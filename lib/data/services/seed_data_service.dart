import '../../core/constants/unit.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds all test data: ingredients, recipes, categories and user servings.
/// Users are NOT seeded here — they are managed manually in Firestore.
/// Servings are created for every user currently present in the `users` collection.
Future<void> seedAllTestData() async {
  await seedAllToFirestore();
}

/// Populates Firestore with distinct recipe categories and returns a {name: id} map
Future<Map<String, String>> seedCategoriesToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  // Map category name to color
  final categories = {
    'Viande': 0xFFE57373, // Red
    'Végétarien': 0xFF81C784, // Green
    'Pâtes': 0xFFFFD54F, // Amber
    'Asiatique': 0xFFFF8A65, // Deep Orange
    'Poisson': 0xFF4FC3F7, // Light Blue
    'Salade': 0xFFAED581, // Light Green
    'Sandwich': 0xFFA1887F, // Brown
    'Boisson': 0xFF4DB6AC, // Teal
    'Petit-déjeuner': 0xFFFFB74D, // Orange
  };

  final Map<String, String> nameToId = {};

  // Load existing categories
  final existing = await firestore.collection('categories').get();
  for (final doc in existing.docs) {
    final name = (doc.data()['name'] as String? ?? '').trim();
    if (name.isNotEmpty) nameToId[name] = doc.id;
  }

  for (final entry in categories.entries) {
    final name = entry.key;
    final color = entry.value;

    if (!nameToId.containsKey(name)) {
      final ref = await firestore.collection('categories').add({
        'name': name,
        'color': color,
      });
      nameToId[name] = ref.id;
    } else {
      // Update color for existing categories to ensure they have one
      await firestore.collection('categories').doc(nameToId[name]).update({'color': color});
    }
  }

  return nameToId;
}

/// Populates Firestore with ingredient types and returns a {name: id} map
Future<Map<String, String>> seedIngredientTypesToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  final types = {
    'Viande': 0xFFE57373,
    'Légume': 0xFF81C784,
    'Féculent': 0xFFFFD54F,
    'Poisson': 0xFF4FC3F7,
    'Produit laitier': 0xFFB39DDB,
    'Condiment': 0xFFA1887F,
    'Fruit': 0xFFFFB74D,
    'Oeuf': 0xFF90CAF9,
    'Herbe': 0xFF66BB6A,
    'Autre': 0xFFB0BEC5,
  };
  final Map<String, String> nameToId = {};
  final existing = await firestore.collection('ingredient_types').get();
  for (final doc in existing.docs) {
    final name = (doc.data()['name'] as String? ?? '').trim();
    if (name.isNotEmpty) nameToId[name] = doc.id;
  }
  for (final entry in types.entries) {
    final name = entry.key;
    final color = entry.value;
    if (!nameToId.containsKey(name)) {
      final ref = await firestore.collection('ingredient_types').add({
        'name': name,
        'color': color,
      });
      nameToId[name] = ref.id;
    } else {
      await firestore.collection('ingredient_types').doc(nameToId[name]).update({'color': color});
    }
  }
  return nameToId;
}

/// Populates Firestore with test users
Future<List<String>> seedTestUsersToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  final userDatas = [
    {'id': 'user_ugo', 'name': 'Ugo', 'email': 'ugo.vignon@gmail.com'},
    {'id': 'user_test', 'name': 'Test', 'email': 'test@test.com'},
  ];
  List<String> userIds = [];
  for (final user in userDatas) {
    await firestore.collection('users').doc(user['id']).set({
      'name': user['name'],
      'email': user['email'],
      'createdAt': DateTime.now().toIso8601String(),
    });
    userIds.add(user['id']!);
  }
  return userIds;
}

/// Populates Firestore with all test ingredients and recipes.
/// Creates UserRecipeServings for every user in the `users` collection.
Future<List<Recipe>> seedAllToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  final categoryIds = await seedCategoriesToFirestore();
  final ingredientIds = await seedIngredientsToFirestore();
  final recipes = buildRecipes(ingredientIds);
  final now = DateTime.now();
  List<Recipe> seededRecipes = [];

  // Load all users from Firestore (managed manually)
  final usersSnap = await firestore.collection('users').get();
  final existingUsers = usersSnap.docs.map((doc) {
    final data = doc.data();
    return {'id': doc.id, 'name': (data['name'] as String? ?? doc.id)};
  }).toList();

  for (int i = 0; i < recipes.length; i++) {
    final recipe = recipes[i];
    // Build user servings for all existing users (2 portions each)
    final List<Map<String, dynamic>> userServings = existingUsers.map((u) =>
      {'userId': u['id'], 'portion': 2, 'date': now.toIso8601String()}
    ).toList();

    // Add recipe document (without id field)
    // Store the category ID (not the name) for consistent referencing
    final firstCat = recipe.categoryIds.isNotEmpty ? recipe.categoryIds.first : '';
    final categoryId = categoryIds[firstCat] ?? firstCat;
    final recipeRef = await firestore.collection('recipes').add({
      'title': recipe.title,
      'description': recipe.description,
      'servings': recipe.servings,
      'category': categoryId,
      'categoryIds': [categoryId],
      'preparationTime': recipe.preparationTime,
      'cookingTime': recipe.cookingTime,
      'ingredients': recipe.ingredients.map((ri) => {
        'ingredientId': ri.ingredient.id,
        'ingredientName': ri.ingredient.name,
        'quantity': ri.quantity,
        'unit': ri.unit.name,
        'notes': ri.notes,
      }).toList(),
      'instructions': recipe.instructions,
      'createdAt': recipe.createdAt.toIso8601String(),
      'isFavorite': recipe.isFavorite,
      'rating': recipe.rating,
      'addExtraMeal': recipe.addExtraMeal,
      'userServings': userServings,
      'url': 'https://example.com/recette-${i+1}',
    });

    // Update the recipe document to set its id field
    await firestore.collection('recipes').doc(recipeRef.id).update({'id': recipeRef.id});

    // Add user servings to user_recipe_servings collection
    final userNameMap = {for (final u in existingUsers) u['id']!: u['name']!};

    for (final serving in userServings) {
      final lunch = (serving['portion'] as int) ~/ 2;
      final dinner = (serving['portion'] as int) - lunch;
      final data = {
        'userId': serving['userId'],
        'userName': userNameMap[serving['userId']] ?? serving['userId'],
        'lunchServings': lunch,
        'dinnerServings': dinner,
        'recipeId': recipeRef.id,
        'recipeTitle': recipe.title,
        'createdAt': Timestamp.now(),
      };

      // recipe side
      await firestore
          .collection('recipes')
          .doc(recipeRef.id)
          .collection('userServings')
          .doc(serving['userId'])
          .set(data);

      // user side
      await firestore
          .collection('users')
          .doc(serving['userId'])
          .collection('recipeServings')
          .doc(recipeRef.id)
          .set(data);
    }

    seededRecipes.add(recipe.copyWith(id: recipeRef.id));
  }

  return seededRecipes;
}

/// Builds 10 test recipes
List<Recipe> buildRecipes(Map<String, String> ingredients) {
  return [
    // Recettes existantes
    _createRecipe(
      title: 'Boeuf mijoté',
      description: 'Ragoût de bœuf copieux aux légumes',
      servings: 6,
      category: 'Viande',
      preparationTime: 20,
      cookingTime: 120,
      ingredients: [
        ('Boeuf', ingredients['Boeuf']!, 800, Unit.g, null),
        ('Pomme de terre', ingredients['Pomme de terre']!, 400, Unit.g, null),
        ('Carotte', ingredients['Carotte']!, 300, Unit.g, null),
        ('Oignon', ingredients['Oignon']!, 2, Unit.piece, null),
        ('Ail', ingredients['Ail']!, 4, Unit.piece, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 3, Unit.tablespoon, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Couper le bœuf en morceaux',
        'Faire revenir la viande',
        'Ajouter oignon et ail',
        'Ajouter pommes de terre et carottes',
        'Laisser mijoter 2h',
        'Assaisonner et servir',
      ],
      addExtraMeal: true,
    ),
    _createRecipe(
      title: 'Soupe de lentilles',
      description: 'Soupe de lentilles nourrissante',
      servings: 6,
      category: 'Végétarien',
      preparationTime: 10,
      cookingTime: 40,
      ingredients: [
        ('Lentilles', ingredients['Lentilles']!, 300, Unit.g, null),
        ('Carotte', ingredients['Carotte']!, 200, Unit.g, null),
        ('Oignon', ingredients['Oignon']!, 1, Unit.piece, null),
        ('Ail', ingredients['Ail']!, 2, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Rincer les lentilles',
        'Faire revenir oignon et ail',
        'Ajouter les légumes et l’eau',
        'Cuire 40 minutes',
        'Mixer partiellement',
      ],
      addExtraMeal: true,
    ),
    _createRecipe(
      title: 'Spaghetti carbonara',
      description: 'Pâtes crémeuses à l’italienne',
      servings: 2,
      category: 'Pâtes',
      preparationTime: 10,
      cookingTime: 15,
      ingredients: [
        ('Spaghetti', ingredients['Spaghetti']!, 200, Unit.g, null),
        ('Oeuf', ingredients['Oeuf']!, 2, Unit.piece, null),
        ('Lardons', ingredients['Lardons']!, 150, Unit.g, null),
        ('Parmesan', ingredients['Parmesan']!, 40, Unit.g, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Cuire les pâtes',
        'Faire revenir les lardons',
        'Mélanger œufs et parmesan',
        'Assembler hors du feu',
        'Poivrer et servir',
      ],
    ),
    _createRecipe(
      title: 'Curry vert thaï',
      description: 'Curry parfumé au lait de coco',
      servings: 4,
      category: 'Asiatique',
      preparationTime: 15,
      cookingTime: 25,
      ingredients: [
        ('Poulet', ingredients['Poulet']!, 500, Unit.g, null),
        ('Lait de coco', ingredients['Lait de coco']!, 400, Unit.ml, null),
        ('Pâte de curry vert', ingredients['Pâte de curry vert']!, 2, Unit.tablespoon, null),
        ('Poivron', ingredients['Poivron']!, 1, Unit.piece, null),
        ('Riz', ingredients['Riz']!, 300, Unit.g, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Cuire le riz',
        'Faire revenir la pâte de curry',
        'Ajouter le poulet',
        'Verser le lait de coco',
        'Laisser mijoter',
      ],
      addExtraMeal: true,
    ),
    _createRecipe(
      title: 'Saumon grillé',
      description: 'Filet de saumon simple et rapide',
      servings: 2,
      category: 'Poisson',
      preparationTime: 5,
      cookingTime: 10,
      ingredients: [
        ('Saumon', ingredients['Saumon']!, 300, Unit.g, null),
        ('Citron', ingredients['Citron']!, 1, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Assaisonner le saumon',
        'Griller côté peau',
        'Ajouter le citron',
      ],
    ),

    // Nouvelles recettes
    _createRecipe(
      title: 'Salade de poulet et légumes',
      description: 'Salade fraîche et saine',
      servings: 4,
      category: 'Salade',
      preparationTime: 10,
      cookingTime: 0,
      ingredients: [
        ('Poulet', ingredients['Poulet']!, 200, Unit.g, null),
        ('Salade', ingredients['Salade']!, 100, Unit.g, null),
        ('Tomate', ingredients['Tomate']!, 2, Unit.piece, null),
        ('Concombre', ingredients['Concombre']!, 1, Unit.piece, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 2, Unit.tablespoon, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Couper tous les légumes',
        'Cuire et découper le poulet',
        'Mélanger avec huile d’olive, sel et poivre',
      ],
    ),
    _createRecipe(
      title: 'Pâtes aux champignons',
      description: 'Pâtes crémeuses aux champignons',
      servings: 2,
      category: 'Pâtes',
      preparationTime: 10,
      cookingTime: 15,
      ingredients: [
        ('Spaghetti', ingredients['Spaghetti']!, 200, Unit.g, null),
        ('Champignon', ingredients['Champignon']!, 150, Unit.g, null),
        ('Lait de coco', ingredients['Lait de coco']!, 100, Unit.ml, null),
        ('Parmesan', ingredients['Parmesan']!, 30, Unit.g, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Cuire les pâtes',
        'Faire revenir les champignons',
        'Mélanger avec crème et parmesan',
      ],
    ),
    _createRecipe(
      title: 'Wrap au thon',
      description: 'Wrap rapide et léger',
      servings: 2,
      category: 'Sandwich',
      preparationTime: 5,
      cookingTime: 0,
      ingredients: [
        ('Thon', ingredients['Thon']!, 100, Unit.g, null),
        ('Salade', ingredients['Salade']!, 50, Unit.g, null),
        ('Maïs', ingredients['Maïs']!, 50, Unit.g, null),
        ('Pain', ingredients['Pain']!, 2, Unit.piece, null),
        ('Tomate', ingredients['Tomate']!, 1, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Étaler les ingrédients sur le pain',
        'Rouler et servir',
      ],
    ),
    _createRecipe(
      title: 'Smoothie fruité',
      description: 'Smoothie rapide et vitaminé',
      servings: 2,
      category: 'Boisson',
      preparationTime: 5,
      cookingTime: 0,
      ingredients: [
        ('Banane', ingredients['Banane']!, 1, Unit.piece, null),
        ('Pomme', ingredients['Pomme']!, 1, Unit.piece, null),
        ('Lait de coco', ingredients['Lait de coco']!, 100, Unit.ml, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, 'une pincée pour rehausser les saveurs'),
      ],
      instructions: [
        'Mixer tous les fruits avec le lait de coco',
      ],
    ),
    _createRecipe(
      title: 'Omelette aux légumes',
      description: 'Omelette rapide et saine',
      servings: 2,
      category: 'Petit-déjeuner',
      preparationTime: 5,
      cookingTime: 10,
      ingredients: [
        ('Oeuf', ingredients['Oeuf']!, 2, Unit.piece, null),
        ('Tomate', ingredients['Tomate']!, 1, Unit.piece, null),
        ('Courgette', ingredients['Courgette']!, 50, Unit.g, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: [
        'Battre les oeufs',
        'Ajouter les légumes hachés',
        'Cuire à la poêle',
      ],
    ),

    // ── Recettes de test pour la hauteur dynamique (toutes avec Sel) ──
    _createRecipe(
      title: 'Gratin dauphinois',
      description: 'Gratin de pommes de terre crémeux',
      servings: 4,
      category: 'Végétarien',
      preparationTime: 15,
      cookingTime: 60,
      ingredients: [
        ('Pomme de terre', ingredients['Pomme de terre']!, 800, Unit.g, null),
        ('Lait de coco', ingredients['Lait de coco']!, 300, Unit.ml, null),
        ('Fromage râpé', ingredients['Fromage râpé']!, 80, Unit.g, null),
        ('Ail', ingredients['Ail']!, 2, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Couper les pommes de terre', 'Disposer en couches', 'Verser la crème', 'Gratiner au four'],
    ),
    _createRecipe(
      title: 'Riz cantonais',
      description: 'Riz sauté aux légumes et œufs',
      servings: 4,
      category: 'Asiatique',
      preparationTime: 10,
      cookingTime: 15,
      ingredients: [
        ('Riz', ingredients['Riz']!, 300, Unit.g, null),
        ('Oeuf', ingredients['Oeuf']!, 2, Unit.piece, null),
        ('Carotte', ingredients['Carotte']!, 100, Unit.g, null),
        ('Maïs', ingredients['Maïs']!, 80, Unit.g, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 2, Unit.tablespoon, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
      ],
      instructions: ['Cuire le riz', 'Sauter les légumes', 'Ajouter les œufs', 'Mélanger le tout'],
    ),
    _createRecipe(
      title: 'Poêlée de crevettes',
      description: "Crevettes sautées à l'ail",
      servings: 2,
      category: 'Poisson',
      preparationTime: 5,
      cookingTime: 8,
      ingredients: [
        ('Crevettes', ingredients['Crevettes']!, 300, Unit.g, null),
        ('Ail', ingredients['Ail']!, 3, Unit.piece, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 2, Unit.tablespoon, null),
        ('Citron', ingredients['Citron']!, 1, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ["Faire chauffer l'huile", "Sauter les crevettes avec l'ail", 'Presser le citron'],
    ),
    _createRecipe(
      title: 'Soupe de tomates',
      description: 'Soupe de tomates fraîches au basilic',
      servings: 4,
      category: 'Végétarien',
      preparationTime: 10,
      cookingTime: 20,
      ingredients: [
        ('Tomate', ingredients['Tomate']!, 600, Unit.g, null),
        ('Oignon', ingredients['Oignon']!, 1, Unit.piece, null),
        ('Ail', ingredients['Ail']!, 2, Unit.piece, null),
        ('Basilic', ingredients['Basilic']!, 5, Unit.g, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Faire revenir oignon et ail', 'Ajouter les tomates', 'Cuire 20 min', 'Mixer et assaisonner'],
    ),
    _createRecipe(
      title: 'Poulet rôti',
      description: 'Poulet rôti classique aux herbes',
      servings: 4,
      category: 'Viande',
      preparationTime: 10,
      cookingTime: 90,
      ingredients: [
        ('Poulet', ingredients['Poulet']!, 1200, Unit.g, null),
        ('Ail', ingredients['Ail']!, 4, Unit.piece, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 3, Unit.tablespoon, null),
        ('Citron', ingredients['Citron']!, 1, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 3, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 2, Unit.pinch, null),
      ],
      instructions: ['Préchauffer le four', 'Badigeonner le poulet', 'Enfourner 1h30'],
    ),
    _createRecipe(
      title: 'Taboulé',
      description: 'Salade de semoule fraîche',
      servings: 4,
      category: 'Salade',
      preparationTime: 15,
      cookingTime: 0,
      ingredients: [
        ('Tomate', ingredients['Tomate']!, 2, Unit.piece, null),
        ('Concombre', ingredients['Concombre']!, 1, Unit.piece, null),
        ('Citron', ingredients['Citron']!, 1, Unit.piece, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 3, Unit.tablespoon, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
      ],
      instructions: ['Préparer la semoule', 'Couper les légumes', 'Mélanger et assaisonner'],
    ),
    _createRecipe(
      title: 'Boeuf haché sauce tomate',
      description: 'Sauce bolognaise maison',
      servings: 4,
      category: 'Viande',
      preparationTime: 10,
      cookingTime: 45,
      ingredients: [
        ('Boeuf', ingredients['Boeuf']!, 500, Unit.g, null),
        ('Tomate', ingredients['Tomate']!, 400, Unit.g, null),
        ('Oignon', ingredients['Oignon']!, 1, Unit.piece, null),
        ('Ail', ingredients['Ail']!, 3, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Faire revenir la viande', 'Ajouter la sauce tomate', 'Laisser mijoter 45 min'],
    ),
    _createRecipe(
      title: 'Quiche lorraine',
      description: 'Quiche aux lardons et fromage',
      servings: 6,
      category: 'Petit-déjeuner',
      preparationTime: 15,
      cookingTime: 35,
      ingredients: [
        ('Oeuf', ingredients['Oeuf']!, 3, Unit.piece, null),
        ('Lardons', ingredients['Lardons']!, 200, Unit.g, null),
        ('Fromage râpé', ingredients['Fromage râpé']!, 100, Unit.g, null),
        ('Lait de coco', ingredients['Lait de coco']!, 200, Unit.ml, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Préparer la garniture', 'Verser dans le moule', 'Cuire 35 min'],
    ),
    _createRecipe(
      title: 'Pâtes bolognaise',
      description: 'Spaghetti à la sauce bolognaise',
      servings: 4,
      category: 'Pâtes',
      preparationTime: 10,
      cookingTime: 30,
      ingredients: [
        ('Spaghetti', ingredients['Spaghetti']!, 400, Unit.g, null),
        ('Boeuf', ingredients['Boeuf']!, 400, Unit.g, null),
        ('Tomate', ingredients['Tomate']!, 300, Unit.g, null),
        ('Oignon', ingredients['Oignon']!, 1, Unit.piece, null),
        ('Sel', ingredients['Sel']!, 2, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Cuire les pâtes', 'Préparer la bolognaise', 'Assembler et servir'],
    ),
    _createRecipe(
      title: 'Poêlée de légumes',
      description: 'Légumes sautés colorés',
      servings: 2,
      category: 'Végétarien',
      preparationTime: 10,
      cookingTime: 15,
      ingredients: [
        ('Poivron', ingredients['Poivron']!, 1, Unit.piece, null),
        ('Courgette', ingredients['Courgette']!, 150, Unit.g, null),
        ('Champignon', ingredients['Champignon']!, 100, Unit.g, null),
        ("Huile d'olive", ingredients["Huile d'olive"]!, 2, Unit.tablespoon, null),
        ('Sel', ingredients['Sel']!, 1, Unit.pinch, null),
        ('Poivre', ingredients['Poivre']!, 1, Unit.pinch, null),
      ],
      instructions: ['Couper les légumes', 'Faire sauter à feu vif', 'Assaisonner'],
    ),
  ];
}

/// Saves all required ingredients to Firestore and returns the {name: id} map
Future<Map<String, String>> seedIngredientsToFirestore() async {
  final ingredientNames = [
    'Boeuf','Pomme de terre','Carotte','Oignon','Ail',"Huile d'olive",'Sel','Poivre',
    'Lentilles','Spaghetti','Oeuf','Lardons','Parmesan','Poulet','Lait de coco',
    'Pâte de curry vert','Poivron','Riz','Saumon','Citron','Tomate','Courgette',
    'Basilic','Champignon','Crevettes','Fromage râpé','Thon','Pain','Salade','Concombre',
    'Maïs','Pomme','Banane',
  ];
  final firestore = FirebaseFirestore.instance;
  final typeIds = await seedIngredientTypesToFirestore();
  final Map<String, String> ids = {};
  // Mapping ingredient to type
  final Map<String, String> ingredientType = {
    'Boeuf': 'Viande',
    'Poulet': 'Viande',
    'Lardons': 'Viande',
    'Saumon': 'Poisson',
    'Thon': 'Poisson',
    'Crevettes': 'Poisson',
    'Pomme de terre': 'Féculent',
    'Riz': 'Féculent',
    'Spaghetti': 'Féculent',
    'Pain': 'Féculent',
    'Lentilles': 'Féculent',
    'Carotte': 'Légume',
    'Oignon': 'Légume',
    'Ail': 'Légume',
    'Poivron': 'Légume',
    'Courgette': 'Légume',
    'Champignon': 'Légume',
    'Salade': 'Légume',
    'Concombre': 'Légume',
    'Maïs': 'Légume',
    'Tomate': 'Légume',
    'Basilic': 'Herbe',
    'Citron': 'Fruit',
    'Pomme': 'Fruit',
    'Banane': 'Fruit',
    'Oeuf': 'Oeuf',
    'Parmesan': 'Produit laitier',
    'Fromage râpé': 'Produit laitier',
    'Lait de coco': 'Produit laitier',
    'Pâte de curry vert': 'Condiment',
    "Huile d'olive": 'Condiment',
    'Sel': 'Condiment',
    'Poivre': 'Condiment',
  };
  for (final name in ingredientNames) {
    final typeName = ingredientType[name] ?? 'Autre';
    final typeId = typeIds[typeName];
    final doc = await firestore.collection('ingredients').add({
      'name': name,
      'typeId': typeId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    ids[name] = doc.id;
  }
  return ids;
}

Recipe _createRecipe({
  required String title,
  required String description,
  required int servings,
  required String category,
  required int preparationTime,
  required int cookingTime,
  required List<(String ingredientName, String ingredientId, num quantity, Unit unit, String? notes)>
      ingredients,
  required List<String> instructions,
  bool addExtraMeal = false,
}) {
  return Recipe(
    id: '',
    title: title.toLowerCase(),
    description: description,
    servings: servings,
    categoryIds: [category],
    preparationTime: preparationTime,
    cookingTime: cookingTime,
    ingredients: ingredients
        .map(
          (ing) => RecipeIngredient(
            ingredient: Ingredient(id: ing.$2, name: ing.$1),
            quantity: ing.$3.toDouble(),
            unit: ing.$4,
            notes: ing.$5,
          ),
        )
        .toList(),
    instructions: instructions,
    createdAt: DateTime.now(),
    isFavorite: false,
    rating: 0.0,
    addExtraMeal: addExtraMeal,
  );
}