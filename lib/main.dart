import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:recipe_planner/data/services/seed_data_service.dart';
import 'package:recipe_planner/data/services/notification_service.dart';

import 'presentation/pages/recipes_page.dart';
import 'presentation/pages/planner_page.dart';
import 'presentation/pages/ingredients_page.dart';
import 'presentation/pages/shopping_list_page.dart';
import 'presentation/pages/login_page.dart';
import 'presentation/pages/access_denied_page.dart';
import 'presentation/pages/no_group_page.dart';
import 'presentation/providers/auth_notifier.dart';
import 'presentation/providers/auth_state.dart';

import 'data/repositories/notification_settings_repository.dart';
import 'data/repositories/group_repository.dart';
import 'firebase_options.dart';

const bool useTestData = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting();
  await NotificationService().initialize();

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _loadTestDataIfNeeded() async {
  final firestore = FirebaseFirestore.instance;
  final recipesSnapshot = await firestore.collection('recipes').limit(1).get();
  if (recipesSnapshot.docs.isNotEmpty) {
    await _purgeAllData(firestore);
  }
  await seedAllTestData();
}

Future<void> _purgeAllData(FirebaseFirestore firestore) async {
  // 'users' documents are NOT deleted (managed manually in Firestore).
  // Only their recipeServings subcollection is cleared so stale entries
  // (from old recipe IDs) don't accumulate between seed runs.
  final usersSnap = await firestore.collection('users').get();
  for (final userDoc in usersSnap.docs) {
    final servingsSnap = await userDoc.reference.collection('recipeServings').get();
    for (final sub in servingsSnap.docs) {
      await sub.reference.delete();
    }
  }

  final collections = ['recipes', 'ingredients', 'categories', 'mealPlans', 'mealPlanHistory', 'shopping_lists'];
  for (final col in collections) {
    final snap = await firestore.collection(col).get();
    for (final doc in snap.docs) {
      if (col == 'recipes') {
        final subSnap = await doc.reference.collection('userServings').get();
        for (final sub in subSnap.docs) {
          await sub.reference.delete();
        }
      }
      await doc.reference.delete();
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipe Planner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      home: const _AuthWrapper(),
    );
  }
}

class _AuthWrapper extends ConsumerWidget {
  const _AuthWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return switch (authState) {
      // ── Still determining session ──────────────────────────────────────────
      AuthInitial() || AuthLoading() => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),

      // ── Valid session + UID present in Firestore ───────────────────────────
      AuthAuthenticated() => const _DataLoader(),

      // ── UID not in Firestore – access refused ──────────────────────────────
      AuthDenied() => const AccessDeniedPage(),

      // ── No session or user signed out ─────────────────────────────────────
      AuthUnauthenticated() => const LoginPage(),

      // ── Unexpected error – show login page which already handles AuthError ──
      AuthError() => const LoginPage(),
    };
  }
}

class _DataLoader extends StatefulWidget {
  const _DataLoader();

  @override
  State<_DataLoader> createState() => _DataLoaderState();
}

class _DataLoaderState extends State<_DataLoader> {
  bool _isLoading = true;
  bool _hasGroup = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (useTestData) {
      await _loadTestDataIfNeeded();
    }
    // Check if the user belongs to a group
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    // Initialise les préférences de notification avec les valeurs par défaut
    // si l'utilisateur n'en a jamais configuré (première ouverture).
    await NotificationSettingsRepository().initializeDefaults();
    if (mounted) {
      setState(() {
        _hasGroup = groupId != null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasGroup) {
      return const NoGroupPage();
    }
    return const HomePage();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  static const int _pageCount = 4;
  final List<Widget> _pages = const [
    PlannerPage(),
    ShoppingListPage(),
    RecipesPage(),
    IngredientsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // Prevent index out of range
    final safeIndex = _selectedIndex.clamp(0, _pages.length - 1);
    return Scaffold(
      body: _pages[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: safeIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Planning',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Liste de courses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Recettes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.kitchen),
            label: 'Ingrédients',
          ),
        ],
      ),
    );
  }
}