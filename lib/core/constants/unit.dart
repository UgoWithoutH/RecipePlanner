/// Unité de mesure. Les unités et leurs correspondances sont stockées en base
/// (par groupe) et chargées dans [UnitRegistry] au démarrage de l'application.
/// [name] est le code stable utilisé dans les recettes / frigo / courses.
class Unit {
  final String name;
  final String label;
  const Unit(this.name, this.label);

  static const g = Unit('g', 'g');
  static const kg = Unit('kg', 'kg');
  static const ml = Unit('ml', 'ml');
  static const l = Unit('l', 'l');
  static const teaspoon = Unit('teaspoon', 'cuillère à café');
  static const tablespoon = Unit('tablespoon', 'cuillère à soupe');
  static const cup = Unit('cup', 'tasse');
  static const piece = Unit('piece', 'pièce');
  static const pinch = Unit('pinch', 'pincée');

  /// Unités communes créées par défaut pour un groupe.
  static const defaults = <Unit>[g, kg, ml, l, teaspoon, tablespoon, cup, piece, pinch];

  /// Unités du groupe courant (ou unités par défaut tant que rien n'est chargé).
  static List<Unit> get values => UnitRegistry.units;

  /// Retourne l'unité correspondant au code [name], ou null si inconnue.
  static Unit? byName(String name) => UnitRegistry.find(name);

  /// Returns the display label for a unit stored by code (e.g. "teaspoon" → "cuillère à café").
  static String labelOf(String name) => (byName(name) ?? Unit.piece).label;

  @override
  bool operator ==(Object other) => other is Unit && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Unit($name)';

  /// Plus petite unité de la famille de conversion de cette unité.
  Unit get baseUnit => UnitRegistry.baseOf(this);

  /// Convertit [qty] exprimée dans cette unité vers l'unité de base de sa famille.
  double toBase(double qty) => qty * UnitRegistry.sizeOf(this);

  /// Convertit [baseQty] (unité de base de la famille) vers cette unité.
  double fromBase(double baseQty) => baseQty / UnitRegistry.sizeOf(this);

  /// Returns true if this unit and [other] are in the same family (convertible).
  bool isSameDimension(Unit other) =>
      this == other || baseUnit == other.baseUnit;

  /// Converts [qty] from this unit to [target] unit.
  /// Returns null if conversion is not possible.
  double? convertTo(double qty, Unit target) {
    if (this == target) return qty;
    if (!isSameDimension(target)) return null;
    return toBase(qty) / UnitRegistry.sizeOf(target);
  }

  /// Returns a normalized (quantity, unit) pair: remonte vers une unité plus
  /// grande lorsqu'une correspondance « conversion automatique » est configurée
  /// (ex : g → kg si qty ≥ 1000). Sinon retourne la valeur inchangée.
  (double, Unit) normalize(double qty) {
    UnitConversion? best;
    for (final c in UnitRegistry.conversions) {
      if (!c.autoConvert || c.toCode != name || qty < c.factor) continue;
      if (best == null || c.factor > best.factor) best = c;
    }
    if (best == null) return (qty, this);
    return (qty / best.factor, UnitRegistry.find(best.fromCode)!);
  }

  /// Exprime [baseQty] (en unité de base de la famille) de façon lisible :
  /// utilise la conversion automatique si la famille en possède une,
  /// sinon l'unité courante.
  (double, Unit) displayFromBase(double baseQty) {
    final base = baseUnit;
    final (q, u) = base.normalize(baseQty);
    if (u != base || UnitRegistry.hasAutoConversion(base)) return (q, u);
    return (fromBase(baseQty), this);
  }
}

/// Correspondance : 1 [fromCode] = [factor] [toCode] (factor ≥ 1, donc
/// [toCode] est l'unité la plus petite).
class UnitConversion {
  final String id;
  final String fromCode;
  final String toCode;
  final double factor;

  /// Si vrai, une quantité exprimée en [toCode] est automatiquement
  /// convertie en [fromCode] dès qu'elle atteint [factor].
  final bool autoConvert;

  const UnitConversion({
    this.id = '',
    required this.fromCode,
    required this.toCode,
    required this.factor,
    this.autoConvert = false,
  });

  /// Correspondances communes créées par défaut pour un groupe.
  static const defaults = <UnitConversion>[
    UnitConversion(fromCode: 'kg', toCode: 'g', factor: 1000, autoConvert: true),
    UnitConversion(fromCode: 'l', toCode: 'ml', factor: 1000, autoConvert: true),
    UnitConversion(fromCode: 'tablespoon', toCode: 'teaspoon', factor: 3),
    UnitConversion(fromCode: 'cup', toCode: 'tablespoon', factor: 16),
  ];
}

/// Registre en mémoire des unités et correspondances du groupe courant.
class UnitRegistry {
  static List<Unit> _units = Unit.defaults;
  static List<UnitConversion> _conversions = UnitConversion.defaults;
  static Map<String, Unit> _byCode = {for (final u in Unit.defaults) u.name: u};
  static Map<String, double> _sizes = {};
  static Map<String, Unit> _bases = {};
  static bool _built = false;

  static List<Unit> get units => _units;
  static List<UnitConversion> get conversions => _conversions;

  static Unit? find(String code) => _byCode[code];

  static void configure({
    required List<Unit> units,
    required List<UnitConversion> conversions,
  }) {
    _units = List.unmodifiable(units.isEmpty ? Unit.defaults : units);
    _byCode = {for (final u in _units) u.name: u};
    _conversions = List.unmodifiable(conversions.where(
        (c) => _byCode.containsKey(c.fromCode) && _byCode.containsKey(c.toCode)));
    _rebuild();
  }

  static bool hasAutoConversion(Unit unit) =>
      _conversions.any((c) => c.autoConvert && c.toCode == unit.name);

  static double sizeOf(Unit unit) {
    _ensureBuilt();
    return _sizes[unit.name] ?? 1.0;
  }

  static Unit baseOf(Unit unit) {
    _ensureBuilt();
    return _bases[unit.name] ?? unit;
  }

  static void _ensureBuilt() {
    if (!_built) _rebuild();
  }

  /// Regroupe les unités en familles (composantes connexes du graphe de
  /// correspondances) ; l'unité de base d'une famille est la plus petite.
  static void _rebuild() {
    final adjacency = <String, List<(String, double)>>{};
    for (final c in _conversions) {
      if (c.factor <= 0) continue;
      // 1 from = factor to  ⇒  size(from) = factor × size(to)
      adjacency.putIfAbsent(c.fromCode, () => []).add((c.toCode, 1 / c.factor));
      adjacency.putIfAbsent(c.toCode, () => []).add((c.fromCode, c.factor));
    }

    final sizes = <String, double>{};
    final bases = <String, Unit>{};
    final visited = <String>{};

    for (final unit in _units) {
      if (visited.contains(unit.name)) continue;
      // Taille relative à l'unité de départ.
      final relative = <String, double>{unit.name: 1.0};
      final queue = <String>[unit.name];
      visited.add(unit.name);
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final (next, ratio) in adjacency[current] ?? const <(String, double)>[]) {
          if (visited.contains(next)) continue;
          visited.add(next);
          relative[next] = relative[current]! * ratio;
          queue.add(next);
        }
      }
      var baseCode = unit.name;
      for (final e in relative.entries) {
        final best = relative[baseCode]!;
        if (e.value < best - 1e-12 ||
            ((e.value - best).abs() <= 1e-12 && e.key.compareTo(baseCode) < 0)) {
          baseCode = e.key;
        }
      }
      final baseSize = relative[baseCode]!;
      final baseUnit = _byCode[baseCode]!;
      relative.forEach((code, size) {
        sizes[code] = size / baseSize;
        bases[code] = baseUnit;
      });
    }
    _sizes = sizes;
    _bases = bases;
    _built = true;
  }
}
