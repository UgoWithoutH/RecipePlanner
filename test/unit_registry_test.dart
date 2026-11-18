import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_planner/core/constants/unit.dart';
import 'package:recipe_planner/core/constants/ingredient_equivalence.dart';

void main() {
  setUp(() => UnitRegistry.configure(
      units: Unit.defaults, conversions: UnitConversion.defaults));

  test('default conversions behave like the former hard-coded ones', () {
    expect(Unit.kg.convertTo(2, Unit.g), 2000);
    expect(Unit.ml.convertTo(500, Unit.l), 0.5);
    expect(Unit.cup.toBase(1), 48);
    expect(Unit.g.convertTo(1, Unit.ml), isNull);
    expect(Unit.g.normalize(1500), (1.5, Unit.kg));
    expect(Unit.teaspoon.normalize(9), (9.0, Unit.teaspoon));
  });

  test('custom units and conversions are used', () {
    const cl = Unit('cl', 'cl');
    UnitRegistry.configure(
      units: [...Unit.defaults, cl],
      conversions: [
        ...UnitConversion.defaults,
        const UnitConversion(fromCode: 'cl', toCode: 'ml', factor: 10),
      ],
    );
    expect(cl.convertTo(3, Unit.l), closeTo(0.03, 1e-9));
    expect(Unit.l.baseUnit, Unit.ml);
    expect(Unit.byName('cl'), cl);
  });

  test('ingredient equivalences make a unit convertible for that ingredient only', () {
    IngredientEquivalences.configure({
      'Lardons': const [
        IngredientEquivalence(unitCode: 'piece', amount: 200, targetCode: 'g'),
      ],
    });
    // 1 pièce = 200 g, et la famille « g » inclut aussi kg
    expect(IngredientEquivalences.toBaseFor('lardons', 1.5, Unit.piece), 300);
    expect(IngredientEquivalences.baseUnitFor('lardons', Unit.piece), Unit.g);
    expect(IngredientEquivalences.convertFor('lardons', 0.4, Unit.kg, Unit.piece), 2);
    expect(IngredientEquivalences.resolve('lardons', 1.5, Unit.piece), (300.0, Unit.g));
    final alts = IngredientEquivalences.alternativesFor('lardons', 300, Unit.g);
    expect(alts, [(1.5, Unit.piece)]);
    // Autre ingrédient : pas de conversion
    expect(IngredientEquivalences.convertFor('pâtes', 1, Unit.piece, Unit.g), isNull);
    IngredientEquivalences.configure({});
  });

  test('equivalences combine with global conversions and several equivalences', () {
    const paquet = Unit('paquet', 'paquet');
    UnitRegistry.configure(
        units: [...Unit.defaults, paquet], conversions: UnitConversion.defaults);
    IngredientEquivalences.configure({
      // cible exprimée en kg (non-base) + volume via une 2e équivalence
      'Lardons': const [
        IngredientEquivalence(unitCode: 'paquet', amount: 0.2, targetCode: 'kg'),
        IngredientEquivalence(unitCode: 'piece', amount: 50, targetCode: 'g'),
      ],
      'Crème': const [
        IngredientEquivalence(unitCode: 'paquet', amount: 0.25, targetCode: 'l'),
      ],
    });
    // 1,5 paquet = 0,3 kg = 300 g (base g)
    expect(IngredientEquivalences.baseUnitFor('lardons', paquet), Unit.g);
    expect(IngredientEquivalences.toBaseFor('lardons', 1.5, paquet), closeTo(300, 1e-9));
    // paquet <-> pièce via la base commune, et kg inchangé
    expect(IngredientEquivalences.convertFor('lardons', 1, paquet, Unit.piece),
        closeTo(4, 1e-9));
    expect(IngredientEquivalences.toBaseFor('lardons', 0.5, Unit.kg), 500);
    expect(IngredientEquivalences.baseUnitFor('lardons', Unit.piece), Unit.g);
    // volume : 2 paquets = 0,5 l = 500 ml
    expect(IngredientEquivalences.toBaseFor('crème', 2, paquet), closeTo(500, 1e-9));
    expect(IngredientEquivalences.baseUnitFor('crème', paquet), Unit.ml);
    // un ingrédient sans équivalence garde le comportement global
    expect(IngredientEquivalences.baseUnitFor('riz', Unit.kg), Unit.g);
    expect(IngredientEquivalences.toBaseFor('riz', 2, Unit.kg), 2000);
    expect(IngredientEquivalences.convertFor('riz', 1, paquet, Unit.g), isNull);
    // affichage : 300 g -> 1,5 paquet
    final alts = IngredientEquivalences.alternativesFor('lardons', 300, Unit.g);
    expect(alts.map((a) => a.$2), containsAll([paquet, Unit.piece]));
    IngredientEquivalences.configure({});
    UnitRegistry.configure(units: Unit.defaults, conversions: UnitConversion.defaults);
  });
}
