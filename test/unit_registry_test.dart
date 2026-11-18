import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_planner/core/constants/unit.dart';

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
}
