enum Unit {
  g('g'),
  kg('kg'),
  ml('ml'),
  l('l'),
  teaspoon('c.à.t.'),
  tablespoon('c.à.s.'),
  cup('tasse'),
  piece('pièce'),
  pinch('pincée');

  final String label;
  const Unit(this.label);
}