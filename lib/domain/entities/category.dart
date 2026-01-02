class Category {
  final String id;
  final String name;

  Category({
    required this.id,
    required this.name,
  });

  /// Création depuis Firestore
  factory Category.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return Category(
      id: id,
      name: data['name'] as String,
    );
  }

  /// Conversion vers Firestore (si besoin plus tard)
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
    };
  }
}