# Documentation de l'Algorithme de Planification des Repas

## Vue d'ensemble

L'algorithme de planification des repas génère automatiquement un planning optimisé sur une période donnée en respectant les préférences utilisateurs, en maximisant la diversité, et en minimisant les répétitions d'ingrédients similaires.

**Objectifs principaux:**
1. **Respect des portions utilisateurs** - Chaque utilisateur reçoit exactement ses portions déclarées
2. **Diversité maximale** - Éviter les répétitions de recettes et d'ingrédients similaires
3. **Optimisation de la cuisine** - Cuisiner une fois, manger deux fois (avec `addExtraMeal`)
4. **Équité entre utilisateurs** - Priorité aux utilisateurs ayant le plus de portions restantes

---

## Règles Métier Fondamentales

### 1. Portions Utilisateurs (Immuables)

**Règle:** Les portions déclarées par utilisateur **ne changent JAMAIS**.

```
Exemple:
- Bob déclare: "Je veux 2 portions de Lasagnes (1 midi, 1 soir)"
- Résultat: À CHAQUE occurrence de Lasagnes, Bob reçoit exactement 2 portions
- Aucune dilution, aucun recalcul
```

**Conséquence:**
- Les portions sont **déclaratives**, pas **calculées**
- Un utilisateur peut avoir 0 portions d'une recette (pas d'intérêt pour ce plat)
- Les portions sont séparées par type de repas (lunch/dinner)

### 2. Multiplication de Recette (Batch Cooking)

**Règle:** Si les portions totales nécessaires dépassent les portions de la recette, on multiplie la recette.

```
Formule:
recipeMultiplier = ceil(totalServings / recipe.servings)

Exemple 1:
- Recette: Lasagnes (4 portions)
- Besoins: Alice (2) + Bob (2) = 4 portions
- Résultat: x1 (on cuisine 1 fois, 4 portions)

Exemple 2:
- Recette: Lasagnes (4 portions)
- Besoins: Alice (2) + Bob (2) + Charlie (1) = 5 portions
- Résultat: x2 (on cuisine 2 fois, 8 portions, 3 restes)
```

**Note:** Les restes sont acceptés. On préfère cuisiner plus que moins.

### 3. Cook Once, Eat Twice (addExtraMeal)

**Règle:** Une recette avec `addExtraMeal: true` génère automatiquement un "leftover" le lendemain **au même type de repas**.

```
Exemple:
- Jour 1, MIDI: Bœuf mijoté (addExtraMeal: true)
  → On cuisine x2 quantité
- Jour 2, MIDI: Bœuf mijoté (leftover)
  → Même repas, mêmes utilisateurs, mêmes portions
  → Aucune cuisine supplémentaire

Si c'était au SOIR du Jour 1:
- Jour 1, SOIR: Bœuf mijoté
- Jour 2, SOIR: Bœuf mijoté (leftover)
```

**Caractéristiques des leftovers:**
- ✅ Même type de repas (lunch → lunch, dinner → dinner)
- ✅ Jour suivant (i+2 dans le tableau)
- ✅ Mêmes utilisateurs avec mêmes portions
- ✅ Même `recipeMultiplier` (déjà x2)
- ✅ Marqué comme `isLeftoverMeal: true`
- ❌ Ne consomment PAS de portions supplémentaires
- ❌ Ne comptent PAS comme réutilisation dans le cycle

**Cas particulier addExtraMeal:**
```
Avec 10 recettes et 20 repas:
- Sans addExtraMeal: besoin de réutiliser certaines recettes
- Avec 3 addExtraMeal: 3 recettes couvrent 6 slots
  → Seulement 14 slots restants pour 10 recettes
  → Réutilisation minimale
```

### 4. Cycle de Réutilisation

**Règle:** Une recette ne peut être réutilisée qu'après avoir utilisé TOUTES les recettes au moins une fois.

**Activation du cycle:**
```dart
final requireFullCycle = numMeals > recipes.length;
```

**Cas 1 - Cycle ACTIF** (`numMeals > recipes.length`):
```
Contexte:
- 80 repas (40 jours)
- 10 recettes disponibles

Comportement:
- Cycle 1: Utilise les 10 recettes une première fois
- Reset du cycle
- Cycle 2: Peut réutiliser les 10 recettes
- Et ainsi de suite...

Garantie: Une recette ne peut apparaître 2 fois avant que toutes les autres n'aient été utilisées.
```

**Cas 2 - Cycle INACTIF** (`numMeals ≤ recipes.length`):
```
Contexte:
- 10 repas (5 jours)
- 20 recettes disponibles

Comportement:
- Pas de contrainte de cycle
- Le scoring normal (diversité, similarité) suffit
- Chaque recette peut être utilisée 0 ou 1 fois
```

**Exception - Leftovers:**
Les leftovers (`addExtraMeal`) ne comptent pas dans le cycle car ce n'est pas un nouveau choix de recette.

### 5. Épuisement des Portions

**Règle:** Quand toutes les portions d'un type de repas sont épuisées, l'algorithme continue en se basant sur les préférences déclarées.

```
Phase 1 - Portions disponibles:
- Seules les recettes avec portions restantes sont considérées
- Le scoring favorise la couverture des portions

Phase 2 - Portions épuisées:
- Toutes les recettes redeviennent disponibles
- Le scoring se base sur les préférences (lunch/dinner)
- La diversité et similarité continuent de s'appliquer
```

**Détection:**
```dart
final allPortionsExhausted = remainingPortions.values
    .every((map) => (map[mealType] ?? 0) == 0);
```

**Exemple:**
```
Jour 1-10: Alice et Bob ont des portions
→ Algorithme suit les portions déclarées

Jour 11+: Toutes les portions épuisées
→ Algorithme utilise les préférences (lunch=1, dinner=1)
→ Continue de varier les recettes
```

---

## Système de Scoring

L'algorithme sélectionne la meilleure recette pour chaque repas via un score composite. **Score le plus BAS = meilleur choix**.

### Composantes du Score

#### 1. Coverage Component (Bonus - valeur négative)

**Objectif:** Favoriser les recettes qui couvrent les besoins des utilisateurs.

```
Formula:
coverageScore = Σ(served × (1.0 + equityWeight))
equityWeight = userTotalRemaining / maxUserRemaining

normalizedCoverage = (coverageScore / (totalRemaining × 2.0)).clamp(0.0, 1.0)
coverageComponent = -normalizedCoverage × coverageBonusWeight (défaut: 2)
```

**Exemple:**
```
Context:
- Alice: 50 portions restantes
- Bob: 10 portions restantes
- Recette candidate: peut servir Alice (1) et Bob (1)

Calcul:
- Alice equityWeight: 50/50 = 1.0 → served = 1 × 2.0 = 2.0
- Bob equityWeight: 10/50 = 0.2 → served = 1 × 1.2 = 1.2
- coverageScore = 2.0 + 1.2 = 3.2

→ Alice est "plus prioritaire" car elle a plus de portions en attente
→ Cette recette a un bon coverage score
```

**Mode portions épuisées:**
```dart
if (allPortionsExhausted) {
  coverageScore += desired.toDouble();
}
```
Simplement la somme des portions désirées (pas d'equity).

#### 2. Usage Penalty (Pénalité)

**Objectif:** Pénaliser les recettes déjà beaucoup utilisées.

```
Formula:
timesUsed = usedRecipes[recipe.id] ?? 0
maxTimesUsed = max(usedRecipes.values)

normalizedUsage = (timesUsed / maxTimesUsed).clamp(0.0, 1.0)
usageComponent = normalizedUsage × usagePenaltyWeight (défaut: 20)
```

**Exemple:**
```
Recette A: utilisée 5 fois
Recette B: utilisée 2 fois
maxTimesUsed: 5

Score Recette A: (5/5) × 20 = 20
Score Recette B: (2/5) × 20 = 8

→ Recette B est moins pénalisée (score plus bas = mieux)
```

**Note importante:** Les leftovers ne sont PAS comptés dans `usedRecipes`.

#### 3. Recency Penalty (Pénalité)

**Objectif:** Éviter de répéter une recette trop rapidement.

```
Formula:
normalizedRecency = recentRecipes.contains(recipe.id) ? 1.0 : 0.0
recencyComponent = normalizedRecency × recencyPenaltyWeight (défaut: 100)

Fenêtre glissante: 5 dernières recettes
```

**Exemple:**
```
recentRecipes = ['lasagnes', 'poulet', 'pâtes', 'soupe', 'salade']

Recette candidate: 'poulet'
→ recencyComponent = 1.0 × 100 = 100 (FORTE pénalité)

Recette candidate: 'bœuf'
→ recencyComponent = 0.0 × 100 = 0 (aucune pénalité)
```

**Note:** Les leftovers SONT ajoutés à `recentRecipes` pour éviter:
```
✗ Mauvais:
Jour 1 midi: Lasagnes
Jour 2 midi: Lasagnes (leftover)
Jour 2 soir: Lasagnes (nouveau choix) ← Trop répétitif!

✓ Bon:
Jour 1 midi: Lasagnes
Jour 2 midi: Lasagnes (leftover)
Jour 2 soir: Autre recette (lasagnes dans recentRecipes)
```

#### 4. Similarity Penalty (Pénalité)

**Objectif:** Éviter les recettes avec ingrédients similaires aux recettes récentes.

```
Formula:
Pour chaque recette récente:
  similarity = Jaccard(ingredients_recette, ingredients_recente)
  recencyWeight = 0.2 + (0.8 × position / longueur)
  weightedSimilarity += similarity × recencyWeight

normalizedSimilarity = (weightedSimilarity / totalWeight).clamp(0.0, 1.0)
similarityComponent = normalizedSimilarity × similarityPenaltyWeight (défaut: 30)
```

**Calcul de similarité (Jaccard):**
```
Recette A: {poulet, riz, curry, lait de coco}
Recette B: {poulet, pâtes, tomate, parmesan}

Ingrédients communs exclus: {sel, poivre, huile, eau}

intersection = {poulet} = 1
union = {poulet, riz, curry, lait de coco, pâtes, tomate, parmesan} = 7

Jaccard = 1/7 ≈ 0.14 (faible similarité)
```

**Temporal Decay:**
```
recentRecipes = ['recette1', 'recette2', 'recette3', 'recette4', 'recette5']
positions:         0          1          2          3          4

Poids (recencyWeight):
- recette1 (la plus ancienne): 0.2 + 0.8 × (1/5) = 0.36
- recette2: 0.2 + 0.8 × (2/5) = 0.52
- recette3: 0.2 + 0.8 × (3/5) = 0.68
- recette4: 0.2 + 0.8 × (4/5) = 0.84
- recette5 (la plus récente): 0.2 + 0.8 × (5/5) = 1.0

→ Les recettes les plus récentes ont plus d'influence
```

**Exemple complet:**
```
Candidate: Poulet au curry
recentRecipes: ['Lasagnes', 'Pâtes carbonara', 'Bœuf mijoté']

Similarités:
- Poulet/Lasagnes: 0.0 (aucun ingrédient commun)
- Poulet/Pâtes: 0.0 (aucun ingrédient commun)
- Poulet/Bœuf: 0.2 (légumes en commun)

Calcul:
- weightedSimilarity = 0.0×0.53 + 0.0×0.73 + 0.2×1.0 = 0.2
- totalWeight = 0.53 + 0.73 + 1.0 = 2.26
- normalizedSimilarity = 0.2 / 2.26 = 0.088
- similarityComponent = 0.088 × 30 = 2.64
```

#### 5. AddExtraMeal Bonus (Bonus - valeur négative)

**Objectif:** Favoriser les recettes avec `addExtraMeal` car elles réduisent le nombre de cuisines.

```
Formula:
addExtraMealComponent = recipe.addExtraMeal && normalizedCoverage > 0
    ? -normalizedCoverage × 30.0
    : 0.0
```

**Rationale:**
- Coefficient 30 → comparable à similarity (30) et usage (20)
- Proportionnel au coverage → plus la recette couvre de besoins, plus le bonus est important
- Seulement si coverage > 0 → pas de bonus si la recette ne sert personne

**Exemple:**
```
Recette A: Bœuf mijoté (addExtraMeal: true, coverage: 0.8)
→ addExtraMealComponent = -0.8 × 30 = -24

Recette B: Pâtes (addExtraMeal: false, coverage: 0.8)
→ addExtraMealComponent = 0

→ Recette A a un bonus de -24 points (score plus bas = mieux)
→ Elle sera favorisée car elle réduit le travail de cuisine
```

### Score Total

```
totalScore = usageComponent + recencyComponent + similarityComponent 
           + coverageComponent + addExtraMealComponent

Règle: Score le plus BAS gagne
```

**Exemple complet:**
```
Recette: Poulet au curry (addExtraMeal: true)
Context: Utilisée 2 fois, dans recentRecipes, similarité 0.3, coverage 0.7

Calcul:
1. usage: (2/5) × 20 = 8
2. recency: 1.0 × 100 = 100
3. similarity: 0.3 × 30 = 9
4. coverage: -0.7 × 2 = -1.4
5. addExtraMeal: -0.7 × 30 = -21

totalScore = 8 + 100 + 9 - 1.4 - 21 = 94.6

Cette recette est pénalisée par la recency (100), mais le bonus addExtraMeal (-21)
compense partiellement.
```

---

## Flux d'Exécution Détaillé

### Phase 1: Initialisation

```dart
1. Validation des entrées
   - recipes non vide
   - users non vide

2. Calcul du nombre de repas
   numMeals = durationDays × 2 (lunch + dinner)

3. Création des structures de données
   - meals: List<Meal?> pré-allouée (slots vides)
   - pendingLeftovers: Map<int, Meal> (réservations futures)
   - remainingPortions: Map<userId, Map<MealType, int>>
   - usedRecipes: Map<recipeId, count>
   - recentRecipes: List<recipeId> (fenêtre glissante)
   - usedInCurrentCycle: Set<recipeId>

4. Activation du cycle
   requireFullCycle = numMeals > recipes.length

5. Cache de similarité
   Précalcul de la similarité Jaccard entre toutes les paires de recettes
```

### Phase 2: Boucle Principale (pour chaque repas)

```dart
for (int i = 0; i < numMeals; i++) {
  // Étape 1: Vérifier si slot réservé
  if (pendingLeftovers.containsKey(i)) {
    → Placer le leftover
    → Ajouter à recentRecipes
    → Continue (pas de nouvelle sélection)
  }

  // Étape 2: Calculer date et type
  mealDate = startDate + (i ~/ 2) jours
  mealType = i % 2 == 0 ? lunch : dinner

  // Étape 3: Détecter épuisement
  allPortionsExhausted = tous les users ont 0 portions pour ce mealType

  // Étape 4: Sélectionner meilleure recette
  selectedRecipe = _selectBestRecipe(...)

  // Étape 5: Calculer portions
  (userServingsForMeal, totalConsumed) = _calculateUserServings(...)

  // Étape 6: Calculer multiplicateur
  requiredServings = totalConsumed × (addExtraMeal ? 2 : 1)
  recipeMultiplier = ceil(requiredServings / recipe.servings)

  // Étape 7: Créer le repas
  meal = Meal(...)
  meals[i] = meal

  // Étape 8: Tracker usage et cycle
  usedRecipes[recipe]++
  recentRecipes.add(recipe)
  if (requireFullCycle) {
    usedInCurrentCycle.add(recipe)
    if (usedInCurrentCycle.length == recipes.length) {
      usedInCurrentCycle.clear() // Reset du cycle
    }
  }

  // Étape 9: Gérer addExtraMeal
  if (recipe.addExtraMeal && i+2 < numMeals) {
    pendingLeftovers[i+2] = Meal(isLeftoverMeal: true, ...)
  }
}
```

### Phase 3: Finalisation

```dart
return MealPlan(
  meals: meals.whereType<Meal>().toList(), // Retirer les nulls
  ...
)
```

---

## Algorithme de Sélection (_selectBestRecipe)

### Étape 1: Filtrage par Cycle

```dart
candidateRecipes = availableRecipes

if (requireFullCycle && usedInCurrentCycle.isNotEmpty) {
  unusedRecipes = recettes non utilisées dans le cycle actuel
  
  if (unusedRecipes.isNotEmpty) {
    candidateRecipes = unusedRecipes
  } else {
    // Cycle complet, toutes les recettes sont candidates
    candidateRecipes = availableRecipes
  }
}
```

**Exemple:**
```
Cycle 1:
- usedInCurrentCycle = {A, B, C}
- availableRecipes = {A, B, C, D, E}
- candidateRecipes = {D, E} (uniquement les non utilisées)

Cycle complet:
- usedInCurrentCycle = {A, B, C, D, E}
- Reset automatique → usedInCurrentCycle = {}
- candidateRecipes = {A, B, C, D, E} (toutes)
```

### Étape 2: Scoring de Chaque Candidate

Pour chaque recette dans `candidateRecipes`:

1. Calculer `coverageScore` (équité entre users)
2. Normaliser chaque composante (0-1)
3. Appliquer les poids
4. Sommer toutes les composantes

```dart
for (recipe in candidateRecipes) {
  coverageScore = calcul avec equity
  normalizedCoverage = ...
  normalizedUsage = ...
  normalizedRecency = ...
  normalizedSimilarity = ...
  
  coverageComponent = -normalizedCoverage × 2
  usageComponent = normalizedUsage × 20
  recencyComponent = normalizedRecency × 100
  similarityComponent = normalizedSimilarity × 30
  addExtraMealComponent = recipe.addExtraMeal ? -normalizedCoverage × 30 : 0
  
  totalScore = sum of all components
  
  if (totalScore < bestScore) {
    bestScore = totalScore
    bestRecipe = recipe
  }
}
```

### Étape 3: Retour du Meilleur Choix

```dart
return bestRecipe // Peut être null si aucune recette valide
```

---

## Cas Particuliers et Comportements

### Cas 1: Pas assez de recettes pour tous les users

```
Contexte:
- 2 users: Alice et Bob
- Recette: Poulet (lunch=1 Alice, dinner=0 Alice, lunch=0 Bob, dinner=1 Bob)
- Repas actuel: LUNCH

Résultat:
- Alice: 1 portion
- Bob: 0 portions (n'a pas déclaré d'intérêt pour lunch)
- totalConsumed = 1
- La recette est quand même utilisée
```

### Cas 2: AddExtraMeal en fin de planning

```
Contexte:
- Jour 40 (dernier jour), DINNER
- Recette avec addExtraMeal: true
- i+2 > numMeals (dépasse le planning)

Résultat:
- Le leftover n'est PAS créé (condition: i+2 < numMeals)
- Aucun pendingLeftover réservé
- Pas d'erreur, comportement normal
```

### Cas 3: Toutes les recettes ont le même score

```
Comportement:
- La première recette dans l'ordre de la liste est choisie
- C'est l'ordre d'insertion dans availableRecipes

→ Peu probable en pratique (scores très différenciés)
```

### Cas 4: Recette sans utilisateurs intéressés

```
Contexte:
- Recette: Sushi
- Alice: lunch=0, dinner=0
- Bob: lunch=0, dinner=0

Résultat:
- coverageScore = 0
- normalizedCoverage = 0
- Recette très mal notée (pas de bonus coverage)
- Ne sera jamais sélectionnée (sauf si c'est la seule option)
```

### Cas 5: Sur-planification avec addExtraMeal

```
Contexte:
- Alice: 2 portions totales de Bœuf mijoté
- Bob: 2 portions totales de Bœuf mijoté
- Total portions: 4

Planning généré:
- Jour 1 LUNCH: Bœuf mijoté (Alice: 1, Bob: 1) → consomme 2 portions
- Jour 2 LUNCH: Bœuf mijoté leftover (Alice: 1, Bob: 1) → NE consomme PAS
- Jour 3 LUNCH: Bœuf mijoté (Alice: 1, Bob: 1) → consomme 2 portions restantes
- Jour 4 LUNCH: Bœuf mijoté leftover (Alice: 1, Bob: 1) → NE consomme PAS

Total servi: 4 repas (8 portions servies)
Total portions disponibles: 4 (déclarées initialement)

→ "Sur-planification" de 4 portions
→ C'est INTENTIONNEL (les leftovers sont "gratuits")
```

---

## Exemples Complets

### Exemple 1: Petit Planning (5 jours, 10 recettes)

```
Entrées:
- 10 recettes disponibles
- 2 users (Alice, Bob)
- 5 jours (10 repas)
- Chaque user: 2 portions par recette (1 lunch, 1 dinner)

Comportement:
- requireFullCycle = false (10 repas ≤ 10 recettes)
- Pas de contrainte de cycle
- Scoring normal (diversité, similarité)

Résultat possible:
Jour 1: Lunch=Recette1, Dinner=Recette2
Jour 2: Lunch=Recette3, Dinner=Recette4
Jour 3: Lunch=Recette5, Dinner=Recette6
Jour 4: Lunch=Recette7, Dinner=Recette8
Jour 5: Lunch=Recette9, Dinner=Recette10

→ Aucune réutilisation
→ Maximum de variété
```

### Exemple 2: Planning Long (40 jours, 10 recettes)

```
Entrées:
- 10 recettes disponibles (3 avec addExtraMeal)
- 2 users (Alice, Bob)
- 40 jours (80 repas)
- Chaque user: 2 portions par recette

Comportement:
- requireFullCycle = true (80 repas > 10 recettes)
- Cycle obligatoire

Cycles attendus:
Cycle 1 (repas 1-20):
- 10 recettes utilisées
- 3 addExtraMeal créent 3 leftovers
- Total: 13 repas couverts (10 + 3)
- Reset du cycle

Cycle 2 (repas 21-40):
- Réutilisation des 10 recettes
- 3 addExtraMeal créent 3 leftovers
- Total: 13 repas couverts
- Reset du cycle

Cycle 3-6: Idem

→ Total: environ 6 cycles × 13 repas = 78 repas
→ Portions épuisées vers repas 20-30
→ Mode "preferences" activé pour le reste
```

### Exemple 3: AddExtraMeal en Action

```
Entrées:
- Recette: Bœuf mijoté (servings=6, addExtraMeal=true)
- Users: Alice (lunch=1), Bob (lunch=1), Charlie (lunch=1)
- Jour 5, LUNCH

Exécution:
1. Sélection: Bœuf mijoté
2. Calcul portions:
   - Alice: 1, Bob: 1, Charlie: 1
   - totalConsumed = 3
3. Calcul multiplicateur:
   - requiredServings = 3 × 2 = 6 (addExtraMeal!)
   - recipeMultiplier = ceil(6/6) = 1
4. Création repas principal:
   - Jour 5, LUNCH: Bœuf (Alice: 1, Bob: 1, Charlie: 1)
   - totalServings = 3
   - recipeMultiplier = 1
5. Création leftover:
   - pendingLeftovers[12] = Meal(
       date: Jour 6,
       type: LUNCH,
       userServings: {Alice: 1, Bob: 1, Charlie: 1},
       isLeftoverMeal: true
     )

Résultat planning:
Jour 5 LUNCH: Bœuf mijoté (cuisson x1, 3 portions consommées)
Jour 6 LUNCH: Bœuf mijoté leftover (pas de cuisson, 3 portions servies)

Portions consommées: 3 (seulement le premier repas)
Portions servies: 6 (les deux repas)
```

### Exemple 4: Épuisement et Réutilisation

```
Entrées:
- 5 recettes
- Alice: 1 portion lunch par recette (5 total lunch)
- 20 jours (40 repas = 20 lunch + 20 dinner)

Phase 1 (Lunch 1-5): Portions disponibles
- Utilise Recettes A, B, C, D, E
- Consomme les 5 portions lunch d'Alice

Phase 2 (Lunch 6-20): Portions épuisées
- allPortionsExhausted = true
- Réutilise les recettes selon preferences (Alice lunch=1)
- Cycle: A, B, C, D, E, A, B, C, D, E, A, B, C, D, E

Résultat:
- Recette A utilisée 3 fois
- Recette B utilisée 3 fois
- etc.
- Diversité maintenue (pas 15x la même recette)
```

---

## Points d'Attention et Limites

### 1. Sur-planification avec AddExtraMeal

**Comportement:** Les leftovers ne consomment pas de portions déclarées.

**Conséquence:** Vous pouvez servir plus de repas que de portions initiales.

**Exemple:**
```
Portions déclarées: 10
Repas addExtraMeal: 5 (génèrent 5 leftovers)
Total repas servis: 15

→ C'est intentionnel
→ Modèle déclaratif: "je veux cuisiner X fois", pas "j'ai X portions"
```

### 2. Leftovers dans recentRecipes

**Comportement:** Les leftovers sont ajoutés à `recentRecipes` mais pas à `usedRecipes`.

**Raison:** Éviter la répétition d'ingrédients similaires juste après un leftover.

**Exemple:**
```
Jour 1 LUNCH: Lasagnes (viande, tomate, pâtes)
Jour 2 LUNCH: Lasagnes leftover
→ Lasagnes dans recentRecipes
→ Jour 2 DINNER: Pâtes carbonara (pâtes communes) sera pénalisé

→ Bon design pour la diversité
```

### 3. usedRecipes Jamais Décrémenté

**Comportement:** Le compteur `usedRecipes` ne fait que monter.

**Conséquence:** Pas de différence entre "utilisé dans le cycle actuel" et "utilisé globalement".

**Justification:**
- C'est un signal relatif (normalisé)
- Il guide la distribution équitable
- Ce n'est pas un compteur absolu

### 4. Scoring Non Déterministe (faible probabilité)

**Cas:** Si deux recettes ont exactement le même score.

**Comportement:** La première dans l'ordre de la liste est choisie.

**Probabilité:** Très faible en pratique (5 composantes avec poids différents).

### 5. Recettes Sans Intérêt

**Cas:** Aucun utilisateur n'a déclaré de portions pour une recette.

**Comportement:** Cette recette ne sera jamais sélectionnée (coverageScore = 0).

**Solution:** S'assurer que chaque recette a au moins 1 utilisateur intéressé.

---

## Optimisations et Performance

### 1. Cache de Similarité

**Technique:** Précalcul de toutes les paires de recettes au démarrage.

```dart
similarityCache = _buildSimilarityCache(recipes)
// O(n²) au démarrage, O(1) par lookup
```

**Gain:** Évite de recalculer Jaccard à chaque itération.

### 2. Pré-allocation des Slots

**Technique:** `List<Meal?>.filled(numMeals, null)`

**Gain:** Pas de redimensionnement dynamique, accès direct par index.

### 3. Pendantsalut Leftovers

**Technique:** Réservation via Map plutôt que liste temporaire.

```dart
pendingLeftovers[i+2] = meal
// Insertion future O(1)
```

### 4. Normalisation des Scores

**Technique:** Tous les scores normalisés en 0-1 avant application des poids.

**Avantage:** Équilibrage correct entre composantes, pas de domination d'une métrique.

---

## Poids par Défaut et Tuning

```dart
usagePenaltyWeight: 20.0      // Impact modéré
recencyPenaltyWeight: 100.0   // Impact FORT (éviter répétitions rapides)
similarityPenaltyWeight: 30.0 // Impact modéré
coverageBonusWeight: 2.0      // Impact faible (mais c'est un bonus)
addExtraMealBonus: 30.0       // Impact modéré (hardcodé)
```

**Recommandations de tuning:**
- **Augmenter recencyPenaltyWeight** → Plus d'espace entre répétitions
- **Augmenter similarityPenaltyWeight** → Plus de diversité d'ingrédients
- **Augmenter usagePenaltyWeight** → Distribution plus équitable entre recettes
- **Augmenter coverageBonusWeight** → Plus de priorité aux portions restantes

---

## Résumé Visuel du Flux

```
┌─────────────────────────────────────────────────────────────┐
│ INITIALISATION                                              │
│ • Valider entrées                                           │
│ • Créer structures de données                               │
│ • Calculer cache similarité                                 │
│ • Déterminer requireFullCycle                               │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ BOUCLE PRINCIPALE (pour chaque repas i)                     │
│                                                             │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 1. Slot réservé ? (pendingLeftovers)             │     │
│  │    OUI → Placer leftover et continue             │     │
│  │    NON → Continuer                                │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 2. Calculer date et type (lunch/dinner)          │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 3. Détecter épuisement portions                   │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 4. Sélectionner meilleure recette                │     │
│  │    • Filtrer par cycle (si actif)                │     │
│  │    • Scorer chaque candidate                      │     │
│  │    • Choisir score minimal                        │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 5. Calculer portions users                        │     │
│  │    • Mode normal ou ignorePortions                │     │
│  │    • Consommer portions (si applicable)           │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 6. Calculer multiplicateur de recette            │     │
│  │    • x2 si addExtraMeal                           │     │
│  │    • ceil(required / servings)                    │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 7. Créer et placer le repas                      │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 8. Tracker usage et cycle                        │     │
│  │    • usedRecipes++                                │     │
│  │    • recentRecipes.add()                          │     │
│  │    • usedInCurrentCycle.add() (si cycle actif)   │     │
│  │    • Reset cycle si complet                       │     │
│  └──────────────────────────────────────────────────┘     │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────┐     │
│  │ 9. Gérer addExtraMeal                            │     │
│  │    • Si true et i+2 valide                        │     │
│  │    • Réserver pendingLeftovers[i+2]              │     │
│  └──────────────────────────────────────────────────┘     │
│                                                             │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ FINALISATION                                                │
│ • Filtrer nulls                                             │
│ • Retourner MealPlan                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Glossaire

**addExtraMeal**: Attribut booléen d'une recette. Si true, cuisiner cette recette génère automatiquement un leftover le lendemain au même type de repas.

**Batch Cooking**: Technique consistant à cuisiner plusieurs fois une recette si les portions nécessaires dépassent les portions de la recette.

**Coverage**: Mesure de combien de besoins utilisateurs une recette peut satisfaire.

**Cycle**: Période pendant laquelle toutes les recettes doivent être utilisées au moins une fois avant qu'une puisse être réutilisée.

**Equity Weight**: Poids donnant priorité aux utilisateurs ayant le plus de portions restantes.

**Jaccard Similarity**: Mesure de similarité entre deux ensembles. `|A ∩ B| / |A ∪ B|`

**Leftover**: Repas planifié automatiquement suite à un `addExtraMeal`, ne nécessitant pas de nouvelle cuisine.

**MealType**: Type de repas (`lunch` ou `dinner`).

**Normalized Score**: Score ramené dans l'intervalle [0, 1] pour équilibrage.

**pendingLeftovers**: Map réservant des slots futurs pour les leftovers.

**recentRecipes**: Fenêtre glissante des 5 dernières recettes pour éviter répétitions rapides.

**recipeMultiplier**: Nombre de fois qu'une recette doit être cuisinée pour satisfaire les besoins.

**remainingPortions**: Map trackant les portions encore disponibles par utilisateur et type de repas.

**requireFullCycle**: Booléen activant la contrainte de cycle complet (true si `numMeals > recipes.length`).

**Temporal Decay**: Poids croissant donné aux éléments plus récents dans un historique.

**usedInCurrentCycle**: Set des recettes déjà utilisées dans le cycle actuel.

**usedRecipes**: Map comptant le nombre total d'utilisations de chaque recette.

---

## Conclusion

Cet algorithme implémente un système de planification de repas sophistiqué qui:

✅ **Respecte scrupuleusement les portions utilisateurs** (modèle déclaratif)  
✅ **Optimise la cuisine** via `addExtraMeal` (cook once, eat twice)  
✅ **Maximise la diversité** via scoring multi-critères avec pénalités de similarité  
✅ **Garantit l'équité** en priorisant les utilisateurs avec plus de besoins restants  
✅ **Évite les répétitions** via fenêtre glissante et cycle complet  
✅ **S'adapte automatiquement** aux contraintes (portions épuisées, peu de recettes, etc.)

Le code est optimisé, documenté, et chaque règle métier est explicitement implémentée sans ambiguïté.
