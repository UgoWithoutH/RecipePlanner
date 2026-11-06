import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/repositories/firebase_pantry_snapshot_repository.dart';
import 'planner_modern_widgets.dart';

class ModernPlannerHeader extends StatelessWidget {
  final DateTime? selectedStartDate;
  final int? selectedDuration;
  final Set<String> selectedCategories;
  final double selectedMinRating;
  
  // ID -> {id, name, color}
  final Map<String, Map<String, dynamic>> categoryDataById;
  
  final int pantryCount;
  final int urgentCount;
  final List<PantrySnapshotItem> pantrySnapshot;
  final VoidCallback? onViewPantrySnapshot;

  final VoidCallback onPickDateRange;
  final VoidCallback onPickCategories;
  final ValueChanged<double> onMinRatingChanged;
  final VoidCallback onLaunchPlanning;
  final bool isLoading;

  const ModernPlannerHeader({
    super.key,
    required this.selectedStartDate,
    required this.selectedDuration,
    required this.selectedCategories,
    required this.selectedMinRating,
    required this.categoryDataById,
    required this.pantryCount,
    required this.urgentCount,
    required this.pantrySnapshot,
    this.onViewPantrySnapshot,
    required this.onPickDateRange,
    required this.onPickCategories,
    required this.onMinRatingChanged,
    required this.onLaunchPlanning,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Créer un plan de repas',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: onPickDateRange,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (selectedStartDate != null && selectedDuration != null)
                      ? const Color(0xFF6A5AE0).withOpacity(0.5)
                      : Colors.grey.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.date_range_rounded, color: Color(0xFF6A5AE0), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Période',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (ctx) {
                            if (selectedStartDate == null || selectedDuration == null) {
                              return Text(
                                'Choisir une période',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2D2D2D),
                                ),
                              );
                            }
                            final endDate = selectedStartDate!.add(Duration(days: selectedDuration! - 1));
                            return Text(
                              'Du ${selectedStartDate!.day}/${selectedStartDate!.month} au ${endDate.day}/${endDate.month}\u00a0· $selectedDuration ${selectedDuration! > 1 ? 'jours' : 'jour'}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2D2D2D),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onPickCategories,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selectedCategories.isNotEmpty
                      ? const Color(0xFF6A5AE0).withOpacity(0.5)
                      : Colors.grey.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_offer_rounded, color: Color(0xFF6A5AE0), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Catégories',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final validCategories = selectedCategories.where((id) {
                                final cat = categoryDataById[id];
                                return cat != null;
                            }).toList();

                            // If empty (no filter) or equal to total known categories (all selected)
                            if (validCategories.isEmpty || (categoryDataById.isNotEmpty && validCategories.length == categoryDataById.length)) {
                              return Text(
                                'Toutes',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2D2D2D),
                                ),
                              );
                            }

                            return Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: validCategories.map((id) {
                                final cat = categoryDataById[id];
                                final name = cat?['name'] as String? ?? 'Unknown';
                                final colorVal = cat?['color'] as int? ?? 0xFF6A5AE0;
                                final color = Color(colorVal);

                                // Contrast logic
                                final hsl = HSLColor.fromColor(color);
                                final textLightness =
                                    hsl.lightness > 0.4 ? 0.4 : hsl.lightness;
                                final textColor =
                                    hsl.withLightness(textLightness).toColor();

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    name,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selectedMinRating > 0
                    ? const Color(0xFFFFA726).withOpacity(0.5)
                    : Colors.grey.withOpacity(0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, color: Color(0xFFFFA726), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Note minimale',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2D2D2D),
                          ),
                        ),
                        Text(
                          'non notées toujours incluses',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in [0, 1, 2, 3, 4, 5])
                      GestureDetector(
                        onTap: () => onMinRatingChanged(v.toDouble()),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: selectedMinRating == v.toDouble()
                                ? const Color(0xFFFFA726)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedMinRating == v.toDouble()
                                  ? const Color(0xFFFFA726)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: v == 0
                              ? Text(
                                  'Toutes',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selectedMinRating == 0
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: selectedMinRating == v.toDouble()
                                          ? Colors.white
                                          : const Color(0xFFFFA726),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '≥$v',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: selectedMinRating == v.toDouble()
                                            ? Colors.white
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: (pantrySnapshot.isNotEmpty || pantryCount > 0) ? onViewPantrySnapshot : null,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: urgentCount > 0
                    ? Colors.orange.withOpacity(0.5)
                    : pantryCount > 0
                        ? const Color(0xFF6A5AE0).withOpacity(0.3)
                        : Colors.grey.withOpacity(0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.kitchen_rounded,
                    color: urgentCount > 0 ? Colors.orange[700] : const Color(0xFF6A5AE0),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Frigo / Placard',
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pantryCount == 0
                            ? 'Aucun article renseigné'
                            : urgentCount > 0
                                ? '$pantryCount article${pantryCount > 1 ? 's' : ''} · $urgentCount urgent${urgentCount > 1 ? 's' : ''} 🔥'
                                : '$pantryCount article${pantryCount > 1 ? 's' : ''} disponible${pantryCount > 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: urgentCount > 0
                              ? Colors.orange[800]
                              : const Color(0xFF2D2D2D),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pantrySnapshot.isNotEmpty
                            ? 'Appuyez pour voir le frigo de ce plan'
                            : 'Gérez votre stock dans l\'onglet Frigo / Placard',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                if (pantrySnapshot.isNotEmpty)
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 18)
                else
                  const Icon(Icons.lock_outline_rounded, color: Colors.black12, size: 16),
              ],
            ),
          ),
          ),
          const SizedBox(height: 24),
          ModernGradientButton(
            label: 'Générer le plan',
            icon: Icons.auto_awesome,
            onTap: isLoading ? null : onLaunchPlanning,
          ),
        ],
      ),
    );
  }
}
