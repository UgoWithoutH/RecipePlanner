// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerMultiShuffle on _PlannerPageState {
  /// Lance le multi-shuffle : pour chaque slot non gardé, applique un shuffle
  /// avec accumulation de bans (même logique que le shuffle unitaire).
  Future<void> _launchMultiShuffle() async {
    if (_generatedMealPlan == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Slots libres = futurs non-leftover non verrouillés par l'utilisateur.
    final freeSlotKeys = <String>{};
    for (final m in _generatedMealPlan!.meals) {
      if (m.isLeftoverMeal) continue;
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (mealDay.isBefore(today)) continue;
      final sk = _slotKey(m.date, m.type);
      if (!_multiShuffleKeptSlots.contains(sk)) freeSlotKeys.add(sk);
    }

    // Persister les slots verrouillés futurs (tout sauf les slots libres).
    final futureLockedKeys = _generatedMealPlan!.meals
        .where((m) =>
            !m.isLeftoverMeal &&
            !DateTime(m.date.year, m.date.month, m.date.day).isBefore(today))
        .map((m) => _slotKey(m.date, m.type))
        .where((sk) => !freeSlotKeys.contains(sk))
        .toSet();
    _persistedLockedSlotKeys = futureLockedKeys;
    _saveLockedSlots(futureLockedKeys);

    setState(() {
      _isMultiShuffleMode = false;
      _multiShuffleKeptSlots.clear();
    });

    await _shuffleFreeSlots(freeSlotKeys, isMultiShuffle: true);
  }

  /// Code commun au shuffle unitaire et au shuffle multiple.
  /// [freeSlotKeys] : slot keys (format date_type) des slots à re-générer.
  /// Tous les autres slots futurs non-leftover sont traités comme verrouillés.
  ///
  /// PASSE 1 : pour chaque slot libre (en ordre), l'algo tourne avec le ban
  ///   propre à CE slot uniquement → chaque slot a son propre cycle indépendant.
  ///   Les slots déjà traités sont passés comme contexte pour le suivant.
  /// PASSE 2 : plan final avec tous les repas (verrouillés + nouvelles recettes)
  ///   comme userSelectedMeals → calcule correctement les cascades de restes.
  Future<void> _shuffleFreeSlots(
    Set<String> freeSlotKeys, {
    bool suppressDialogs = false,
    bool isMultiShuffle = false,
  }) async {
    if (_generatedMealPlan == null || freeSlotKeys.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (kDebugMode) {
      debugPrint('[SHUFFLE] ===== _shuffleFreeSlots START =====');
      debugPrint('[SHUFFLE] freeSlotKeys (${freeSlotKeys.length}): $freeSlotKeys');
    }

    // Bannir la recette courante de chaque slot libre dans son ban par slot.
    for (final m in _generatedMealPlan!.meals) {
      if (m.isLeftoverMeal) continue;
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (mealDay.isBefore(today)) continue;
      final sk = _slotKey(m.date, m.type);
      if (!freeSlotKeys.contains(sk)) continue;
      _autoChangeBannedRecipes.putIfAbsent(sk, () => {}).add(m.recipe.id);
    }

    // Log ban state AFTER banning current recipes.
    if (kDebugMode) {
      for (final sk in freeSlotKeys) {
        final banned = _autoChangeBannedRecipes[sk] ?? {};
        debugPrint('[SHUFFLE] BAN state for $sk : ${banned.length} banned = $banned');
      }
    }

    // Repas verrouillés = passés + tous les slots futurs non libres.
    // Exception : les repas RESTES qui se trouvent sur un slot libre mais dont
    // la SOURCE (repas non-reste de même recette et même type) n'est PAS dans
    // les slots libres → ce sont des restes indépendants (d'un autre slot
    // verrouillé) qui doivent rester intacts.
    final lockedMeals = _generatedMealPlan!.meals.where((m) {
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (m.isLeftoverMeal) {
        final sk = _slotKey(m.date, m.type);
        // Reste sur un slot NON libre → exclu (comportement normal, on ne touche pas aux slots non libres via les lockedMeals)
        if (!freeSlotKeys.contains(sk)) return false;
        // Reste sur un slot libre : y inclure seulement si sa source n'est pas elle-même libre.
        if (mealDay.isBefore(today)) return false;
        final sourceIsBeingShuffled = _generatedMealPlan!.meals.any((src) =>
            !src.isLeftoverMeal &&
            src.recipe.id == m.recipe.id &&
            src.type == m.type &&
            freeSlotKeys.contains(_slotKey(src.date, src.type)));
        return !sourceIsBeingShuffled; // lock si la source n'est pas shufflée
      }
      if (mealDay.isBefore(today)) return true;
      return !freeSlotKeys.contains(_slotKey(m.date, m.type));
    }).toList();

    setState(() => _isLoading = true);
    try {
      final recipesRaw = await _loadRecipes();
      final allServings = await _loadServings();
      await _loadUserNames();
      final users = allServings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Résolution des noms d'ingrédients pour la similarité.
      final allIngredientIds = recipesRaw
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final recipesWithNames = recipesRaw.map((recipe) {
        final resolved = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolved);
      }).toList();

        final allCategoryRecipes = _applyPlannerRecipeFilters(recipesWithNames);

      if (kDebugMode) debugPrint('[SHUFFLE] allCategoryRecipes count: ${allCategoryRecipes.length}');

      // Vérification d'épuisement PER-SLOT.
      final exhaustedSlotLabels = <String>[];
      for (int di = 0; di < _generatedMealPlan!.durationDays; di++) {
        final day = _generatedMealPlan!.startDate.add(Duration(days: di));
        if (DateTime(day.year, day.month, day.day).isBefore(today)) continue;
        for (final type in [MealType.lunch, MealType.dinner]) {
          final sk = _slotKey(day, type);
          if (!freeSlotKeys.contains(sk)) continue;
          final slotBanned = _autoChangeBannedRecipes[sk] ?? {};
          final slotIsExhausted = _algoExhaustedSlots.contains(sk) ||
              (allCategoryRecipes.isNotEmpty &&
                  allCategoryRecipes.every((r) => slotBanned.contains(r.id)));
          if (slotIsExhausted) {
            final dayLabel =
                '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
            final typeLabel = type == MealType.lunch ? 'déjeuner' : 'dîner';
            exhaustedSlotLabels.add('$typeLabel du $dayLabel');
          }
        }
      }
      if (kDebugMode) debugPrint('[SHUFFLE] exhaustedSlots (${exhaustedSlotLabels.length}/${freeSlotKeys.length}): $exhaustedSlotLabels');

      // Si TOUS les slots libres sont épuisés, retourner tôt (rien à faire).
      // Si seulement CERTAINS sont épuisés, passe 1 les traitera via failedSlotMeals.
      if (exhaustedSlotLabels.length == freeSlotKeys.length) {
        if (kDebugMode) debugPrint('[SHUFFLE] All slots exhausted → reset bans and early return');
        // Réinitialiser les bans pour ces slots : le cycle repart depuis le début.
        // On reban uniquement la recette actuelle de chaque slot (pour ne pas
        // reproposer immédiatement ce qui est déjà affiché).
        for (final sk in freeSlotKeys) {
          final currentMeal = _generatedMealPlan!.meals
              .where((m) => !m.isLeftoverMeal && _slotKey(m.date, m.type) == sk)
              .firstOrNull;
          _autoChangeBannedRecipes[sk] = currentMeal != null ? {currentMeal.recipe.id} : {};
        }
        _algoExhaustedSlots.removeAll(freeSlotKeys);
        if (!suppressDialogs && mounted) {
          final slotsLabel = exhaustedSlotLabels.length == 1
              ? exhaustedSlotLabels.first
              : exhaustedSlotLabels.join(', ');
          final message = exhaustedSlotLabels.length == 1
              ? 'Toutes les recettes ont été proposées pour $slotsLabel. Les propositions reprennent depuis le début.'
              : 'Toutes les recettes ont été proposées pour : $slotsLabel. Les propositions reprennent depuis le début.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.refresh_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFF6A5AE0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
        return; // Plan inchangé, cycle réinitialisé.
      }

      // Historique pour le contexte de diversité.
      final cutoffDate = now.subtract(Duration(days: _maxHistoryDays));
      final currentUserIds = allServings.map((s) => s.userId).toSet();
      final filteredHistoryMeals = _mealHistory.entries
          .where((entry) => !entry.key.isBefore(cutoffDate))
          .expand((entry) => entry.value)
          .where((meal) =>
              meal.userServings.isEmpty ||
              meal.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      // ── PASSE 1 : sélection per-slot ──────────────────────────────────────
      // Chaque slot utilise UNIQUEMENT son propre ban → les bans des autres
      // slots ne pollent pas son pool. Les slots déjà traités dans cette passe
      // sont passés comme contexte cumulatif (userSelectedMeals) pour le suivant.

      // Slots actuellement VIDES dans le plan (futurs, non libres) : ils ne
      // doivent pas être remplis par l'algo en passe 2, sauf s'ils deviennent
      // un reste légitime de l'une des nouvelles recettes sélectionnées.
      final currentlyEmptyFutureSlotKeys = <String>{};
      for (int di = 0; di < _generatedMealPlan!.durationDays; di++) {
        final day = _generatedMealPlan!.startDate.add(Duration(days: di));
        if (DateTime(day.year, day.month, day.day).isBefore(today)) continue;
        for (final type in [MealType.lunch, MealType.dinner]) {
          final sk = _slotKey(day, type);
          if (freeSlotKeys.contains(sk)) continue;
          final hasMeal = _generatedMealPlan!.meals.any(
              (m) => _slotKey(m.date, m.type) == sk);
          if (!hasMeal) currentlyEmptyFutureSlotKeys.add(sk);
        }
      }

      final freeMeals = _generatedMealPlan!.meals
          .where((m) => !m.isLeftoverMeal && freeSlotKeys.contains(_slotKey(m.date, m.type)))
          .toList()
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          if (d != 0) return d;
          return a.type.index.compareTo(b.type.index);
        });

      final selectedNewMeals = <Meal>[];
      final unfilledLabels = <String>[]; // épuisement des bans
      final contextualFailedLabels = <String>[]; // algo null (contrainte contextuelle)
      final wasteConstrainedLabels = <String>[]; // algo null (no-waste strict en multi-shuffle)
      // Repas actuels des slots libres qui n'ont pas pu être changés (épuisés ou
      // algo sans résultat) → traités comme verrouillés en passe 2 pour ne pas
      // être remplacés par un repas aléatoire.
      final failedSlotMeals = <Meal>[];
      // Slots qui étaient des restes dans l'ancien plan mais dont la nouvelle recette
      // ne produit pas de restes → à laisser vides dans le plan final.
      final slotsToLeaveEmpty = <String>{};

      for (final mealToChange in freeMeals) {
        final sk = _slotKey(mealToChange.date, mealToChange.type);
        final slotBanned = _autoChangeBannedRecipes[sk] ?? {};

        // Slots de restes directement causés par l'ancienne recette de CE slot.
        // On scanne TOUS les slots futurs triés (la chaîne peut sauter un slot,
        // ex : dîner occupé par une autre recette mais déjeuner +1j est quand
        // même un reste de la recette shufflée).
        // On s'arrête dès qu'on croise une NOUVELLE occurrence non-reste de la
        // même recette (début d'une autre chaîne indépendante).
        final oldLeftoverSlotKeys = <String>{};
        {
          final shuffledSlotKey = sk;
          final targetRecipeId = mealToChange.recipe.id;
          // Trier les repas futurs par date+type (lunch avant dinner).
          final futureMeals = _generatedMealPlan!.meals.where((m) {
            final msk = _slotKey(m.date, m.type);
            if (msk == shuffledSlotKey) return false;
            // Les restes d'un slot lunch vont toujours au lunch suivant (slot+2),
            // idem pour dinner. On ne considère donc que le même type de repas
            // pour éviter de confondre deux chaînes independantes du même plat
            // (ex : poulet au dîner J-1 produit un reste au dîner J, tandis que
            // poulet au déjeuner J produit un reste au déjeuner J+1).
            if (m.type != mealToChange.type) return false;
            final mDay = DateTime(m.date.year, m.date.month, m.date.day);
            final sDay = DateTime(mealToChange.date.year, mealToChange.date.month, mealToChange.date.day);
            if (mDay.isBefore(sDay)) return false;
            if (mDay.isAtSameMomentAs(sDay)) return false; // même jour → pas futur
            return true;
          }).toList()
            ..sort((a, b) {
              final da = DateTime(a.date.year, a.date.month, a.date.day);
              final db = DateTime(b.date.year, b.date.month, b.date.day);
              final cmp = da.compareTo(db);
              if (cmp != 0) return cmp;
              // lunch (0) avant dinner (1)
              return a.type.index.compareTo(b.type.index);
            });
          for (final m in futureMeals) {
            if (m.recipe.id != targetRecipeId) continue;
            if (!m.isLeftoverMeal) break; // nouvelle occurrence indépendante
            oldLeftoverSlotKeys.add(_slotKey(m.date, m.type));
          }
        }

        // Contexte : repas verrouillés + slots libres déjà déterminés.
        final allLockedForSlot = [
          ...lockedMeals.map((m) => m.copyWith(userSelected: true)),
          ...selectedNewMeals.map((m) => m.copyWith(userSelected: true)),
        ];

        // Recettes déjà utilisées le même jour (autre slot verrouillé ou déjà
        // sélectionné dans cette passe) → exclure pour éviter les doublons jour.
        final sameDayRecipeIds = allLockedForSlot
            .where((m) =>
                m.date.year == mealToChange.date.year &&
                m.date.month == mealToChange.date.month &&
                m.date.day == mealToChange.date.day)
            .map((m) => m.recipe.id)
            .toSet();

        // Pool = catégorie filtrée moins le ban de CE slot et les doublons jour.
        final slotAvailable = allCategoryRecipes
            .where((r) => !slotBanned.contains(r.id) && !sameDayRecipeIds.contains(r.id))
            .toList();
        if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk : banned=${slotBanned.length}, available=${slotAvailable.length}');
        if (slotAvailable.isEmpty || _algoExhaustedSlots.contains(sk)) {
          if (slotAvailable.isEmpty) _algoExhaustedSlots.add(sk);
          final dayLabel = '${mealToChange.date.day.toString().padLeft(2, '0')}/${mealToChange.date.month.toString().padLeft(2, '0')}';
          final typeLabel = mealToChange.type == MealType.lunch ? 'déjeuner' : 'dîner';
          if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → EXHAUSTED (added to failedSlotMeals, recipe=${mealToChange.recipe.id})');
          unfilledLabels.add('$typeLabel du $dayLabel');
          failedSlotMeals.add(mealToChange);
          continue;
        }

        // Paramètres communs pour les appels à l'algo.
        Future<MealPlan> runPlan(List<Recipe> recipes, {List<Meal>? overrideLocked, bool strict = true}) async {
          final locked = overrideLocked ?? allLockedForSlot;
          return await MealPlanningService.generateMealPlan(
            recipes: recipes,
            servings: allServings,
            users: users,
            startDate: _generatedMealPlan!.startDate,
            durationDays: _generatedMealPlan!.durationDays,
            recentMeals: filteredHistoryMeals,
            userSelectedMeals: locked.isEmpty ? null : locked,
            pantryItems: _pantryIngredients,
            urgentPantryIngredientNames: _urgentPantryNames,
            selectedCategories: _selectedCategories.toList(),
            leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
            similarityPenaltyWeight: 60.0,
            wastePenaltyWeight: 25.0,
            strictNoWaste: strict,
            ignoreHistoryLeftovers: true,
          );
        }
        Meal? pickFromPlan(MealPlan plan) => plan.meals.where(
          (m) => !m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
        ).firstOrNull;

        Meal? newMeal;

        // Si l'ancienne recette avait des restes, on privilégie les recettes
        // qui en produiront aussi (même schéma J+1).
        if (oldLeftoverSlotKeys.isNotEmpty) {
          final leftoverFavored = slotAvailable
              .where((r) => r.servings > mealToChange.totalServings)
              .toList();
          if (leftoverFavored.isNotEmpty) {
            final candidate = pickFromPlan(await runPlan(leftoverFavored));
            if (candidate != null &&
                candidate.recipe.servings * candidate.recipeMultiplier > candidate.totalServings) {
              newMeal = candidate;
            }
          }
        }

        // Fallback : toutes les recettes disponibles pour ce slot.
        final fallbackPlan = await runPlan(slotAvailable);
        newMeal ??= pickFromPlan(fallbackPlan);

        // Si null : vérifier si ce slot est couvert par un reste d'une recette
        // déjà sélectionnée dans ce batch (ex : 30-mai-midi produit des restes
        // qui tombent sur 31-mai-midi, lui aussi libre dans ce même shuffle).
        // Dans ce cas, ne pas chercher une nouvelle recette indépendante —
        // le reste sera injecté naturellement en passe 2.
        if (newMeal == null && selectedNewMeals.isNotEmpty) {
          final batchRecipeIds = selectedNewMeals.map((m) => m.recipe.id).toSet();
          final coveredByBatchLeftover = fallbackPlan.meals.any((m) =>
            m.isLeftoverMeal &&
            _slotKey(m.date, m.type) == sk &&
            batchRecipeIds.contains(m.recipe.id),
          );
          if (coveredByBatchLeftover) {
            if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → covered by batch leftover, skip');
            // L'ancienne recette avait peut-être ses propres restes : les marquer
            // à vider car ce slot sera désormais occupé par un reste du batch.
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
            continue;
          }
        }

        // Si null : un reste cascade exactement sur sk → pickFromPlan filtre
        // isLeftoverMeal → null. On retire itérativement chaque recette source
        // du pool jusqu'à obtenir un plan sans cascade sur sk, ou épuiser le pool.
        bool cascadeUnresolvable = false;
        if (newMeal == null) {
          final poolExcluded = <String>{};
          bool coveredByLeftover = false;
          int safetyLimit = 15; // max itérations pour éviter boucle infinie
          while (newMeal == null && safetyLimit-- > 0) {
            final currentPool = slotAvailable
                .where((r) => !poolExcluded.contains(r.id))
                .toList();
            if (currentPool.isEmpty) break;
            final locked = allLockedForSlot
                .where((m) => !poolExcluded.contains(m.recipe.id))
                .toList();
            final trialPlan = await runPlan(currentPool, overrideLocked: locked);
            final cascading = trialPlan.meals.where(
              (m) => m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
            ).firstOrNull;
            if (cascading == null) {
              // Plus de cascade : tenter de récupérer la recette pour sk.
              newMeal = pickFromPlan(trialPlan);
              // Si null, le slot est peut-être couvert par un reste d'une recette
              // extérieure (hors pool exclu). Dans ce cas, skip comme batch leftover.
              if (newMeal == null) {
                final coveredByAnyLeftover = trialPlan.meals.any((m) =>
                  m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
                );
                if (coveredByAnyLeftover) {
                  coveredByLeftover = true;
                  if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → cascade cleared but covered by external leftover, skip');
                }
              }
              if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → cascade cleared, pool=${currentPool.length}, newMeal=${newMeal?.recipe.id}');
              break;
            }
            poolExcluded.add(cascading.recipe.id);
            if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → leftover-source ${cascading.recipe.id} excluded, poolLeft=${currentPool.length - 1}');
          }
          if (coveredByLeftover) {
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
            continue; // slot sera rempli par le reste en passe 2
          }
          cascadeUnresolvable = newMeal == null && poolExcluded.isNotEmpty;
          if (cascadeUnresolvable) {
            if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → cascade unresolvable after ${poolExcluded.length} exclusions');
          }
        }

        if (newMeal != null) {
          if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → SUCCESS new recipe=${newMeal.recipe.id} (${newMeal.recipe.title})');
          selectedNewMeals.add(newMeal);
          // L'ancienne recette avait des restes : libérer ces slots.
          // La nouvelle recette peut elle aussi produire des restes, mais
          // on ne les injecte pas automatiquement — l'utilisateur a shufflé
          // uniquement la première occurrence, pas les slots suivants.
          if (oldLeftoverSlotKeys.isNotEmpty) {
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
          }
        } else {
          // L'algo a retourné null malgré un pool non vide.
          // Vérifier EN PREMIER si le blocage vient de la contrainte no-waste
          // (recettes restantes produisent trop de restes pour les slots libres)
          // avant de conclure à l'épuisement ou à un blocage contextuel.
          final dayLabel =
              '${mealToChange.date.day.toString().padLeft(2, '0')}/${mealToChange.date.month.toString().padLeft(2, '0')}';
          final typeLabel = mealToChange.type == MealType.lunch ? 'déjeuner' : 'dîner';
          final isWasteConstrained = cascadeUnresolvable ||
              pickFromPlan(await runPlan(slotAvailable, strict: false)) != null;
          if (isWasteConstrained) {
            // Pour un shuffle unitaire, accepter quand même une recette qui produit
            // des restes plutôt que d'échouer (le slot suivant est verrouillé mais
            // l'utilisateur veut juste changer de recette).
            if (!isMultiShuffle) {
              final nonStrictMeal = pickFromPlan(await runPlan(slotAvailable, strict: false));
              if (nonStrictMeal != null) {
                if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → waste-constrained, single-shuffle fallback → ${nonStrictMeal.recipe.id}');
                selectedNewMeals.add(nonStrictMeal);
                if (oldLeftoverSlotKeys.isNotEmpty) {
                  slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
                }
                continue;
              }
            }
            if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO null (waste-constrained, aucune recette sans restes dispo). recipe=${mealToChange.recipe.id}');
            wasteConstrainedLabels.add('$typeLabel du $dayLabel');
          } else {
            // Blocage contextuel (diversité, pantry, etc.).
            // Si presque toutes les recettes ont été essayées, marquer comme épuisé.
            final exhaustionThreshold = (allCategoryRecipes.length * 0.25).ceil();
            if (slotAvailable.length <= exhaustionThreshold) {
              _algoExhaustedSlots.add(sk);
              if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO null (near-exhaustion ${slotAvailable.length}/${allCategoryRecipes.length}, not waste-constrained). recipe=${mealToChange.recipe.id}');
              unfilledLabels.add('$typeLabel du $dayLabel');
            } else {
              if (kDebugMode) debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO returned null (contextual, ${slotAvailable.length} available preserved). recipe=${mealToChange.recipe.id}');
              contextualFailedLabels.add('$typeLabel du $dayLabel');
            }
          }
          failedSlotMeals.add(mealToChange);
        }
      }

      if (kDebugMode) {
        debugPrint('[SHUFFLE] Passe1 END: selectedNewMeals=${selectedNewMeals.map((m) => '${_slotKey(m.date, m.type)}=${m.recipe.id}').toList()}');
        debugPrint('[SHUFFLE] Passe1 END: failedSlotMeals=${failedSlotMeals.map((m) => '${_slotKey(m.date, m.type)}=${m.recipe.id}').toList()}');
      }

      // Signaler les slots non remplis.
      if (unfilledLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = unfilledLabels.length == 1 && freeSlotKeys.length == 1
              ? 'Toutes les recettes ont été proposées pour ce créneau.'
              : 'Toutes les recettes ont été proposées pour : ${unfilledLabels.join(', ')}.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFF6A5AE0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
      }
      if (contextualFailedLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = contextualFailedLabels.length == 1 && freeSlotKeys.length == 1
              ? 'Impossible de trouver une recette adaptée pour ce créneau. Réessayez ou déverrouillez des repas voisins.'
              : 'Impossible de trouver une recette pour : ${contextualFailedLabels.join(', ')}. Réessayez ou déverrouillez des repas voisins.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFFE06A5A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
      }
      if (wasteConstrainedLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = wasteConstrainedLabels.length == 1
              ? 'Aucune recette sans restes gaspillés n\'est disponible pour le ${wasteConstrainedLabels.first}. Déverrouillez des repas voisins pour que les restes puissent être absorbés.'
              : 'Aucune recette sans restes gaspillés pour : ${wasteConstrainedLabels.join(', ')}. Déverrouillez des repas voisins pour que les restes puissent être absorbés.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.no_food_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFFFF9800),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 8),
          ));
        }
      }
      {
        // Si aucun slot n'a pu être mis à jour, tout le plan reste inchangé.
        if (selectedNewMeals.isEmpty) return;
      }

      // ── PASSE 2 : plan final ──────────────────────────────────────────────
      // Tous les repas (verrouillés + nouvelles recettes + slots échoués) sont
      // passés comme userSelectedMeals. L'algo calcule les cascades de restes
      // sur le plan complet de façon cohérente.
      // Les slots échoués (épuisés) sont verrouillés sur leur recette actuelle.
      // On verrouille aussi TOUS les repas de l'ancien plan qui ne sont ni
      // shufflés ni à vider : empêche l'algo de remplir des slots "spectateurs"
      // avec de nouvelles recettes (ex : 6-3_lunch leftover d'une autre source).
      final alreadyCoveredSlots = {
        ...lockedMeals.map((m) => _slotKey(m.date, m.type)),
        ...failedSlotMeals.map((m) => _slotKey(m.date, m.type)),
        ...selectedNewMeals.map((m) => _slotKey(m.date, m.type)),
      };
      // Repas co-localisés sur un free slot mais qui ne sont PAS le repas shufflé
      // (ex : steak haché + purée sur 25/6 midi où crêpes est le nouveau repas).
      // Ces repas ne sont dans aucun des sets ci-dessus et doivent être préservés.
      final coLocatedMainMeals = _generatedMealPlan!.meals.where((m) {
        if (m.isLeftoverMeal) return false;
        final sk = _slotKey(m.date, m.type);
        if (!freeSlotKeys.contains(sk)) return false;
        if (DateTime(m.date.year, m.date.month, m.date.day).isBefore(today)) return false;
        // Ne garder que les repas principaux du free slot absents de selectedNewMeals
        // et de failedSlotMeals (ils coexistent dans un slot partagé).
        return !selectedNewMeals.any((n) => n.recipe.id == m.recipe.id && _slotKey(n.date, n.type) == sk)
            && !failedSlotMeals.any((f) => f.recipe.id == m.recipe.id && _slotKey(f.date, f.type) == sk);
      }).map((m) => m.copyWith(userSelected: true)).toList();
      final preservedOriginalMeals = _generatedMealPlan!.meals.where((m) {
        final sk = _slotKey(m.date, m.type);
        if (freeSlotKeys.contains(sk)) return false;        // slot shufflé
        if (slotsToLeaveEmpty.contains(sk)) return false;   // slot à vider
        if (alreadyCoveredSlots.contains(sk)) return false; // déjà verrouillé
        if (DateTime(m.date.year, m.date.month, m.date.day)
            .isBefore(today)) return false;
        return true;
      }).map((m) => m.copyWith(userSelected: true)).toList();

      final allUserSelectedFinal = [
        ...lockedMeals.map((m) => m.copyWith(userSelected: true)),
        ...failedSlotMeals.map((m) => m.copyWith(userSelected: true)),
        ...selectedNewMeals.map((m) => m.copyWith(userSelected: true)),
        ...coLocatedMainMeals,
        ...preservedOriginalMeals,
      ];
      if (kDebugMode) {
        debugPrint('[SHUFFLE] Passe2 allUserSelectedFinal (${allUserSelectedFinal.length}):');
        for (final m in allUserSelectedFinal) {
          debugPrint('[SHUFFLE]   ${_slotKey(m.date, m.type)} recipe=${m.recipe.id} (${m.recipe.title}) leftover=${m.isLeftoverMeal} userSelected=${m.userSelected}');
        }
      }

      final finalPlan = await MealPlanningService.generateMealPlan(
        recipes: allCategoryRecipes, // pool complet (tous les slots sont verrouillés)
        servings: allServings,
        users: users,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        recentMeals: filteredHistoryMeals,
        userSelectedMeals: allUserSelectedFinal.isEmpty ? null : allUserSelectedFinal,
        pantryItems: _pantryIngredients,
        urgentPantryIngredientNames: _urgentPantryNames,
        selectedCategories: _selectedCategories.toList(),
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
        similarityPenaltyWeight: 60.0,
        wastePenaltyWeight: 25.0,
        ignoreHistoryLeftovers: true,
      );

      // Supprimer les repas non-leftover dans les slots marqués vides
      // (anciens slots de restes dont la nouvelle recette ne produit pas de restes).
      // Aussi supprimer tout repas placé par l'algo dans un slot qui était vide
      // avant ce shuffle, sauf s'il s'agit d'un reste dérivé d'une des nouvelles recettes.
      final selectedNewRecipeIds = selectedNewMeals.map((m) => m.recipe.id).toSet();
      MealPlan planToSave = finalPlan.copyWith(id: _generatedMealPlan!.id);
      {
        final prunedMeals = planToSave.meals.where((m) {
          final sk = _slotKey(m.date, m.type);
          // Anciens slots de restes libérés par le shuffle.
          // On garde uniquement les restes de la nouvelle recette sélectionnée
          // (si elle produit elle-même des restes qui tombent sur ces slots).
          // Tout autre repas (y compris les restes de l'ancienne recette) est supprimé.
          if (slotsToLeaveEmpty.contains(sk)) {
            return m.isLeftoverMeal && selectedNewRecipeIds.contains(m.recipe.id);
          }
          // Slots qui étaient vides avant ce shuffle : ne garder que les restes
          // légitimes des nouvelles recettes sélectionnées.
          if (currentlyEmptyFutureSlotKeys.contains(sk)) {
            return m.isLeftoverMeal && selectedNewRecipeIds.contains(m.recipe.id);
          }
          return true;
        }).toList();

        // Snackbar pour les slots réellement laissés vides (non couverts par la
        // nouvelle recette).
        final trulyVacatedSlots = slotsToLeaveEmpty
            .where((sk) => !prunedMeals.any((m) => _slotKey(m.date, m.type) == sk))
            .toSet();
        if (trulyVacatedSlots.isNotEmpty) {
          final vacatedLabels = <String>[];
          for (int di = 0; di < planToSave.durationDays; di++) {
            final day = planToSave.startDate.add(Duration(days: di));
            for (final type in [MealType.lunch, MealType.dinner]) {
              final sk = _slotKey(day, type);
              if (!trulyVacatedSlots.contains(sk)) continue;
              final dayLabel = '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
              final typeLabel = type == MealType.lunch ? 'déjeuner' : 'dîner';
              vacatedLabels.add('$typeLabel du $dayLabel');
            }
          }
          if (!suppressDialogs && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  'La recette a changé — les restes de l\'ancienne recette ont été supprimés. ${vacatedLabels.length == 1 ? 'Créneau maintenant libre' : 'Créneaux maintenant libres'} : ${vacatedLabels.join(', ')}.',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                )),
              ]),
              backgroundColor: const Color(0xFF6A5AE0),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 6),
            ));
          }
        }

        planToSave = planToSave.copyWith(meals: prunedMeals);
      }

      // ── Re-inject co-located leftovers dropped by generateMealPlan ────────
      // When a free slot has both a new main meal (crêpes) AND a leftover from
      // another source (croque monsieur [RESTE]), generateMealPlan may silently
      // drop the leftover because it sees the slot already occupied by the main
      // meal.  Locked leftovers on free slots are in lockedMeals; re-add any
      // that are missing from the pruned plan.
      {
        final coLocatedLockedLeftovers = lockedMeals.where((m) => m.isLeftoverMeal).toList();
        if (coLocatedLockedLeftovers.isNotEmpty) {
          final reinjectedMeals = planToSave.meals.toList();
          for (final leftover in coLocatedLockedLeftovers) {
            final sk = _slotKey(leftover.date, leftover.type);
            final alreadyPresent = reinjectedMeals.any((m) =>
                m.isLeftoverMeal &&
                m.recipe.id == leftover.recipe.id &&
                _slotKey(m.date, m.type) == sk);
            if (!alreadyPresent) {
              if (kDebugMode) debugPrint('[SHUFFLE] Re-inject co-located leftover ${leftover.recipe.title} @ $sk');
              reinjectedMeals.add(leftover);
            }
          }
          if (reinjectedMeals.length != planToSave.meals.length) {
            planToSave = planToSave.copyWith(meals: reinjectedMeals);
          }
        }
      }

      // ── Re-inject selectedNewMeals dropped by generateMealPlan ────────────
      // The reverse situation: the slot also has a co-located leftover, and
      // generateMealPlan keeps the leftover but drops the new main meal.
      // Re-add any selectedNewMeal that is absent from the final plan.
      {
        final reinjectedMeals = planToSave.meals.toList();
        for (final newMeal in selectedNewMeals) {
          final sk = _slotKey(newMeal.date, newMeal.type);
          final alreadyPresent = reinjectedMeals.any((m) =>
              !m.isLeftoverMeal &&
              m.recipe.id == newMeal.recipe.id &&
              _slotKey(m.date, m.type) == sk);
          if (!alreadyPresent) {
            if (kDebugMode) debugPrint('[SHUFFLE] Re-inject dropped new meal ${newMeal.recipe.title} @ $sk');
            reinjectedMeals.add(newMeal);
          }
        }
        if (reinjectedMeals.length != planToSave.meals.length) {
          planToSave = planToSave.copyWith(meals: reinjectedMeals);
        }
      }

      await _mealPlanRepo.saveMealPlan(planToSave);
      await ShoppingListGenerator().generateAndSaveShoppingList(planToSave);

      if (mounted) setState(() => _generatedMealPlan = planToSave);
      _showWastedLeftoversSnackbar(planToSave);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
