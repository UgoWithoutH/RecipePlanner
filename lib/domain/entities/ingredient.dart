class Ingredient {
  final String id;
  final String name;
  final String? typeId;

  Ingredient({
    required this.id,
    required this.name,
    this.typeId,
  });

  // Copy with modifications
  Ingredient copyWith({
    String? id,
    String? name,
    String? typeId,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      typeId: typeId ?? this.typeId,
    );
  }

  @override
  String toString() => name;
}
