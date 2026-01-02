class Ingredient {
  final String id;
  final String name;

  Ingredient({
    required this.id,
    required this.name,
  });

  // Copy with modifications
  Ingredient copyWith({
    String? id,
    String? name,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => name;
}
