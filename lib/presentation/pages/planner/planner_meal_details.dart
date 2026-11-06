// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerMealDetails on _PlannerPageState {
  Widget _buildMealDetails() {
    if (_selectedMealDate == null) return const SizedBox();

    // If the selected date is in history, show historical meals
    final historyMeals = _mealHistory.entries
        .firstWhere(
          (entry) =>
              entry.key.year == _selectedMealDate!.year &&
              entry.key.month == _selectedMealDate!.month &&
              entry.key.day == _selectedMealDate!.day,
          orElse: () => MapEntry(_selectedMealDate!, <Meal>[]),
        )
        .value;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(_selectedMealDate!.year, _selectedMealDate!.month, _selectedMealDate!.day);
    final isPastDay = selectedDay.isBefore(today);
    final mealsOfDay = isPastDay && historyMeals.isNotEmpty
        ? historyMeals
        : (_generatedMealPlan?.meals.where((meal) {
                final d = meal.date;
                return d.year == _selectedMealDate!.year &&
                    d.month == _selectedMealDate!.month &&
                    d.day == _selectedMealDate!.day;
              }).toList() ??
              []);

    // Trier par nom alphabétique du premier utilisateur du repas pour un ordre stable
    String _firstUserName(Meal m) {
      if (m.userServings.isEmpty) return '';
      final names = m.userServings.keys
          .map((uid) => _userNames[uid] ?? uid)
          .toList()
        ..sort();
      return names.first;
    }

    final lunchMeals = mealsOfDay
        .where((m) => m.type == MealType.lunch)
        .toList()
      ..sort((a, b) => _firstUserName(a).compareTo(_firstUserName(b)));
    final dinnerMeals = mealsOfDay
        .where((m) => m.type == MealType.dinner)
        .toList()
      ..sort((a, b) => _firstUserName(a).compareTo(_firstUserName(b)));

    Widget buildMealCard(Meal meal) {
      final isKept = _multiShuffleKeptSlots.contains(_slotKey(meal.date, meal.type));
      final isSelectableMeal = _isMultiShuffleMode && !meal.isLeftoverMeal && !isPastDay;
      final liveRating = _currentRecipeRating(meal.recipe);
      final isSwapSource = _swapSourceMeal != null &&
          _swapSourceMeal!.date.year == meal.date.year &&
          _swapSourceMeal!.date.month == meal.date.month &&
          _swapSourceMeal!.date.day == meal.date.day &&
          _swapSourceMeal!.type == meal.type &&
          _swapSourceMeal!.recipe.id == meal.recipe.id;
      final isSwapTarget = _swapSourceMeal != null && !isSwapSource &&
          !meal.isLeftoverMeal && !isPastDay;
      final isSwapDimmed = _swapSourceMeal != null && !isSwapSource && !isSwapTarget;

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: isSelectableMeal
              ? () => setState(() {
                    final key = _slotKey(meal.date, meal.type);
                    if (_multiShuffleKeptSlots.contains(key)) {
                      _multiShuffleKeptSlots.remove(key);
                    } else {
                      _multiShuffleKeptSlots.add(key);
                    }
                  })
              : null,
          child: Stack(
            children: [
              // ── Main content + right-side buttons in a Row ──
              IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  // ── Left: tap to open recipe ──
                  Expanded(
                    child: InkWell(
                    onTap: isSelectableMeal ? null : () => _openRecipeDetail(meal),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon
                        meal.isLeftoverMeal
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restaurant, color: Colors.orange, size: 24),
                              )
                            : Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restaurant_menu, color: Colors.green, size: 24),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + multiplier badge
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      meal.recipe.title,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                  ),
                                  if (meal.recipeMultiplier > 1 && !meal.isLeftoverMeal)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green, width: 1.5),
                                      ),
                                      child: Text(
                                        'x${meal.recipeMultiplier}',
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green[800]),
                                      ),
                                    ),
                                  // ...badge "X pers" supprimé...
                                ],
                              ),
                                if (liveRating > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: Color(0xFFFFA726),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${liveRating.toStringAsFixed(liveRating % 1 == 0 ? 0 : 1)}/5',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFFFA726),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              const SizedBox(height: 4),
                              // Badges
                              if (meal.isLeftoverMeal) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                                    const SizedBox(width: 4),
                                    Text('Restes du repas précédent',
                                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.orange[700], fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ],

                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingRecipeId == meal.recipe.id)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
                  ), // InkWell (left content)
                  ), // Expanded (left)
                  // ── Right: action buttons row (hidden in multi-shuffle and swap mode) ──
                  if (!_isMultiShuffleMode && _swapSourceMeal == null)
                  Builder(builder: (context) {
                    final btnHPad = (MediaQuery.of(context).size.width * 0.014).clamp(10.0, 20.0);
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: IntrinsicWidth(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isPastDay) ...[
                            InkWell(
                              onTap: () => _autoChangeMealRecipe(meal),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: btnHPad, vertical: 12),
                                child: Icon(Icons.autorenew, color: Colors.grey.shade500, size: 20),
                              ),
                            ),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                            if (!meal.isLeftoverMeal) ...[
                              InkWell(
                                onTap: () => setState(() => _swapSourceMeal = meal),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: btnHPad, vertical: 12),
                                  child: Icon(Icons.compare_arrows_rounded, color: Colors.grey.shade500, size: 20),
                                ),
                              ),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                            ],
                          ],
                          InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final today = DateTime(now.year, now.month, now.day);
                              final mealDate = DateTime(meal.date.year, meal.date.month, meal.date.day);
                              final isHistory = mealDate.isBefore(today);
                              if (isHistory) {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                    contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                    actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                    title: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), shape: BoxShape.circle),
                                        child: const Icon(Icons.history, color: Colors.orange, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text('Repas historique', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16))),
                                    ]),
                                    content: Text("Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        style: TextButton.styleFrom(foregroundColor: Colors.black54),
                                        child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6A5AE0), foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), elevation: 0,
                                        ),
                                        child: Text('Oui, modifier', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                              } else {
                                _autoChangeBannedRecipes.clear();
                              }
                              _showRecipeSelector(mealToUpdate: meal, requireConfirmation: false);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: btnHPad, vertical: 12),
                              child: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                            ),
                          ),
                          VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                          InkWell(
                            onTap: () => _deleteMeal(meal),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: btnHPad, vertical: 12),
                              child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  }), // Builder (responsive btn padding)
                  ], // Row children (left content + right buttons)
                ), // Row
              ), // IntrinsicHeight
              // ── Swap source overlay ──
              if (isSwapSource)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF6A5AE0), width: 2),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF6A5AE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.compare_arrows_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // ── Swap target overlay (tap to confirm swap) ──
              if (isSwapTarget)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _swapMeals(_swapSourceMeal!, meal),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF6A5AE0).withOpacity(0.45),
                          width: 1.5,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A5AE0).withOpacity(0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // ── Swap dimmed overlay (past / leftover / not eligible) ──
              if (isSwapDimmed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              // ── Selection overlay (multi-shuffle mode) ──
              if (isSelectableMeal)
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isKept
                          ? Colors.green.withOpacity(0.18)
                          : Colors.orange.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isKept
                            ? Colors.green.withOpacity(0.7)
                            : Colors.orange.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: isKept
                              ? Container(
                                  key: const ValueKey('kept'),
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                                )
                              : Container(
                                  key: const ValueKey('shuffle'),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 16),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ], // Stack children
          ), // Stack
        ), // GestureDetector
      );
    }

    // ── Grouped slot card: une seule Card quand les repas diffèrent par user ──
    Widget buildSlotCard(List<Meal> meals) {
      if (meals.length == 1) return buildMealCard(meals.first);

      // Multi-recettes dans le même créneau → card unique avec une ligne par repas
      Widget rowBtn(IconData icon, Color color, VoidCallback onTap) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 22, color: color),
            ),
          ),
        );
      }

      Widget compactRow(Meal meal) {
        final isKeptCompact = _multiShuffleKeptSlots.contains(_slotKey(meal.date, meal.type));
        final isSelectableCompact = _isMultiShuffleMode && !meal.isLeftoverMeal && !isPastDay;
        final liveRating = _currentRecipeRating(meal.recipe);

        return GestureDetector(
          onTap: isSelectableCompact
              ? () => setState(() {
                    final key = _slotKey(meal.date, meal.type);
                    if (_multiShuffleKeptSlots.contains(key)) {
                      _multiShuffleKeptSlots.remove(key);
                    } else {
                      _multiShuffleKeptSlots.add(key);
                    }
                  })
              : null,
          child: Stack(
          children: [
            InkWell(
              onTap: isSelectableCompact ? null : () => _openRecipeDetail(meal),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // Icône
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: meal.isLeftoverMeal
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        meal.isLeftoverMeal ? Icons.restaurant : Icons.restaurant_menu,
                        color: meal.isLeftoverMeal ? Colors.orange : Colors.green,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Titre recette
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            meal.recipe.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (liveRating > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: Color(0xFFFFA726),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${liveRating.toStringAsFixed(liveRating % 1 == 0 ? 0 : 1)}/5',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFFFA726),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (meal.isLeftoverMeal)
                            Text(
                              'Restes du repas précédent',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange[700],
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const SizedBox(width: 4),
                    // Bouton Aléatoire (plan futur seulement)
                    if (!isPastDay && !_isMultiShuffleMode)
                      rowBtn(Icons.autorenew, Colors.grey.shade500,
                          () => _autoChangeMealRecipe(meal)),
                    // Bouton Chercher
                    if (!_isMultiShuffleMode)
                    rowBtn(Icons.search, Colors.grey.shade500, () async {
                      final now2 = DateTime.now();
                      final today2 =
                          DateTime(now2.year, now2.month, now2.day);
                      final mealDate2 = DateTime(
                          meal.date.year, meal.date.month, meal.date.day);
                      if (mealDate2.isBefore(today2)) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            titlePadding:
                                const EdgeInsets.fromLTRB(24, 24, 24, 0),
                            contentPadding:
                                const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            actionsPadding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            title: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.history,
                                    color: Colors.orange, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text('Repas historique',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16))),
                            ]),
                            content: Text(
                              "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                              style: GoogleFonts.poppins(
                                  fontSize: 14, color: Colors.black54),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.black54),
                                child: Text('Annuler',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w500)),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF6A5AE0),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  elevation: 0,
                                ),
                                child: Text('Oui, modifier',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      } else {
                        _autoChangeBannedRecipes.clear();
                      }
                      _showRecipeSelector(
                          mealToUpdate: meal, requireConfirmation: false);
                    }),
                    // Bouton Supprimer
                    if (!_isMultiShuffleMode)
                    rowBtn(Icons.delete_outline, Colors.red.shade300,
                        () => _deleteMeal(meal)),
                  ],
                ),
              ),
            ),
            if (_loadingRecipeId == meal.recipe.id)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            // Selection overlay for multi-shuffle
            if (isSelectableCompact)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isKeptCompact
                        ? Colors.green.withOpacity(0.18)
                        : Colors.orange.withOpacity(0.06),
                    border: Border.all(
                      color: isKeptCompact
                          ? Colors.green.withOpacity(0.7)
                          : Colors.orange.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isKeptCompact
                            ? Container(
                                key: const ValueKey('keptC'),
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 14),
                              )
                            : Container(
                                key: const ValueKey('shuffleC'),
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 14),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          ), // Stack
        ); // GestureDetector
      }

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int _i = 0; _i < meals.length; _i++) ...[
              if (_i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200),
              compactRow(meals[_i]),
            ],
          ],
        ),
      );
    }

    Widget buildEmptySlot(MealType mealType) {
      Future<void> onManualTap() async {
        if (_selectedMealDate == null) return;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final mealDate = DateTime(
          _selectedMealDate!.year,
          _selectedMealDate!.month,
          _selectedMealDate!.day,
        );
        final isHistory = mealDate.isBefore(today);
        if (isHistory) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Repas historique',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: Text(
                "Ce jour fait partie de l'historique. Voulez-vous vraiment ajouter un repas ?",
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                  ),
                  child: Text('Oui, ajouter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
        _showRecipeSelector(date: _selectedMealDate!, type: mealType);
      }

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            // ── Main content ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.restaurant_menu, color: Colors.grey[400], size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucun repas planifié',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Action bar ──
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    if (!isPastDay) ...[
                      Expanded(
                        child: InkWell(
                          onTap: () => _autoFillEmptySlot(_selectedMealDate!, mealType),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.autorenew, color: Colors.grey.shade500, size: 20),
                                const SizedBox(height: 3),
                                Text('Aléatoire', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: Colors.grey.shade200),
                    ],
                    Expanded(
                      child: InkWell(
                        onTap: onManualTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                              const SizedBox(height: 3),
                              Text('Chercher', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        
        // Calculate bounds (same as in calendar) to prevent out of bounds error
        DateTime planStart = _generatedMealPlan?.startDate ?? DateTime.now();
        DateTime planEnd = planStart.add(
          Duration(days: (_generatedMealPlan?.durationDays ?? 1) - 1),
        );
        final historyDates = _mealHistory.keys.toList();
        DateTime? historyMin = historyDates.isNotEmpty
            ? historyDates.reduce((a, b) => a.isBefore(b) ? a : b)
            : null;
        DateTime? historyMax = historyDates.isNotEmpty
            ? historyDates.reduce((a, b) => a.isAfter(b) ? a : b)
            : null;
        final firstDay = historyMin != null && historyMin.isBefore(planStart)
            ? historyMin
            : planStart;
        final lastDay = historyMax != null && historyMax.isAfter(planEnd)
            ? historyMax
            : planEnd;

        DateTime? newDate;
        if (details.primaryVelocity! < 0) {
          // Swipe Left -> Next Day
          newDate = _selectedMealDate!.add(const Duration(days: 1));
        } else if (details.primaryVelocity! > 0) {
          // Swipe Right -> Previous Day
          newDate = _selectedMealDate!.subtract(const Duration(days: 1));
        }

        if (newDate != null) {
          // Verify bounds (start of day comparison)
          final newDateDay = DateTime(newDate.year, newDate.month, newDate.day);
          final firstDayStart = DateTime(firstDay.year, firstDay.month, firstDay.day);
          final lastDayStart = DateTime(lastDay.year, lastDay.month, lastDay.day);

          if (!newDateDay.isBefore(firstDayStart) && !newDateDay.isAfter(lastDayStart)) {
             setState(() {
               _selectedMealDate = newDate;
               _focusedDay = newDate!;
             });
          }
        }
      },
      child: Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LUNCH Section
          Text(
            'MIDI',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
          const SizedBox(height: 8),
          if (lunchMeals.isNotEmpty)
            buildSlotCard(lunchMeals)
          else
            buildEmptySlot(MealType.lunch),

          const SizedBox(height: 16),

          // DINNER Section
          Text(
            'SOIR',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
          const SizedBox(height: 8),
          if (dinnerMeals.isNotEmpty)
            buildSlotCard(dinnerMeals)
          else
            buildEmptySlot(MealType.dinner),
        ],
      ),
    ), // Close Padding
    ); // Close GestureDetector
  }
}
