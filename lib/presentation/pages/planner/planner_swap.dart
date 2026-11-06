// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerSwap on _PlannerPageState {
  /// Échange les recettes de deux slots, en déplaçant leurs restes pour suivre
  /// leurs nouveaux parents. Propose une réorganisation quand les chaînes de
  /// restes sont inégales et qu'un repas existant serait écrasé.
  Future<void> _swapMeals(Meal source, Meal target) async {
    if (_generatedMealPlan == null) return;
    setState(() { _swapSourceMeal = null; _isLoading = true; });
    try {
      final allMeals = List<Meal>.from(_generatedMealPlan!.meals);
      final sameType = source.type == target.type;

      debugPrint('[SWAP] ===== _swapMeals START =====');
      debugPrint('[SWAP] SOURCE: ${source.recipe.title} @ ${_slotKey(source.date, source.type)} leftover=${source.isLeftoverMeal}');
      debugPrint('[SWAP] TARGET: ${target.recipe.title} @ ${_slotKey(target.date, target.type)} leftover=${target.isLeftoverMeal}');
      debugPrint('[SWAP] sameType=$sameType');

      // ── 1. Collect leftover chains ──────────────────────────────────────────
      // Les restes suivent toujours leur parent (même type qu'eux), quel que
      // soit le type du slot cible — _getConsecutiveLeftoversOfMeal filtre déjà
      // par m.type == mainMeal.type.
      final srcLeftovers = _getConsecutiveLeftoversOfMeal(source, allMeals);
      final tgtLeftovers = _getConsecutiveLeftoversOfMeal(target, allMeals);
      final N = srcLeftovers.length;
      final M = tgtLeftovers.length;

      debugPrint('[SWAP] srcLeftovers ($N): ${srcLeftovers.map((m) => '${m.recipe.title}@${_slotKey(m.date, m.type)}').toList()}');
      debugPrint('[SWAP] tgtLeftovers ($M): ${tgtLeftovers.map((m) => '${m.recipe.title}@${_slotKey(m.date, m.type)}').toList()}');

      final srcDay = DateTime(source.date.year, source.date.month, source.date.day);
      final tgtDay = DateTime(target.date.year, target.date.month, target.date.day);

      final srcLeftoverKeys = srcLeftovers.map(_mealKey).toSet();
      final tgtLeftoverKeys = tgtLeftovers.map(_mealKey).toSet();
      final srcKey = _mealKey(source);
      final tgtKey = _mealKey(target);

      // ── 2. Compute new leftover positions ───────────────────────────────────
      // Source's leftovers (type = source.type) move after tgtDay.
      // Target's leftovers (type = target.type) move after srcDay.
      // Each chain skips the day that now hosts the other main meal (same type
      // conflict), and searches further if needed to place all N / M leftovers.
      final planStart = DateTime(_generatedMealPlan!.startDate.year,
          _generatedMealPlan!.startDate.month, _generatedMealPlan!.startDate.day);
      final planEnd = planStart.add(Duration(days: _generatedMealPlan!.durationDays));

      bool isInPlan(DateTime d) => !d.isBefore(planStart) && d.isBefore(planEnd);

      // src leftovers take type=target.type after the swap.
      // Block tgtDay (source meal is there at target.type).
      // Block srcDay only if sameType (target meal is there at source.type == target.type).
      bool isBlockedForSrcLeftover(DateTime d) {
        if (d.year == tgtDay.year && d.month == tgtDay.month && d.day == tgtDay.day) return true;
        if (sameType && d.year == srcDay.year && d.month == srcDay.month && d.day == srcDay.day) return true;
        return false;
      }
      // tgt leftovers take type=source.type after the swap.
      // Block srcDay (target meal is there at source.type).
      // Block tgtDay only if sameType (source meal is there at target.type == source.type).
      bool isBlockedForTgtLeftover(DateTime d) {
        if (d.year == srcDay.year && d.month == srcDay.month && d.day == srcDay.day) return true;
        if (sameType && d.year == tgtDay.year && d.month == tgtDay.month && d.day == tgtDay.day) return true;
        return false;
      }

      // Search the first N available days after tgtDay for src leftovers.
      final srcNewPositions = <DateTime>[];
      for (int i = 1; srcNewPositions.length < N; i++) {
        final d = tgtDay.add(Duration(days: i));
        if (!isInPlan(d)) break;
        if (isBlockedForSrcLeftover(d)) continue;
        srcNewPositions.add(d);
      }
      // Search the first M available days after srcDay for tgt leftovers.
      final tgtNewPositions = <DateTime>[];
      for (int i = 1; tgtNewPositions.length < M; i++) {
        final d = srcDay.add(Duration(days: i));
        if (!isInPlan(d)) break;
        if (isBlockedForTgtLeftover(d)) continue;
        tgtNewPositions.add(d);
      }

      debugPrint('[SWAP] srcNewPositions: ${srcNewPositions.map((d) => '${d.day}/${d.month}').toList()}');
      debugPrint('[SWAP] tgtNewPositions: ${tgtNewPositions.map((d) => '${d.day}/${d.month}').toList()}');

      // ── 3. Find displaced meals & empty slots ───────────────────────────────
      // A displaced meal is any meal at an "extra" new-leftover position that is
      // not itself a src/tgt leftover (those are being moved already).
      final List<Meal> displacedMeals = [];
      final List<DateTime> emptySlots = [];

      if (N > M) {
        // Source has more leftovers: extra positions srcNewPositions[M..end]
        // src leftovers have new type = target.type, so displaced meals have that type too.
        for (int i = M; i < srcNewPositions.length; i++) {
          final slotDate = srcNewPositions[i];
          final displaced = allMeals.where((m) {
            if (m.type != target.type) return false;
            final mDay = DateTime(m.date.year, m.date.month, m.date.day);
            if (mDay.year != slotDate.year || mDay.month != slotDate.month || mDay.day != slotDate.day) return false;
            final mk = _mealKey(m);
            if (mk == srcKey || mk == tgtKey) return false;
            if (srcLeftoverKeys.contains(mk) || tgtLeftoverKeys.contains(mk)) return false;
            return true;
          }).toList();
          displacedMeals.addAll(displaced);
        }
        // Empty slots: old src leftover positions beyond what target needs
        for (int i = M; i < N; i++) {
          emptySlots.add(DateTime(srcLeftovers[i].date.year,
              srcLeftovers[i].date.month, srcLeftovers[i].date.day));
        }
      } else if (M > N) {
        // Target has more leftovers: extra positions tgtNewPositions[N..end]
        // tgt leftovers have new type = source.type, so displaced meals have that type too.
        for (int i = N; i < tgtNewPositions.length; i++) {
          final slotDate = tgtNewPositions[i];
          final displaced = allMeals.where((m) {
            if (m.type != source.type) return false;
            final mDay = DateTime(m.date.year, m.date.month, m.date.day);
            if (mDay.year != slotDate.year || mDay.month != slotDate.month || mDay.day != slotDate.day) return false;
            final mk = _mealKey(m);
            if (mk == srcKey || mk == tgtKey) return false;
            if (srcLeftoverKeys.contains(mk) || tgtLeftoverKeys.contains(mk)) return false;
            return true;
          }).toList();
          displacedMeals.addAll(displaced);
        }
        // Empty slots: old tgt leftover positions beyond what source needs
        for (int i = N; i < M; i++) {
          emptySlots.add(DateTime(tgtLeftovers[i].date.year,
              tgtLeftovers[i].date.month, tgtLeftovers[i].date.day));
        }
      }

      debugPrint('[SWAP] displacedMeals (${displacedMeals.length}): ${displacedMeals.map((m) => '${m.recipe.title}@${_slotKey(m.date, m.type)}').toList()}');
      debugPrint('[SWAP] emptySlots (${emptySlots.length}): ${emptySlots.map((d) => '${d.day}/${d.month}').toList()}');

      // ── 4. Ask for reorganisation if needed ─────────────────────────────────
      bool reorganize = false;
      if (displacedMeals.isNotEmpty && mounted) {
        debugPrint('[SWAP] → showing reorganize dialog');
        setState(() => _isLoading = false);
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A5AE0).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.compare_arrows_rounded,
                      color: Color(0xFF6A5AE0), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Réorganiser le plan ?',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ],
            ),
            content: Text(
              'Ces deux repas n\'ont pas le même nombre de restes.\n\n'
              '${displacedMeals.length} repas ${displacedMeals.length == 1 ? 'sera déplacé' : 'seront déplacés'} '
              'par les nouveaux restes. Voulez-vous les replacer dans les créneaux libérés ?',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: Colors.black54),
                child: Text('Non', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A5AE0),
                  foregroundColor: Colors.white,
                ),
                child: Text('Oui, réorganiser',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );
        if (result == null) return; // dialog dismissed without choice
        reorganize = result;
        debugPrint('[SWAP] user chose reorganize=$reorganize');
        setState(() => _isLoading = true);
      }

      // ── 5. Build updated meal list ──────────────────────────────────────────
      final toRemoveKeys = <String>{srcKey, tgtKey};
      for (final m in srcLeftovers) toRemoveKeys.add(_mealKey(m));
      for (final m in tgtLeftovers) toRemoveKeys.add(_mealKey(m));
      // In YES case, displaced meals are removed so they can be re-placed.
      if (reorganize) {
        for (final m in displacedMeals) toRemoveKeys.add(_mealKey(m));
      }

      debugPrint('[SWAP] toRemoveKeys (${toRemoveKeys.length}): $toRemoveKeys');

      final newMeals = allMeals.where((m) => !toRemoveKeys.contains(_mealKey(m))).toList();

      // Swap main meals: date AND type are exchanged so each meal lands on
      // the exact slot (day + meal type) previously occupied by the other.
      newMeals.add(source.copyWith(date: tgtDay, type: target.type));
      newMeals.add(target.copyWith(date: srcDay, type: source.type));
      debugPrint('[SWAP] main swap: ${source.recipe.title} → ${tgtDay.day}/${tgtDay.month} ${target.type.name}, ${target.recipe.title} → ${srcDay.day}/${srcDay.month} ${source.type.name}');

      // Place source's leftovers after tgtDay.
      for (int i = 0; i < srcNewPositions.length && i < N; i++) {
        final newDate = srcNewPositions[i];
        if (!reorganize && N > M && i >= M) {
          // NO mode: skip if a displaced meal is already occupying this slot.
          final hasDisplaced = displacedMeals.any((dm) {
            final dmDay = DateTime(dm.date.year, dm.date.month, dm.date.day);
            return dmDay.year == newDate.year && dmDay.month == newDate.month && dmDay.day == newDate.day;
          });
          if (hasDisplaced) {
            debugPrint('[SWAP] srcLeftover[$i] skipped (slot ${newDate.day}/${newDate.month} occupied by displaced meal)');
            continue;
          }
        }
        debugPrint('[SWAP] srcLeftover[$i] ${srcLeftovers[i].recipe.title} → ${newDate.day}/${newDate.month} ${target.type.name}');
        newMeals.add(srcLeftovers[i].copyWith(date: newDate, type: target.type));
      }

      // Place target's leftovers after srcDay.
      for (int i = 0; i < tgtNewPositions.length && i < M; i++) {
        final newDate = tgtNewPositions[i];
        if (!reorganize && M > N && i >= N) {
          final hasDisplaced = displacedMeals.any((dm) {
            final dmDay = DateTime(dm.date.year, dm.date.month, dm.date.day);
            return dmDay.year == newDate.year && dmDay.month == newDate.month && dmDay.day == newDate.day;
          });
          if (hasDisplaced) {
            debugPrint('[SWAP] tgtLeftover[$i] skipped (slot ${newDate.day}/${newDate.month} occupied by displaced meal)');
            continue;
          }
        }
        debugPrint('[SWAP] tgtLeftover[$i] ${tgtLeftovers[i].recipe.title} → ${newDate.day}/${newDate.month} ${source.type.name}');
        newMeals.add(tgtLeftovers[i].copyWith(date: newDate, type: source.type));
      }

      // YES mode: move displaced meals into the freed-up empty slots.
      if (reorganize) {
        // Determine the correct type for the freed-up slots:
        // - N > M: empty slots come from freed src leftover positions → source.type
        // - M > N: empty slots come from freed tgt leftover positions → target.type
        final emptySlotType = N > M ? source.type : target.type;

        // Diversity-aware scoring: for a given displaced meal and a candidate slot
        // date, return a score (lower = better) based on three criteria:
        //  1. Same-day same-recipe conflict  → +1000 (hard block)
        //  2. Recency: same recipe within 4 days in [context] → proportional penalty
        //  3. Ingredient similarity (Jaccard) to adjacent meals (±1 day) → weighted penalty
        double scoreDisplaced(Meal dm, DateTime slotDay, List<Meal> context) {
          double score = 0.0;
          const int recencyWindow = 4;

          final dmIngredients = dm.recipe.ingredients
              .map((i) => i.ingredient.name.toLowerCase().trim())
              .where((n) => n.isNotEmpty)
              .toSet();

          for (final m in context) {
            if (m.isLeftoverMeal) continue;
            final mDay = DateTime(m.date.year, m.date.month, m.date.day);
            final daysDiff = slotDay.difference(mDay).inDays.abs();

            // 1. Same-day same-recipe
            if (daysDiff == 0 && m.recipe.id == dm.recipe.id) {
              score += 1000.0;
              continue;
            }

            // 2. Recency penalty
            if (m.recipe.id == dm.recipe.id && daysDiff < recencyWindow) {
              score += (recencyWindow - daysDiff) * 25.0;
            }

            // 3. Ingredient similarity to same-day and ±1-day meals
            if (daysDiff <= 1 && dmIngredients.isNotEmpty) {
              final otherIngredients = m.recipe.ingredients
                  .map((i) => i.ingredient.name.toLowerCase().trim())
                  .where((n) => n.isNotEmpty)
                  .toSet();
              if (otherIngredients.isNotEmpty) {
                final union = dmIngredients.union(otherIngredients).length;
                final intersection = dmIngredients.intersection(otherIngredients).length;
                if (union > 0) {
                  final jaccard = intersection / union;
                  final proximity = daysDiff == 0 ? 2.0 : 1.0;
                  score += jaccard * 60.0 * proximity;
                }
              }
            }
          }
          return score;
        }

        // Greedy assignment: for each displaced meal, pick the lowest-scoring slot.
        // The meal just placed is added to [newMeals] so it becomes context for the
        // next displaced meal (avoids two displaced meals landing on adjacent days
        // with similar ingredients).
        final availableEmptySlots = List<DateTime>.from(emptySlots);
        for (final dm in displacedMeals) {
          if (availableEmptySlots.isEmpty) break;

          int bestIdx = 0;
          double bestScore = double.infinity;
          for (int si = 0; si < availableEmptySlots.length; si++) {
            final s = scoreDisplaced(dm, availableEmptySlots[si], newMeals);
            if (kDebugMode) debugPrint('[SWAP] displaced[${dm.recipe.title}] candidate ${availableEmptySlots[si].day}/${availableEmptySlots[si].month} score=$s');
            if (s < bestScore) { bestScore = s; bestIdx = si; }
          }
          final chosenSlot = availableEmptySlots.removeAt(bestIdx);
          debugPrint('[SWAP] displaced[${dm.recipe.title}] → ${chosenSlot.day}/${chosenSlot.month} ${emptySlotType.name} (score=$bestScore)');
          final placed = dm.copyWith(date: chosenSlot, type: emptySlotType);
          newMeals.add(placed); // mise à jour du contexte pour le repas déplacé suivant
        }
      }

      debugPrint('[SWAP] final meal count: ${newMeals.length} (was ${allMeals.length})');

      // ── Log plan après swap ─────────────────────────────────────────────────
      debugPrint('[SWAP] ===== Plan après swap =====');
      final swapMealsByDay = <String, List<Meal>>{};
      for (final m in newMeals) {
        final key = '${m.date.year}-${m.date.month.toString().padLeft(2,'0')}-${m.date.day.toString().padLeft(2,'0')}';
        swapMealsByDay.putIfAbsent(key, () => []).add(m);
      }
      for (final day in (swapMealsByDay.keys.toList()..sort())) {
        final dayMeals = swapMealsByDay[day]!..sort((a, b) => a.type.index.compareTo(b.type.index));
        for (final m in dayMeals) {
          final type = m.type == MealType.lunch ? 'MIDI' : 'SOIR';
          final leftover = m.isLeftoverMeal ? ' [RESTE]' : '';
          final portions = m.userServings.isEmpty
              ? '${m.totalServings}p'
              : m.userServings.entries.map((e) => '${e.key.substring(0,6)}:${e.value}p').join(', ');
          debugPrint('[SWAP]   $day $type | ${m.recipe.title}$leftover  ($portions)');
        }
      }
      debugPrint('[SWAP] ================================');

      // ── 6. Save ─────────────────────────────────────────────────────────────
      final updatedPlan = _generatedMealPlan!.copyWith(meals: newMeals);
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
      if (mounted) setState(() => _generatedMealPlan = updatedPlan);

      debugPrint('[SWAP] ===== _swapMeals DONE =====');

      // ── Warn about same-day recipe duplicates created by the swap ────────────
      // This can happen when the target meal's recipe already appears on the
      // source's day (or vice-versa) — the main swap has no way to avoid it
      // since the user explicitly chose those two slots.
      if (mounted) {
        final sameDayDuplicates = <String>[];
        // Group non-leftover meals by (normalised day, recipeId).
        final dayRecipeCount = <String, int>{};
        for (final m in newMeals) {
          if (m.isLeftoverMeal) continue;
          final dayKey = '${m.date.year}-${m.date.month}-${m.date.day}_${m.recipe.id}';
          dayRecipeCount[dayKey] = (dayRecipeCount[dayKey] ?? 0) + 1;
        }
        for (final entry in dayRecipeCount.entries) {
          if (entry.value < 2) continue;
          final parts = entry.key.split('_');
          final dayParts = parts[0].split('-');
          final recipeId = parts[1];
          final meal = newMeals.firstWhere(
            (m) => m.recipe.id == recipeId && !m.isLeftoverMeal,
            orElse: () => newMeals.first,
          );
          sameDayDuplicates.add(
            '${meal.recipe.title} × ${entry.value} le ${dayParts[2]}/${dayParts[1]}',
          );
        }
        if (sameDayDuplicates.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: Colors.amber[800],
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('Doublon dans le plan',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                ]),
                const SizedBox(height: 4),
                ...sameDayDuplicates.map((s) => Text('• $s',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white))),
              ],
            ),
          ));
        }
      }

      // ── 7. Detect empty slots & optionally fill them ────────────────────────
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final filledSlotKeys = newMeals
          .map((m) => _slotKey(m.date, m.type))
          .toSet();
      final emptyFutureSlotKeys = <String>{};
      for (int d = 0; d < _generatedMealPlan!.durationDays; d++) {
        final day = planStart.add(Duration(days: d));
        if (day.isBefore(today)) continue;
        for (final type in MealType.values) {
          final sk = _slotKey(day, type);
          if (!filledSlotKeys.contains(sk)) emptyFutureSlotKeys.add(sk);
        }
      }
      debugPrint('[SWAP] emptyFutureSlotKeys après swap (${emptyFutureSlotKeys.length}): $emptyFutureSlotKeys');

      if (emptyFutureSlotKeys.isNotEmpty && mounted) {
        final fillResult = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A5AE0).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant_menu_rounded,
                      color: Color(0xFF6A5AE0), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${emptyFutureSlotKeys.length} créneau${emptyFutureSlotKeys.length > 1 ? 'x' : ''} vide${emptyFutureSlotKeys.length > 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              'L\'échange de recette a laissé ${emptyFutureSlotKeys.length == 1 ? 'un créneau vide' : '${emptyFutureSlotKeys.length} créneaux vides'} dans le plan.\n\nVoulez-vous générer ${emptyFutureSlotKeys.length == 1 ? 'un repas' : 'des repas'} pour les remplir ?',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: Colors.black54),
                child: Text('Non', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A5AE0),
                  foregroundColor: Colors.white,
                ),
                child: Text('Oui, générer',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );
        if (fillResult == true && mounted) {
          debugPrint('[SWAP] → filling empty slots with _fillVacatedSlots: $emptyFutureSlotKeys');
          await _fillVacatedSlots(onlySlotKeys: emptyFutureSlotKeys);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Repas échangés !',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
          backgroundColor: const Color(0xFF6A5AE0),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shuffle unitaire : verrouille tous les autres slots et délègue à _shuffleFreeSlots.
  Future<void> _autoChangeMealRecipe(
    Meal mealToChange, {
    bool suppressDialogs = false,
  }) async {
    // Cas particulier : le repas à shuffler est un reste sur un slot partagé avec
    // un repas principal (slot fractionné). _shuffleFreeSlots traiterait tout le
    // slot comme libre et écraserait le repas de l'autre utilisateur.
    // Dans ce cas, on retire simplement ce reste du plan sans toucher aux autres repas.
    if (mealToChange.isLeftoverMeal && _generatedMealPlan != null) {
      final sk = _slotKey(mealToChange.date, mealToChange.type);
      final hasSiblingMain = _generatedMealPlan!.meals.any(
        (m) => !m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
      );
      if (hasSiblingMain) {
        setState(() => _isLoading = true);
        try {
          final updatedMeals = _generatedMealPlan!.meals
              .where((m) => !(
                  m.isLeftoverMeal &&
                  m.recipe.id == mealToChange.recipe.id &&
                  _slotKey(m.date, m.type) == sk))
              .toList();
          final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
          await _mealPlanRepo.saveMealPlan(updatedPlan);
          await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
          if (mounted) setState(() => _generatedMealPlan = updatedPlan);
          _showWastedLeftoversSnackbar(updatedPlan);
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
        return;
      }
    }
    await _shuffleFreeSlots(
      {_slotKey(mealToChange.date, mealToChange.type)},
      suppressDialogs: suppressDialogs,
    );
  }

  /// Auto-fills an empty meal slot by picking a recipe with the planning algorithm.
  Future<void> _autoFillEmptySlot(DateTime date, MealType type) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allRecipesRaw = await _loadRecipes();
      final servings = await _loadServings();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Résoudre les noms d'ingrédients pour la similarité.
      final allIngredientIds = allRecipesRaw
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final allRecipes = allRecipesRaw.map((recipe) {
        final resolved = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolved);
      }).toList();

      // Apply category filter (same as _launchPlanning)
        final filteredRecipes = _applyPlannerRecipeFilters(allRecipes);

      if (filteredRecipes.isEmpty) return;

      final currentUserIds = servings.map((s) => s.userId).toSet();
      final filteredHistory = _mealHistory.entries
          .expand((e) => e.value)
          .where((m) => m.userServings.isEmpty ||
              m.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      final otherPlanMeals = _generatedMealPlan?.meals
          .where((m) => !(m.date.year == date.year &&
              m.date.month == date.month &&
              m.date.day == date.day &&
              m.type == type))
          .toList() ??
          [];

      // Compter les slots libres futurs (même type) pour le check leftover.
      final planEndFill = _generatedMealPlan?.startDate
          .add(Duration(days: (_generatedMealPlan?.durationDays ?? 1) - 1));
      int freeFollowingFill = 0;
      if (planEndFill != null) {
        DateTime checkFill = date.add(const Duration(days: 1));
        final endNorm = DateTime(planEndFill.year, planEndFill.month, planEndFill.day);
        while (!DateTime(checkFill.year, checkFill.month, checkFill.day).isAfter(endNorm)) {
          final occupied = _generatedMealPlan!.meals.any((m) =>
              m.date.year == checkFill.year &&
              m.date.month == checkFill.month &&
              m.date.day == checkFill.day &&
              m.type == type);
          if (!occupied) freeFollowingFill++;
          checkFill = checkFill.add(const Duration(days: 1));
        }
      }

      Future<Meal?> _runFillAlgo(List<Recipe> recipes) async {
        final plan = await MealPlanningService.generateMealPlan(
          recipes: recipes,
          servings: servings,
          users: users,
          startDate: date,
          durationDays: 1,
          recentMeals: [...filteredHistory, ...otherPlanMeals],
          pantryItems: _pantryIngredients,
          selectedCategories: _selectedCategories.toList(),
          referenceDate: date,
        );
        return plan.meals.where((m) => m.type == type).firstOrNull;
      }

      // Première passe : algo sans restriction.
      Meal? newMeal = await _runFillAlgo(filteredRecipes);
      if (newMeal == null) return;

      // Post-check : si aucun slot libre et la recette produit des restes, relancer avec filtre.
      if (freeFollowingFill == 0) {
        final cooked = newMeal.recipe.servings * newMeal.recipeMultiplier;
        if (cooked > newMeal.totalServings) {
          final actualConsumed = newMeal.totalServings;
          final noLeftover = filteredRecipes
              .where((r) => r.servings > 0 && actualConsumed % r.servings == 0)
              .toList();
          if (noLeftover.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour ce créneau. Slot inchangé.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            return;
          }
          final attempt2 = await _runFillAlgo(noLeftover);
          final cooked2 = attempt2 != null
              ? attempt2.recipe.servings * attempt2.recipeMultiplier
              : 0;
          if (attempt2 == null || cooked2 > attempt2.totalServings) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour ce créneau. Slot inchangé.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            return;
          }
          newMeal = attempt2;
        }
      }

      setState(() => _isLoading = false);
      await _addMealToPlan(newMeal.recipe, date, type);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
