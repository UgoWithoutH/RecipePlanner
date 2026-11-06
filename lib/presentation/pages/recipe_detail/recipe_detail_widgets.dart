// ignore_for_file: invalid_use_of_protected_member
part of 'recipe_detail_page.dart';

extension _RecipeDetailWidgets on _RecipeDetailPageState {
  void _showTransientRatingLabel(double rating) {
    final label = _ratingLabel(rating);
    if (label.isEmpty) return;
    _ratingFeedbackTimer?.cancel();
    if (mounted) {
      setState(() {
        _ratingFeedbackText = label;
        _showRatingFeedback = true;
      });
    }
    _ratingFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showRatingFeedback = false);
    });
  }

  Widget _buildStarRating() {
    final rating = _recipe?.rating ?? 0.0;
    const starCount = 5;
    const starColor = Color(0xFFFFA726);
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(starCount, (i) {
                final filled = i < rating;
                return GestureDetector(
                  onTap: () {
                    final tapped = i + 1.0;
                    _saveRating(rating == tapped ? 0.0 : tapped);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        key: ValueKey('$i-$filled'),
                        size: 28,
                        color: filled ? starColor : Colors.grey[300],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showRatingFeedback ? 1 : 0,
                child: Text(
                  _ratingFeedbackText,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: starColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _ratingLabel(double r) {
    switch (r.toInt()) {
      case 1: return 'Décevant';
      case 2: return 'Passable';
      case 3: return 'Bien';
      case 4: return 'Très bien';
      case 5: return 'Excellent !';
      default: return '';
    }
  }

  Widget _headerCircleButton(IconData icon, VoidCallback? onTap, {Color color = Colors.black87}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Widget _buildModernStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildImportFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 16),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final recipe = _recipe;
          if (recipe == null) return;
          final presetData = <String, dynamic>{
            'title': recipe.title,
            'description': recipe.description,
            'preparationTime': recipe.preparationTime,
            'cookingTime': recipe.cookingTime,
            'servings': recipe.servings,
            'instructions': recipe.instructions,
            'categories': <String>[],
            'ingredients': recipe.ingredients.map((ri) => {
              'name': ri.ingredient.name,
              'quantity': ri.quantity,
              'unit': ri.unit.label,
              'type': ri.ingredient.typeId ?? '',
            }).toList(),
          };
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateRecipePage(presetData: presetData),
            ),
          );
          if (result != null && mounted) {
            setState(() => _isAlreadyImported = true);
          }
        },
        backgroundColor: const Color(0xFF6A5AE0),
        icon: const Icon(Icons.file_download_outlined, color: Colors.white),
        label: Text(
          'Importer',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF6A5AE0),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: const Color(0xFF2D2D2D), // Dark grey
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserServingsList() {
    return Column(
      children: _userServings.map((s) {
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
                  s.userName.isNotEmpty ? s.userName.substring(0, 1).toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6A5AE0),
                    fontSize: 16
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  s.userName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, 
                    fontSize: 15,
                    color: const Color(0xFF2D2D2D)
                  ),
                ),
              ),
              Opacity(
                opacity: _recipe?.mealTime == MealTime.dinnerOnly ? 0.3 : 1.0,
                child: _buildServingBadge(Icons.wb_sunny_rounded, '${s.lunchServings}', Colors.orange),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _recipe?.mealTime == MealTime.lunchOnly ? 0.3 : 1.0,
                child: _buildServingBadge(Icons.nights_stay_rounded, '${s.dinnerServings}', const Color(0xFF5C6BC0)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildServingBadge(IconData icon, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            count,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
