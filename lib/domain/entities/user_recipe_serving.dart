class UserRecipeServing {
  final String userId;
  final String recipeId;
  final String userName;
  final String recipeTitle;
  final int lunchServings;
  final int dinnerServings;

  UserRecipeServing({
    required this.userId,
    required this.recipeId,
    required this.userName,
    required this.recipeTitle,
    this.lunchServings = 0,
    this.dinnerServings = 0,
  });

  /// CopyWith
  UserRecipeServing copyWith({
    String? userId,
    String? recipeId,
    String? userName,
    String? recipeTitle,
    int? lunchServings,
    int? dinnerServings,
  }) {
    return UserRecipeServing(
      userId: userId ?? this.userId,
      recipeId: recipeId ?? this.recipeId,
      userName: userName ?? this.userName,
      recipeTitle: recipeTitle ?? this.recipeTitle,
      lunchServings: lunchServings ?? this.lunchServings,
      dinnerServings: dinnerServings ?? this.dinnerServings,
    );
  }

  /// Create from Firestore
  factory UserRecipeServing.fromFirestore(Map<String, dynamic> data,
      {required String userId, required String recipeId}) {
    return UserRecipeServing(
      userId: userId,
      recipeId: recipeId,
      userName: data['userName'] ?? '',
      recipeTitle: data['recipeTitle'] ?? '',
      lunchServings: (data['lunchServings'] as int?) ?? 0,
      dinnerServings: (data['dinnerServings'] as int?) ?? 0,
    );
  }

  /// Convert to Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'recipeId': recipeId,
      'userName': userName,
      'recipeTitle': recipeTitle,
      'lunchServings': lunchServings,
      'dinnerServings': dinnerServings,
    };
  }
}