class IngredientType {
  final String id;
  final String name;
  final int color;

  IngredientType({
    required this.id,
    required this.name,
    this.color = 0xFF6A5AE0,
  });

  factory IngredientType.fromFirestore(String id, Map<String, dynamic> data) {
    return IngredientType(
      id: id,
      name: data['name'] as String,
      color: data['color'] is int ? data['color'] as int : 0xFF6A5AE0,
    );
  }
}
