class User {
  final String id;
  final String name;
  final String email;

  const User({
    required this.id,
    required this.name,
    this.email = '',
  });

  factory User.fromFirestore(String id, Map<String, dynamic> data) {
    return User(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
    };
  }
}