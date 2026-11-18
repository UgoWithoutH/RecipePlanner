import 'unit.dart';

/// Équivalence propre à un ingrédient : 1 [unitCode] = [amount] [targetCode]
/// (ex : pour « lardons », 1 paquet = 200 g).
class IngredientEquivalence {
  final String unitCode;
  final double amount;
  final String targetCode;

  const IngredientEquivalence({
    required this.unitCode,
    required this.amount,
    required this.targetCode,
  });

  Map<String, dynamic> toMap() => {
        'unit': unitCode,
        'amount': amount,
        'targetUnit': targetCode,
      };

  static IngredientEquivalence? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final unit = raw['unit'] as String?;
    final target = raw['targetUnit'] as String?;
    final amount = (raw['amount'] as num?)?.toDouble();
    if (unit == null || target == null || amount == null || amount <= 0) {
      return null;
    }
    return IngredientEquivalence(
        unitCode: unit, amount: amount, targetCode: target);
  }

  static List<IngredientEquivalence> listFromRaw(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(fromMap).whereType<IngredientEquivalence>().toList();
  }
}

/// Registre en mémoire des équivalences par ingrédient (clé : nom en minuscules).
/// Il complète [UnitRegistry] : une unité sans correspondance globale (paquet,
/// pièce…) devient convertible pour les ingrédients qui définissent une équivalence.
class IngredientEquivalences {
  static Map<String, List<IngredientEquivalence>> _byName = {};

  static String _key(String name) => name.toLowerCase().trim();

  static void configure(Map<String, List<IngredientEquivalence>> byName) {
    _byName = {
      for (final e in byName.entries)
        if (e.value.isNotEmpty) _key(e.key): List.unmodifiable(e.value),
    };
  }

  static List<IngredientEquivalence> of(String name) =>
      _byName[_key(name)] ?? const [];

  static IngredientEquivalence? _find(String name, Unit unit) {
    for (final e in of(name)) {
      if (e.unitCode == unit.name &&
          e.targetCode != unit.name &&
          Unit.byName(e.targetCode) != null) {
        return e;
      }
    }
    return null;
  }

  /// Unité de base de la famille de [unit], en tenant compte des équivalences
  /// de l'ingrédient [name].
  static Unit baseUnitFor(String name, Unit unit) {
    final e = _find(name, unit);
    return e == null ? unit.baseUnit : Unit.byName(e.targetCode)!.baseUnit;
  }

  /// Convertit [qty] exprimée en [unit] vers l'unité de base de sa famille.
  static double toBaseFor(String name, double qty, Unit unit) {
    final e = _find(name, unit);
    if (e == null) return unit.toBase(qty);
    return Unit.byName(e.targetCode)!.toBase(qty * e.amount);
  }

  /// Convertit [baseQty] (unité de base de la famille) vers [unit].
  static double fromBaseFor(String name, double baseQty, Unit unit) {
    final e = _find(name, unit);
    if (e == null) return unit.fromBase(baseQty);
    return baseQty / Unit.byName(e.targetCode)!.toBase(e.amount);
  }

  static bool isSameDimensionFor(String name, Unit a, Unit b) =>
      a == b || baseUnitFor(name, a) == baseUnitFor(name, b);

  /// Convertit [qty] de [from] vers [to], ou null si les unités sont incompatibles.
  static double? convertFor(String name, double qty, Unit from, Unit to) {
    if (from == to) return qty;
    if (!isSameDimensionFor(name, from, to)) return null;
    return fromBaseFor(name, toBaseFor(name, qty, from), to);
  }

  /// Si [unit] a une équivalence pour cet ingrédient, exprime [qty] dans
  /// l'unité cible (ex : 1.5 paquet → 300 g). Sinon retourne la valeur inchangée.
  static (double, Unit) resolve(String name, double qty, Unit unit) {
    final e = _find(name, unit);
    if (e == null) return (qty, unit);
    return (qty * e.amount, Unit.byName(e.targetCode)!);
  }

  /// Quantités équivalentes à [qty] [unit] dans les autres unités définies par
  /// les équivalences de l'ingrédient (ex : 300 g → 1.5 paquet).
  static List<(double, Unit)> alternativesFor(
      String name, double qty, Unit unit) {
    if (qty <= 0) return const [];
    final result = <(double, Unit)>[];
    final seen = <String>{unit.name};
    for (final e in of(name)) {
      for (final code in [
        e.unitCode,
        if (e.unitCode == unit.name) e.targetCode,
      ]) {
        final other = Unit.byName(code);
        if (other == null || !seen.add(code)) continue;
        final converted = convertFor(name, qty, unit, other);
        if (converted != null) result.add((converted, other));
      }
    }
    return result;
  }
}
