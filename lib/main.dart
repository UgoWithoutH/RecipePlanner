import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:recipe_planner/data/services/seed_data_service.dart';

import 'presentation/pages/recipes_page.dart';
import 'presentation/pages/planner_page.dart';
import 'presentation/pages/ingredients_page.dart';
import 'presentation/pages/shopping_list_page.dart';
import 'presentation/providers/auth_notifier.dart';

import 'firebase_options.dart';

const bool useTestData = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting();

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _loadTestDataIfNeeded() async {
  final firestore = FirebaseFirestore.instance;
  final recipesSnapshot = await firestore.collection('recipes').limit(1).get();
  if (recipesSnapshot.docs.isNotEmpty) return;
  await seedAllTestData();
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

    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              ref.read(authNotifierProvider.notifier).signInAnonymously();
            },
            child: const Text('Réessayer'),
          ),
        ),
      ),
      data: (user) =>
          user != null ? const _DataLoader() : const SizedBox.shrink(),
    );
  }
}

class _DataLoader extends StatefulWidget {
  const _DataLoader();

  @override
  State<_DataLoader> createState() => _DataLoaderState();
}

class _DataLoaderState extends State<_DataLoader> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (useTestData) {
      await _loadTestDataIfNeeded();
    }
    if (mounted) {
      setState(() {
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
            label: 'Planner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Liste de courses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Recipes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.kitchen),
            label: 'Ingredients',
          ),
        ],
      ),
    );
  }
}