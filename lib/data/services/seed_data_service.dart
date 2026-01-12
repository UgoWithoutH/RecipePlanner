import '../../core/constants/unit.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds all test data: users, ingredients, recipes, and user servings
Future<void> seedAllTestData() async {
  await seedTestUsersToFirestore();
  await seedAllToFirestore();
}

/// Populates Firestore with test users
Future<List<String>> seedTestUsersToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  final userDatas = [
    {'id': 'userA', 'name': 'Alice', 'email': 'alice@test.com'},
    {'id': 'userB', 'name': 'Bob', 'email': 'bob@test.com'},
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

/// Populates Firestore with all test ingredients and recipes
Future<List<Recipe>> seedAllToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  final ingredientIds = await seedIngredientsToFirestore();
  final recipes = buildRecipes(ingredientIds);
  final now = DateTime.now();
  List<Recipe> seededRecipes = [];

  for (int i = 0; i < recipes.length; i++) {
    final recipe = recipes[i];
    // User servings test cases for planning algorithm
    // Each user has at least 1 portion for every recipe
    List<Map<String, dynamic>> userServings = [];

    switch (i) {
      case 0:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 1:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 2:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 3:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 4:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 5:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 6:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 7:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 8:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
      case 9:
        userServings = [
          {'userId': 'userA', 'portion': 2, 'date': now.toIso8601String()},
          {'userId': 'userB', 'portion': 2, 'date': now.toIso8601String()},
        ];
        break;
    }

    // Add recipe document (without id field)
    final recipeRef = await firestore.collection('recipes').add({
      'title': recipe.title,
      'description': recipe.description,
      'servings': recipe.servings,
      'category': recipe.category,
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
    });

    // Update the recipe document to set its id field
    await firestore.collection('recipes').doc(recipeRef.id).update({'id': recipeRef.id});

    // Add user servings to user_recipe_servings collection
    final userMap = {'userA': 'Alice', 'userB': 'Bob'};

    for (final serving in userServings) {
      final lunch = (serving['portion'] as int) ~/ 2;
      final dinner = (serving['portion'] as int) - lunch;
      final data = {
        'userId': serving['userId'],
        'userName': userMap[serving['userId']] ?? serving['userId'],
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
  final Map<String, String> ids = {};
  for (final name in ingredientNames) {
    final doc = await firestore.collection('ingredients').add({
      'name': name,
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
    category: category,
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