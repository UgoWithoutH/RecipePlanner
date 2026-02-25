class Category {
  final String id;
  final String name;
  final int color;

  Category({
    required this.id,
    required this.name,
    this.color = 0xFF6A5AE0,
  });

  /// Creation from Firestore
  factory Category.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return Category(
      id: id,
      name: data['name'] as String,
      color: data['color'] is int ? data['color'] as int : 0xFF6A5AE0,
    );
  }

  /// Conversion vers Firestore (si besoin plus tard)
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'color': color,
    };
  }
}