// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerPickers on _PlannerPageState {
  Future<void> _pickDateRange({VoidCallback? onUpdated}) async {
    DateTime tempStartDate = _selectedStartDate ?? DateTime.now();
    int tempDuration = _selectedStartDate == null ? 0 : (_selectedDuration ?? 7).clamp(1, 31);
    DateTime tempEndDate = tempStartDate.add(Duration(days: tempDuration - 1));
    DateTime focusedDay = tempStartDate;
    bool awaitingEnd = false;
    bool startSelected = true; // false = start date cleared by user
    const int maxDays = 31;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Période du plan',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Start / End date chips
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A5AE0).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF6A5AE0).withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Début', style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFF6A5AE0))),
                                Text(
                                  startSelected
                                      ? '${tempStartDate.day}/${tempStartDate.month}/${tempStartDate.year}'
                                      : '—',
                                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF6A5AE0)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.grey[400], size: 16),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A5AE0).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF6A5AE0).withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fin', style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFF6A5AE0))),
                                Text(
                                  (startSelected && !awaitingEnd)
                                      ? '${tempEndDate.day}/${tempEndDate.month}/${tempEndDate.year}'
                                      : '—',
                                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF6A5AE0)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hint when awaiting end date pick
                  if (awaitingEnd && startSelected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.touch_app_rounded, size: 15, color: Color(0xFF6A5AE0)),
                            const SizedBox(width: 6),
                            Text(
                              'Sélectionnez maintenant la date de fin',
                              style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF6A5AE0)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Calendar — takes all remaining space
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TableCalendar(
                        shouldFillViewport: true,
                        locale: 'fr_FR',
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        firstDay: DateTime.now(),
                        lastDay: DateTime.now().add(const Duration(days: 365)),
                        focusedDay: focusedDay,
                        rangeStartDay: startSelected ? tempStartDate : null,
                        rangeEndDay: (startSelected && !awaitingEnd) ? tempEndDate : null,
                        rangeSelectionMode: RangeSelectionMode.disabled,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          leftChevronIcon: const Icon(Icons.chevron_left, color: Color(0xFF6A5AE0)),
                          rightChevronIcon: const Icon(Icons.chevron_right, color: Color(0xFF6A5AE0)),
                        ),
                        enabledDayPredicate: (day) {
                          if (!startSelected || !awaitingEnd) return true;
                          final startNorm = DateTime(tempStartDate.year, tempStartDate.month, tempStartDate.day);
                          final dayNorm = DateTime(day.year, day.month, day.day);
                          // Activer dans les ±(maxDays-1) jours autour du début :
                          // - après : fin normale
                          // - avant : swap intelligent (l'antérieure devient début)
                          final diff = dayNorm.difference(startNorm).inDays.abs();
                          return diff < maxDays;
                        },
                        calendarStyle: CalendarStyle(
                          disabledDecoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          disabledTextStyle: TextStyle(color: Colors.grey[300]),
                          rangeStartDecoration: const BoxDecoration(
                            color: Color(0xFF6A5AE0),
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: const BoxDecoration(
                            color: Color(0xFF6A5AE0),
                            shape: BoxShape.circle,
                          ),
                          rangeStartTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          rangeEndTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          withinRangeDecoration: const BoxDecoration(
                            color: Colors.transparent,
                          ),
                          withinRangeTextStyle: const TextStyle(
                            color: Color(0xFF1A1A1A),
                          ),
                          rangeHighlightColor: Color(0xFF6A5AE0).withOpacity(0.15),
                          todayDecoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: const TextStyle(
                            color: Color(0xFF6A5AE0),
                            fontWeight: FontWeight.w600,
                          ),
                          outsideDaysVisible: false,
                        ),
                        onDaySelected: (selected, focused) {
                          setStateSheet(() {
                            focusedDay = focused;
                            if (!startSelected) {
                              // Aucune sélection : choisir la date de début
                              tempStartDate = selected;
                              startSelected = true;
                              awaitingEnd = true;
                            } else if (awaitingEnd) {
                              if (isSameDay(selected, tempStartDate)) {
                                // Re-tap date début → tout désélectionner
                                startSelected = false;
                                awaitingEnd = false;
                              } else if (!selected.isBefore(tempStartDate)) {
                                // Choisir date de fin (limité à maxDays)
                                final raw = selected.difference(tempStartDate).inDays + 1;
                                if (raw > maxDays) return; // jour désactivé, ignorer
                                tempEndDate = selected;
                                final days = raw;
                                tempDuration = days.clamp(1, maxDays);
                                awaitingEnd = false;
                              } else {
                                // Date antérieure → swap : antérieure = début, ancienne = fin
                                final oldStart = tempStartDate;
                                tempStartDate = selected;
                                tempEndDate = oldStart;
                                final days = oldStart.difference(selected).inDays + 1;
                                tempDuration = days.clamp(1, maxDays);
                                awaitingEnd = false;
                              }
                            } else {
                              // Plage complète
                              if (isSameDay(selected, tempStartDate)) {
                                // Re-tap début → garder la fin comme nouveau début, attendre nouvelle fin
                                tempStartDate = tempEndDate;
                                startSelected = true;
                                awaitingEnd = true;
                              } else if (isSameDay(selected, tempEndDate)) {
                                // Re-tap fin → garder début, attendre nouvelle fin
                                awaitingEnd = true;
                              } else {
                                // Autre jour → nouvelle date de début
                                tempStartDate = selected;
                                startSelected = true;
                                awaitingEnd = true;
                              }
                            }
                          });
                        },
                        onPageChanged: (focused) {
                          setStateSheet(() => focusedDay = focused);
                        },
                      ),
                    ),
                  ),
                  // Info max jours
                  if (awaitingEnd && startSelected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            'Maximum $maxDays jours',
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                  // Slider + presets + button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Duration display
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              startSelected ? '$tempDuration' : '0',
                              style: GoogleFonts.poppins(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF6A5AE0),
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tempDuration > 1 ? 'jours' : 'jour',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF6A5AE0),
                            inactiveTrackColor: Colors.grey[200],
                            thumbColor: const Color(0xFF6A5AE0),
                            overlayColor: const Color(0xFF6A5AE0).withOpacity(0.2),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: (startSelected ? tempDuration.clamp(1, maxDays) : 0).toDouble(),
                            min: 0,
                            max: maxDays.toDouble(),
                            divisions: maxDays,
                            onChanged: startSelected ? (val) {
                              setStateSheet(() {
                                tempDuration = val.round().clamp(1, maxDays);
                                tempEndDate = tempStartDate.add(Duration(days: tempDuration - 1));
                                awaitingEnd = false;
                              });
                            } : null,
                          ),
                        ),
                        // Quick presets
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [3, 5, 7, 10, 14].map((days) {
                            final isSelected = tempDuration == days;
                            return InkWell(
                              onTap: () => setStateSheet(() {
                                tempDuration = days;
                                tempEndDate = tempStartDate.add(Duration(days: days - 1));
                                awaitingEnd = false;
                              }),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF6A5AE0) : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$days j',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isSelected ? Colors.white : Colors.grey[700],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (startSelected && !awaitingEnd) ? () {
                              setState(() {
                                _selectedStartDate = tempStartDate;
                                _selectedDuration = tempDuration;
                              });
                              _saveDuration(tempDuration);
                              if (onUpdated != null) onUpdated();
                              Navigator.pop(context);
                            } : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Valider',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickCategories({VoidCallback? onUpdated}) async {
    // Réutilise le cache _categoryDataById si disponible — sinon lit Firestore.
    if (_categoryDataById.isEmpty) {
      await _loadAllCategories();
    }
    if (!mounted) return;

    final allCategories = _categoryDataById.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    // dataById est _categoryDataById lui-même (déjà à jour)
    final dataById = _categoryDataById;

    final validCategoryIds = allCategories.map((e) => e['id'] as String).toSet();
    // Si aucune catégorie n'est sélectionnée (= "Toutes"), ouvrir avec tout coché.
    final tempSelected = _selectedCategories.isEmpty
        ? Set<String>.from(validCategoryIds)
        : Set<String>.from(_selectedCategories.where((id) => validCategoryIds.contains(id)));

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isAllSelected = tempSelected.length == validCategoryIds.length;
          final isNoneSelected = tempSelected.isEmpty;

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // --- Header ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Filtrer par catégorie',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // --- Quick Actions ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isNoneSelected ? null : () => setStateDialog(() => tempSelected.clear()),
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: const Text('Tout décocher'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[700],
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isAllSelected ? null : () => setStateDialog(() => tempSelected.addAll(validCategoryIds)),
                          icon: const Icon(Icons.select_all_rounded, size: 18),
                          label: const Text('Tout cocher'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6A5AE0),
                            side: const BorderSide(color: Color(0xFF6A5AE0)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // --- Scrollable Content ---
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: allCategories.map((entry) {
                        final id = entry['id'] as String;
                        final name = entry['name'] as String;
                        final colorVal = entry['color'] as int;
                        final baseColor = Color(colorVal);

                        final isSelected = tempSelected.contains(id);

                        // Improve contrast for text
                        final hsl = HSLColor.fromColor(baseColor);
                        final startLightness = hsl.lightness;
                        final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                        final textColor = hsl.withLightness(textLightness).toColor();

                        return InkWell(
                          onTap: () {
                            setStateDialog(() {
                              if (isSelected) {
                                tempSelected.remove(id);
                              } else {
                                tempSelected.add(id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? baseColor.withOpacity(0.35)
                                  : baseColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? baseColor.withOpacity(0.5)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // --- Bottom Validation Bar ---
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A5AE0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        tempSelected.isEmpty
                            ? 'Aucun filtre (Tout voir)'
                            : isAllSelected
                                ? 'Toutes'
                                : 'Valider (${tempSelected.length})',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        setState(() {
          _selectedCategories = tempSelected;
          _categoryDataById.addAll(dataById);
        });
      }
      await _saveCategories(tempSelected);
      if (onUpdated != null) onUpdated();
    }
  }

  Future<void> _pickPantryItems({VoidCallback? onUpdated}) async {
    final result = await showDialog<List<RecipeIngredient>>(
      context: context,
      builder: (context) => PantryInputDialog(initialItems: _pantryIngredients),
    );

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _pantryIngredients = result;
      });
      // Sync changes back to the pantry repository.
      _syncPantryToRepository(result).ignore();
      if (onUpdated != null) {
        onUpdated();
      }
    }
  }

  /// Replaces all pantry items in the repository with the provided list.
  Future<void> _syncPantryToRepository(List<RecipeIngredient> items) async {
    try {
      final repo = FirebasePantryRepository.instance;
      await repo.deleteAll();
      for (final ri in items) {
        await repo.save(PantryItem(
          id: '',
          name: ri.ingredient.name,
          ingredientId: ri.ingredient.id,
          quantity: ri.quantity,
          unit: ri.unit,
          isUrgent: false,
          updatedAt: DateTime.now(),
        ));
      }
    } catch (_) {
      // Sync is best-effort; do not disrupt the planning flow.
    }
  }

  void _pickDuration({VoidCallback? onUpdated}) {
    _pickDateRange(onUpdated: onUpdated);
  }
}
