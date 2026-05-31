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

  /// Returns true if this unit and [other] are in the same dimension (mass or volume).
  bool isSameDimension(Unit other) {
    const mass = {Unit.g, Unit.kg};
    const volume = {Unit.ml, Unit.l};
    if (mass.contains(this) && mass.contains(other)) return true;
    if (volume.contains(this) && volume.contains(other)) return true;
    return false;
  }

  /// Converts [qty] from this unit to [target] unit.
  /// Returns null if conversion is not possible.
  double? convertTo(double qty, Unit target) {
    if (this == target) return qty;
    // Mass
    if (this == Unit.g && target == Unit.kg) return qty / 1000.0;
    if (this == Unit.kg && target == Unit.g) return qty * 1000.0;
    // Volume
    if (this == Unit.ml && target == Unit.l) return qty / 1000.0;
    if (this == Unit.l && target == Unit.ml) return qty * 1000.0;
    return null;
  }

  /// Returns a normalized (quantity, unit) pair:
  /// - g → kg if qty ≥ 1000
  /// - ml → L if qty ≥ 1000
  /// Otherwise returns unchanged.
  (double, Unit) normalize(double qty) {
    if (this == Unit.g && qty >= 1000) return (qty / 1000.0, Unit.kg);
    if (this == Unit.ml && qty >= 1000) return (qty / 1000.0, Unit.l);
    return (qty, this);
  }
}