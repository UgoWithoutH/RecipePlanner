// ignore_for_file: invalid_use_of_protected_member
part of 'create_recipe_page.dart';

extension _CreateRecipeInputs on _CreateRecipePageState {
  Widget _buildNumberStepper({
    required TextEditingController controller,
    required String label,
    int min = 0,
    int max = 999,
    int step = 1,
    FocusNode? focusNode,
  }) {
    void increment() {
      final current = int.tryParse(controller.text) ?? min;
      final next = (current + step).clamp(min, max);
      controller.text = next.toString();
      if (focusNode != null) {
        _servingsDebounceTimer?.cancel();
        _servingsDebounceTimer = Timer(const Duration(seconds: 2), _onServingsEditingDone);
      }
    }
    void decrement() {
      final current = int.tryParse(controller.text) ?? min;
      final next = (current - step).clamp(min, max);
      controller.text = next.toString();
      if (focusNode != null) {
        _servingsDebounceTimer?.cancel();
        _servingsDebounceTimer = Timer(const Duration(seconds: 2), _onServingsEditingDone);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _stepperButton(icon: Icons.remove_rounded, onAction: decrement),
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                      isDense: true,
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                    onFieldSubmitted: (_) {
                      if (focusNode != null) _onServingsEditingDone();
                    },
                  ),
                ),
                _stepperButton(icon: Icons.add_rounded, onAction: increment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, required VoidCallback onAction}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAction,
        onLongPress: () {
          _stepperRepeatTimer?.cancel();
          _stepperRepeatTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
            onAction();
          });
        },
        onLongPressUp: () {
          _stepperRepeatTimer?.cancel();
          _stepperRepeatTimer = null;
        },
        onTapCancel: () {
          _stepperRepeatTimer?.cancel();
          _stepperRepeatTimer = null;
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Icon(icon, size: 20, color: const Color(0xFF6A5AE0)),
        ),
      ),
    );
  }

  // ------------------------
  // UI Builders
  // ------------------------

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool isRequired = true,
    FocusNode? focusNode,
  }) {
    // Defines input formatters if keyboardType is number
    List<TextInputFormatter>? inputFormatters;
    if (keyboardType == TextInputType.number) {
      inputFormatters = [FilteringTextInputFormatter.digitsOnly];
    }

    // Nettoyer le label pour le placeholder (enlever le *)
    final String cleanLabel = label.contains('*')
        ? label.replaceAll('*', '').trim()
        : label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              maxLines: maxLines,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: GoogleFonts.poppins(fontSize: 15),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: InputBorder.none,
                hintText: 'Entrez $cleanLabel...',
                hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
              ),
              validator: (v) {
                if (!isRequired) return null;
                return v == null || v.isEmpty ? 'Requis' : null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catégorie',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingCategories)
            const Center(child: CircularProgressIndicator())
          else if (_categories.isEmpty)
            const SizedBox.shrink()
          else
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedCategoryIds.contains(category.id);
                  final categoryColor = Color(category.color);

                  final hsl = HSLColor.fromColor(categoryColor);
                  final startLightness = hsl.lightness;
                  final textLightness = startLightness > 0.4
                      ? 0.4
                      : startLightness;
                  final textColor = hsl.withLightness(textLightness).toColor();

                  return FilterChip(
                    label: Text(
                      category.name,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategoryIds.add(category.id);
                        } else {
                          _selectedCategoryIds.remove(category.id);
                        }
                      });
                    },
                    backgroundColor: categoryColor.withOpacity(0.15),
                    selectedColor: categoryColor.withOpacity(0.35),
                    checkmarkColor: textColor,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernInput(
    TextEditingController controller,
    String hint, {
    TextInputType? inputType,
    FocusNode? focusNode,
  }) {
    List<TextInputFormatter>? inputFormatters;
    if (inputType == TextInputType.number) {
      // Allow decimals with comma or dot for ingredient quantity
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ];
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: inputType == TextInputType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : inputType,
        inputFormatters: inputFormatters,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildMealTimeSelectorSection() {
    const purple = Color(0xFF6A5AE0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Moment du repas',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Définit quand cette recette peut être planifiée',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 12),
        Row(
          children: MealTime.values.map((mt) {
            final selected = _selectedMealTime == mt;
            final icon = mt == MealTime.lunchOnly
                ? Icons.wb_sunny_rounded
                : mt == MealTime.dinnerOnly
                    ? Icons.nights_stay_rounded
                    : Icons.today_rounded;
            final color = mt == MealTime.lunchOnly
                ? Colors.orange.shade700
                : mt == MealTime.dinnerOnly
                    ? const Color(0xFF5C6BC0)
                    : purple;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedMealTime = mt;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: selected ? color.withOpacity(0.12) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? color : Colors.grey.shade200,
                        width: selected ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 20, color: selected ? color : Colors.grey[400]),
                        const SizedBox(height: 4),
                        Text(
                          mt.shortLabel,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? color : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUserServingsSection() {
    if (_users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Portions par utilisateur',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Column(
          children: _users.map((user) {
            // Si la recette est en création (pas d'id), on met 1 par défaut
            final isNewRecipe = widget.recipe == null;
            final lunchDefault = _selectedMealTime == MealTime.dinnerOnly
                ? 0
                : isNewRecipe ? 1 : (_userServings[user.id]?.lunchServings ?? 0);
            final dinnerDefault = _selectedMealTime == MealTime.lunchOnly
                ? 0
                : isNewRecipe ? 1 : (_userServings[user.id]?.dinnerServings ?? 0);
            final lunchController = TextEditingController(
              text: lunchDefault.toString(),
            );
            final dinnerController = TextEditingController(
              text: dinnerDefault.toString(),
            );

            // Important: update logic needs to be preserved or handled carefully
            // The previous logic created new UserRecipeServing objects on change.
            // I will keep that logic but inside a nicer UI.

            // Si la recette est en création, initialiser la map _userServings pour chaque user
            if (isNewRecipe && _userServings[user.id] == null) {
              _userServings[user.id] = UserRecipeServing(
                userId: user.id,
                recipeId: '',
                lunchServings: _selectedMealTime == MealTime.dinnerOnly ? 0 : 1,
                dinnerServings: _selectedMealTime == MealTime.lunchOnly ? 0 : 1,
                userName: user.name,
                recipeTitle: _titleController.text.trim(),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.1),
                    radius: 20,
                    child: Text(
                      user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : '?',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6A5AE0),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  // Lunch Input
                  Opacity(
                    opacity: _selectedMealTime == MealTime.dinnerOnly ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _selectedMealTime == MealTime.dinnerOnly,
                      child: _buildServingInput(
                        lunchController,
                        Icons.wb_sunny_rounded,
                        Colors.orange,
                        (v) {
                          final existing = _userServings[user.id];
                          _userServings[user.id] = UserRecipeServing(
                            userId: user.id,
                            recipeId: widget.recipe?.id ?? '',
                            lunchServings:
                                int.tryParse(v) ?? existing?.lunchServings ?? 1,
                            dinnerServings: existing?.dinnerServings ?? 1,
                            userName: user.name,
                            recipeTitle: _titleController.text.trim(),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dinner Input
                  Opacity(
                    opacity: _selectedMealTime == MealTime.lunchOnly ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _selectedMealTime == MealTime.lunchOnly,
                      child: _buildServingInput(
                        dinnerController,
                        Icons.nights_stay_rounded,
                        const Color(0xFF5C6BC0),
                        (v) {
                          final existing = _userServings[user.id];
                          _userServings[user.id] = UserRecipeServing(
                            userId: user.id,
                            recipeId: widget.recipe?.id ?? '',
                            lunchServings: existing?.lunchServings ?? 1,
                            dinnerServings:
                                int.tryParse(v) ?? existing?.dinnerServings ?? 1,
                            userName: user.name,
                            recipeTitle: _titleController.text.trim(),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildServingInput(
    TextEditingController controller,
    IconData icon,
    Color color,
    Function(String) onChanged,
  ) {
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------
  // BUILD PAGE
  // ------------------------

  Widget _headerCircleButton(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}
