enum Unit {
  g('g'),
  kg('kg'),
  ml('ml'),
  l('l'),
  teaspoon('cuillère à café'),
  tablespoon('cuillère à soupe'),
  cup('tasse'),
  piece('pièce'),
  pinch('pincée');

  final String label;
  const Unit(this.label);

  /// Returns the display label for a unit stored as enum name (e.g. "teaspoon" → "c.à.t.").
  static String labelOf(String name) {
    return Unit.values
        .firstWhere((u) => u.name == name, orElse: () => Unit.piece)
        .label;
  }
}