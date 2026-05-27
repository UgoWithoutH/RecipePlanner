enum MealTime {
  both,
  lunchOnly,
  dinnerOnly;

  String get label {
    switch (this) {
      case MealTime.both:
        return 'Midi & Soir';
      case MealTime.lunchOnly:
        return 'Midi uniquement';
      case MealTime.dinnerOnly:
        return 'Soir uniquement';
    }
  }

  String get shortLabel {
    switch (this) {
      case MealTime.both:
        return 'Midi & Soir';
      case MealTime.lunchOnly:
        return 'Midi';
      case MealTime.dinnerOnly:
        return 'Soir';
    }
  }

  static MealTime fromString(String? value) {
    return MealTime.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MealTime.both,
    );
  }
}
