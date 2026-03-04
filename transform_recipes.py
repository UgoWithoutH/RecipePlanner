"""
Script de transformation des fichiers de cache de recettes.
- Ajoute le type (4ème élément) à chaque ingrédient
- Remplace 'cat':'X' par 'cats':['X','Y'] (multi-catégories)
Types officiels : Viande, Légume, Féculent, Poisson, Produit laitier, Condiment, Fruit, Oeuf, Herbe, Autre
Catégories officielles : Viande, Végétarien, Pâtes, Asiatique, Poisson, Salade, Sandwich, Boisson, Petit-déjeuner
+ Nouvelles : Soupe, Dessert, Plat mijoté
"""

import re, os

BASE = r'c:\Users\E082903\Desktop\RecipePlanner\lib\data\services'

# ── CLASSIFICATION DES INGRÉDIENTS ─────────────────────────────────────────

def classify(name: str) -> str:
    n = name.lower() + ' '  # padding so 'oignon ' matches both 'oignon sauce' and 'oignon'

    # Oeuf (avant Viande — attention: 'oeuf' est dans 'boeuf' → word boundary)
    oeuf_kw = ["jaune d'oeuf","blanc d'oeuf",
               "jaunes d'oeuf","blancs d'oeuf","dorure"]
    for kw in oeuf_kw:
        if kw in n:
            return 'Oeuf'
    if re.search(r'\boeuf[sx]?\b', n):
        return 'Oeuf'

    # Viande
    viande_kw = [
        'boeuf', 'veau', 'porc', 'agneau', 'mouton', 'poulet', 'coq ou',
        'coq,', 'coq ', 'canard', 'dinde', 'pintade', 'lapin', 'lievre',
        'lièvre', 'autruche', 'cerf', 'sanglier',
        'lardons', 'bacon', 'jambon', 'saucisse', 'saucisson', 'merguez',
        'andouillette', 'andouille', 'magret', 'foie gras',
        'confit de canard', 'confit de',
        'poitrine fumée', 'poitrine de porc', 'saindoux',
        'plat-de-côtes', 'os à moelle', 'jarret de', 'palette de porc',
        'côte de porc', 'côte de boeuf', 'côtes courtes',
        'escalope de', 'filet de boeuf', 'filet mignon',
        'gîte', 'paupiette',
        'travers de porc', 'chair à saucisse', 'farce porc',
        'gésier', 'foies de volaille', 'foie de volaille',
        'aiguillettes de', 'blancs de poulet', 'morceaux de poulet',
        'cuisses de poulet', 'ailes de poulet', 'ailes et cuisses',
        "épaule d'agneau", 'gigot', 'tournedos',
        'rôti de porc', 'terrine de', 'rillettes',
        'côtelette', 'entrecôte',
    ]
    for kw in viande_kw:
        if kw in n:
            return 'Viande'

    # Poisson / fruits de mer
    poisson_kw = [
        'saumon', 'cabillaud', 'sole ', 'thon ', 'morue', 'sardine',
        'daurade', 'dorade', 'merlan', 'turbot', ' bar ', 'truite',
        'maquereau', 'hareng', 'lieu ', 'rouget', 'colin ', 'haddock',
        'anchois', 'thiof',
        'crevette', 'gambas', 'scampi', 'langoustine',
        'moules', 'palourde', 'coques', 'bulots',
        'calmar', 'seiche', 'poulpe',
        'saint-jacques', 'coquilles saint',
        'homard', 'crabe', 'langouste', 'oursin',
        'poissons variés', 'poissons de roche', 'filets de poisson',
        'encre de seiche',
    ]
    for kw in poisson_kw:
        if kw in n:
            return 'Poisson'

    # Produit laitier  (AVANT Féculent pour beurre/crème)
    # Note: 'lait de coco' est Condiment → traité plus bas
    laitier_kw = [
        "lait d'amande", "lait d'avoine", "lait de soja",
        'lait tiède', 'lait chaud', 'lait froid', 'lait entier',
        'lait ', 'lait,',  # lait de coco exclu (voir Condiment)
        'crème fraîche', 'crème liquide', 'crème épaisse', 'crème chantilly',
        'crème ', 'cremen',
        'beurre fondu', 'beurre mou', 'beurre nantais', 'beurre froid',
        'beurre ', 'beurre,', 'beurre.',
        'parmesan', 'pecorino', 'gruyère', 'emmental', 'comté', 'roquefort',
        'mozzarella', 'ricotta', 'mascarpone', 'cream cheese', 'cheddar',
        'gorgonzola', 'fromage de chèvre', 'chèvre', 'brie ',
        'camembert', 'raclette ', 'fromage fondu', 'fromage blanc',
        'fromage frais', 'fromage ', 'feta',
        'yaourt', 'yogurt', 'ghee', 'paneer', 'burrata',
    ]
    # 'lait de coco' and 'crème de coco' are Condiment — check before laitier
    if 'lait de coco' in n or 'crème de coco' in n:
        return 'Condiment'
    for kw in laitier_kw:
        if kw in n:
            return 'Produit laitier'

    # Herbe et épice
    herbe_kw = [
        'basilic', 'persil plat', 'persil ', 'persil,',
        'thym', 'romarin', 'estragon', 'ciboulette',
        'menthe ', 'menthe,', 'aneth', 'origan',
        'coriandre', 'sauge', 'laurier',
        'herbes de provence', 'herbes fraîches', 'fines herbes',
        'cumin', 'curry', 'curcuma', 'paprika', 'poivre ', 'poivre,',
        'noix de muscade', 'muscade', 'cannelle', 'safran',
        'piment ', 'piment,', 'piment rouge', 'piment séché',
        'cayenne', 'gingembre', 'galangal', 'citronnelle', 'kaffir',
        'ras-el-hanout', 'quatre-épices', 'cardamome', 'carvi',
        'anis étoilé', 'clou de girofle', 'clous de girofle',
        'tikka masala', 'garam masala', 'cinq épices', 'cinco épices',
        'espelette', 'piment chipotle', 'gochugaru',
        'extrait de vanille', 'vanille ', 'pandan', 'eau de rose',
        'wasabi', 'colorant alimentaire',
        'bouquet garni',
    ]
    for kw in herbe_kw:
        if kw in n:
            return 'Herbe'

    # Féculent
    feculent_kw = [
        'spaghetti', 'tagliatelle', 'penne', 'fusilli', 'macaroni',
        'feuilles de lasagne', 'farfalle', 'bucatini', 'pappardelle',
        'rigatoni', 'linguine', 'orecchiette',
        'gnocchi', 'ramen', 'udon', 'soba',
        'vermicelles de riz', 'vermicelles de soja', 'vermicelles de patate douce',
        'nouilles de riz', 'nouilles épaisses', 'nouilles soba', 'nouilles ',
        'riz arborio', 'riz basmati', 'riz japonais', 'riz gluant', 'riz rond',
        'riz long', 'riz brun', 'riz complet', 'riz cassé', 'riz cuit refroidi',
        'riz cuit', 'riz ', 'riz,',
        'pomme de terre', 'pommes de terre', 'grenaille',
        'farine t00', 'farine t45', 'farine t65', 'farine t80', 'farine t110',
        'farine de seigle', 'farine de sarrasin', 'farine de riz', "farine d'avoine",
        'farine ', 'farine,',
        'chapelure', 'panko',
        'pain de mie', 'pain nordique', 'pain brioché', 'pain blanc', 'pain rassis',
        'pain ', 'baguette', 'ciabatta', 'buns', 'pita', 'naan ',
        'tortilla', 'galette bretonne',
        'boulgour', 'semoule', 'quinoa', 'farro', 'épeautre', 'millet',
        'polenta', 'couscous',
        "flocons d'avoine", 'flocons',
        'maïzena', 'fécule de pomme de terre', 'fécule',
        'crouton', 'croûton', 'chips de tapioca',
        'pâtes petites', 'pâtes ',
    ]
    for kw in feculent_kw:
        if kw in n:
            return 'Féculent'

    # Légume (incluant légumineuses)
    legume_kw = [
        'courgette', 'poivron', 'tomates pelées', 'tomates cerises',
        'tomate ', 'tomates ', 'tomate,', 'tomates,',
        'champignon', 'shiitake', 'pleurote', 'enoki', 'morille', 'cèpe',
        'champignons', 'champignons de paris', 'champignons paille',
        'shiitakes', 'shiitake',
        'ail ', 'ail,', 'oignon ', 'oignon,', 'oignons ', 'oignons,',
        'oignon rouge', 'oignon vert', 'oignons verts', 'oignons rouges',
        'échalote', 'échalotes',
        'poireau', 'carotte', 'carottes', 'céleri', 'aubergine',
        'épinards', 'épinard',
        'fenouil', 'navet', 'betterave',
        'maïs ', 'maïs,',
        'haricot vert', 'haricots verts', 'haricots blancs', 'haricots noirs',
        'haricots rouges', 'haricot',
        'pois chiches', 'pois chiche', 'lentilles', 'lentille',
        'petits pois', 'concombre', 'artichaut', 'radis', 'brocoli',
        'chou-fleur', 'chou blanc', 'chou vert', 'chou chinois', 'chou ',
        'pak choï', 'mâche', 'roquette',
        'laitue', 'mesclun', 'salade verte', 'salade frisée',
        'salade ', 'endive', 'asperge',
        'patate douce', 'courge', 'butternut', 'potimarron',
        'edamame', 'bambou', 'nori', 'algue', 'wakamé', 'spiruline',
        'daikon', 'manioc', 'igname', 'topinambour',
        'papaye verte', 'kimchi',
        'céleri branche',
    ]
    for kw in legume_kw:
        if kw in n:
            return 'Légume'
    if re.search(r'\bail\b', n):
        return 'Légume'

    # Fruit (fruits frais, secs, noix, graines)
    fruit_kw = [
        'pomme ', 'pommes ', 'pomme,', 'poire ', 'cerise ', 'cerises',
        'fraise', 'framboise',
        'abricot', 'pêche ', 'prune ', 'pruneau', 'pruneaux',
        'raisin ', 'raisins', 'figue ', 'figues',
        'mangue', 'ananas', 'orange ', 'oranges', 'citron', 'lime',
        'banane', 'kiwi', 'melon', 'pastèque', 'grenade',
        "fruit de la passion", 'myrtille', 'mûre ', 'groseille',
        'açaï', 'date ', 'noix de coco',
        'noix ', 'noix,', 'amandes', 'amande ', "amandes en poudre",
        'noisette', 'pistache',
        'cacahuète', 'arachide', 'pignon', 'noix de cajou', 'noix de pécan',
        'graines de sésame', 'graines de courge', 'graines de lin',
        'graines de tournesol', 'graines ', 'sésame grillé', 'sésame blanc',
        'sésame noir',
        'raisins secs', 'canneberge', 'airelle', 'cranberry',
        'avocat',
    ]
    if re.search(r'\bnoix\b', n):
        return 'Fruit'
    for kw in fruit_kw:
        if kw in n:
            return 'Fruit'

    # Condiment (sauces, huiles, assaisonnements, bouillons, alcools)
    condiment_kw = [
        "huile d'olive", "huile de sésame", "huile de coco",
        "huile de friture", "huile de noix", "huile de tournesol",
        'huile ', 'vinaigre',
        'ketchup', 'mayonnaise',
        'sauce soja', 'sauce de poisson', 'fish sauce', 'worcestershire',
        'sauce aux huîtres', 'sauce huître', 'oyster sauce', 'hoisin',
        'sauce enchilada', 'sauce bbq', 'sauce teriyaki', 'sauce tonkatsu',
        'sauce gochujang', 'sauce worcestershire',
        'kecap manis', 'sambal', 'sriracha', 'tabasco',
        "bouillon de légumes", "bouillon de poulet", "bouillon de boeuf",
        'bouillon de poisson', 'bouillon de volaille', 'bouillon dashi',
        'bouillon délicat', 'bouillon,', 'bouillon ',
        'fond de veau', 'fond de volaille', "fond d'agneau",
        'cube de bouillon',
        'vin blanc', 'vin rouge', 'vin ', 'cidre ', 'bière',
        'cognac', 'rhum ', 'kirsch', 'marsala', 'mirin ', 'saké',
        'grand marnier', 'cointreau', 'madère', 'calvados',
        "concentré de tomate", "purée de tomate", 'passata',
        'lait de coco', 'crème de coco',
        'miso ', 'pâte miso', 'dashi ', 'nuoc mam', 'nam jim',
        'tahini', 'tamarin', 'pâte de tamarin',
        'sucre ', 'sucre,', 'cassonade', 'sucre glace', 'sucre en poudre',
        'sucre de palme', 'sel de', 'fleur de sel', 'sel ',
        'miel', 'sirop', 'tréacle', 'mélasse',
        'béchamel', 'sauce blanche',
        'olives noires', 'olives vertes', 'olives', 'câpres', 'cornichons',
        "pâte de crevettes", "pâte d'arachide", 'pâte de praliné', 'pralin',
        'citrons confits', 'citron confit', 'eau de rose', 'eau de fleur',
        'moutarde', 'gochujang',
    ]
    for kw in condiment_kw:
        if kw in n:
            return 'Condiment'

    # Tofu et produits végétaux protéinés → Légume
    if 'tofu' in n or 'tempeh' in n:
        return 'Légume'

    # Autre (par défaut)
    autre_kw = [
        'levure', 'gélatine', 'eau gazeuse', 'eau tiède', 'eau froide',
        'eau bouillante', 'eau de cuisson', 'eau ', 'eau,',
        "pâte feuilletée", "pâte brisée", "pâte sablée", "pâte à pizza",
        "pâte à choux", "pâte à gyoza", "pâtes wonton", "galettes de riz",
        'galettes mandarin', 'feuilles brick', 'feuilles de riz', 'phyllo',
        "pâte à won ton", 'wonton', 'galette ', 'galettes',
        'chocolat noir', 'chocolat au lait', 'chocolat blanc', 'chocolat ',
        'cacao', 'fondant blanc',
        'colorant', 'scoby', 'tigrette',
        'crépine', 'krupuk', 'krupuk',
    ]
    for kw in autre_kw:
        if kw in n:
            return 'Autre'

    return 'Autre'


# Test rapide
def test_classify():
    cases = [
        ('spaghetti', 'Féculent'), ('boeuf haché', 'Viande'), ('saumon fumé', 'Poisson'),
        ('oeufs', 'Oeuf'), ('crème fraîche', 'Produit laitier'), ('basilic frais', 'Herbe'),
        ("huile d'olive", 'Condiment'), ('pomme golden', 'Fruit'), ('courgette', 'Légume'),
        ('pâte feuilletée', 'Autre'), ('sel de Guérande', 'Condiment'),
        ('citron vert', 'Fruit'), ('parmesan râpé', 'Produit laitier'),
        ('cumin en poudre', 'Herbe'), ('lait de coco', 'Condiment'),
        ('pois chiches', 'Légume'), ('lentilles corail', 'Légume'),
        ('noix', 'Fruit'), ('oeuf (dorure)', 'Oeuf'), ('levure boulangère', 'Autre'),
        ('beurre fondu', 'Produit laitier'), ('moutarde de Dijon', 'Condiment'),
        ('tofu ferme', 'Légume'), ('bouillon de légumes', 'Condiment'),
        ('lardons', 'Viande'), ('gruyère râpé', 'Produit laitier'),
        ('ail', 'Légume'), ('thym', 'Herbe'), ('riz arborio', 'Féculent'),
    ]
    errors = []
    for name, expected in cases:
        got = classify(name)
        if got != expected:
            errors.append(f'  classify({name!r}) → {got!r}  (attendu: {expected!r})')
    if errors:
        print(f'Tests échoués ({len(errors)}):')
        for e in errors:
            print(e)
    else:
        print(f'✓ Tous les {len(cases)} tests de classify passés.')

test_classify()
print()


# ── CATÉGORIES PAR RECETTE ─────────────────────────────────────────────────

CATS_MAP = {
    # DATA 1 ─ Pâtes
    'Pâtes carbonara': ['Pâtes', 'Viande'],
    'Pâtes bolognaise': ['Pâtes', 'Viande'],
    'Pâtes au pesto': ['Pâtes', 'Végétarien'],
    "Pâtes à l'arrabiata": ['Pâtes', 'Végétarien'],
    'Lasagnes bolognaise': ['Pâtes', 'Viande'],
    'Pâtes aux quatre fromages': ['Pâtes', 'Végétarien'],
    'Pâtes au saumon fumé': ['Pâtes', 'Poisson'],
    'Spaghetti aglio e olio': ['Pâtes', 'Végétarien'],
    "Penne all'amatriciana": ['Pâtes', 'Viande'],
    'Mac and cheese': ['Pâtes', 'Végétarien'],
    'Gnocchi sauce tomate': ['Pâtes', 'Végétarien'],
    'Risotto aux champignons': ['Végétarien'],
    # DATA 1 ─ Viandes
    'Poulet rôti': ['Viande'],
    'Boeuf bourguignon': ['Viande', 'Plat mijoté'],
    'Hachis parmentier': ['Viande'],
    'Escalope milanaise': ['Viande'],
    'Poulet basquaise': ['Viande'],
    'Steak haché maison': ['Viande'],
    'Blanquette de veau': ['Viande', 'Plat mijoté'],
    'Poulet香 au curry et coco': ['Viande'],
    "Côtelettes d'agneau grillées": ['Viande'],
    'Filet de boeuf en croûte': ['Viande'],
    'Paupiettes de veau': ['Viande'],
    'Osso buco': ['Viande'],
    'Aiguillettes de canard sautées': ['Viande'],
    'Gratin dauphinois': ['Végétarien'],
    'Côte de porc moutarde': ['Viande'],
    'Poulet à la normande': ['Viande'],
    'Rôti de porc aux herbes': ['Viande'],
    # DATA 1 ─ Poisson
    'Saumon au four citron-aneth': ['Poisson'],
    'Cabillaud en papillote': ['Poisson'],
    'Brandade de morue': ['Poisson'],
    'Filets de sole meunière': ['Poisson'],
    "Crevettes sautées à l'ail": ['Poisson'],
    'Thon mi-cuit au sésame': ['Poisson'],
    'Bouillabaisse simple': ['Poisson', 'Soupe'],
    'Poke bowl au saumon': ['Poisson', 'Asiatique'],
    # DATA 1 ─ Soupes
    "Soupe à l'oignon gratinée": ['Soupe', 'Végétarien'],
    'Crème de brocoli': ['Soupe', 'Végétarien'],
    'Soupe de tomates rôties': ['Soupe', 'Végétarien'],
    'Minestrone': ['Soupe', 'Végétarien'],
    'Gaspacho': ['Soupe', 'Végétarien'],
    'Velouté de courge butternut': ['Soupe', 'Végétarien'],
    'Soupe lentilles corail': ['Soupe', 'Végétarien'],
    # DATA 1 ─ Végétarien
    'Ratatouille': ['Végétarien'],
    'Quiche lorraine': ['Viande', 'Végétarien'],
    'Tartelette aux légumes grillés': ['Végétarien'],
    'Omelette aux herbes': ['Végétarien'],
    "Tarte à l'oignon": ['Végétarien'],
    'Courgettes farcies': ['Végétarien'],
    'Curry de légumes': ['Végétarien'],
    'Falafels': ['Végétarien'],
    'Shakshuka': ['Végétarien'],
    'Tabboulé libanais': ['Salade', 'Végétarien'],
    # DATA 1 ─ Salades
    'Salade César': ['Salade', 'Viande'],
    'Salade niçoise': ['Salade', 'Poisson'],
    'Salade de quinoa et légumes rôtis': ['Salade', 'Végétarien'],
    'Salade grecque': ['Salade', 'Végétarien'],
    'Salade de chèvre chaud': ['Salade', 'Végétarien'],
    'Salade Waldorf': ['Salade', 'Végétarien'],
    'Bowl Buddha végétarien': ['Végétarien'],
    # DATA 1 ─ Asiatique
    'Riz cantonais': ['Asiatique', 'Végétarien'],
    'Poulet teryaki': ['Asiatique', 'Viande'],
    'Pad thaï': ['Asiatique'],
    'Nasi goreng': ['Asiatique', 'Viande'],
    'Ramen au miso': ['Asiatique', 'Viande'],
    'Gyoza maison': ['Asiatique', 'Viande'],
    'Poulet kung pao': ['Asiatique', 'Viande'],
    'Boeuf sauté au brocoli': ['Asiatique', 'Viande'],
    'Dumplings vapeur (dim sum)': ['Asiatique', 'Viande', 'Poisson'],
    'Tom yum goong': ['Asiatique', 'Poisson', 'Soupe'],
    'Maki et California rolls': ['Asiatique', 'Poisson'],
    # DATA 1 ─ Petit-déjeuner
    'Crêpes sucrées': ['Petit-déjeuner', 'Dessert'],
    'Pancakes moelleux': ['Petit-déjeuner', 'Dessert'],
    'Granola maison': ['Petit-déjeuner'],
    'Français toast': ['Petit-déjeuner'],
    'Avocado toast': ['Petit-déjeuner'],
    'Waffles (gaufres)': ['Petit-déjeuner', 'Dessert'],
    'Bowl açaï': ['Petit-déjeuner'],
    # DATA 1 ─ Sandwiches
    'Burger maison': ['Sandwich', 'Viande'],
    'Club sandwich': ['Sandwich', 'Viande'],
    'Croque monsieur': ['Sandwich', 'Viande'],
    'Wrap au poulet et légumes': ['Sandwich', 'Viande'],
    "Tartines à l'avocat et saumon": ['Sandwich', 'Poisson'],
    'Panini mozzarella-tomate': ['Sandwich', 'Végétarien'],
    # DATA 1 ─ Plats mijotés
    'Pot-au-feu': ['Viande', 'Plat mijoté'],
    'Cassoulet toulousain': ['Viande', 'Plat mijoté'],
    "Tajine d'agneau aux pruneaux": ['Viande', 'Plat mijoté'],
    'Chili con carne': ['Viande', 'Plat mijoté'],
    'Moussaka grecque': ['Viande'],
    'Lentilles vertes du Puy': ['Végétarien', 'Viande'],
    'Magret de canard cerises': ['Viande'],
    # DATA 1 ─ Riz/Céréales
    'Paella valenciana': ['Viande'],
    'Riz pilaf': ['Végétarien'],
    'Risotto aux asperges': ['Végétarien'],
    'Couscous royal': ['Viande'],
    'Dhal de lentilles': ['Végétarien'],
    # DATA 1 ─ Oeufs
    'Oeufs cocotte': ['Végétarien'],
    'Frittata aux légumes': ['Végétarien'],
    'Oeufs brouillés crémeux': ['Petit-déjeuner', 'Végétarien'],
    # DATA 1 ─ Pizza
    'Pizza Margherita': ['Végétarien'],
    'Pizza quatre saisons': ['Viande'],
    'Calzone farcie': ['Végétarien'],
    # DATA 1 ─ Porc
    'Travers de porc BBQ': ['Viande'],
    'Filet mignon de porc à la crème': ['Viande'],
    'Choucroute garnie': ['Viande'],
    'Andouillette sauce moutarde': ['Viande'],
    # DATA 1 ─ Desserts
    'Tarte aux pommes': ['Dessert'],
    'Crème brûlée': ['Dessert'],
    'Mousse au chocolat': ['Dessert'],
    'Fondant au chocolat': ['Dessert'],
    'Tarte au citron meringuée': ['Dessert'],
    'Tiramisu classique': ['Dessert'],
    'Île flottante': ['Dessert'],
    'Clafoutis aux cerises': ['Dessert'],
    'Tarte Tatin': ['Dessert'],
    'Pain perdu': ['Petit-déjeuner', 'Dessert'],
    'Crème caramel': ['Dessert'],
    # DATA 2 ─ Boulangerie/Viennoiserie
    'Pain blanc maison': ['Végétarien'],
    'Brioche moelleuse': ['Petit-déjeuner'],
    'Croissants maison': ['Petit-déjeuner'],
    'Baguette tradition': ['Végétarien'],
    'Pain de campagne au levain': ['Végétarien'],
    'Muffins aux myrtilles': ['Petit-déjeuner', 'Dessert'],
    'Cinnamon rolls': ['Petit-déjeuner', 'Dessert'],
    'Focaccia aux olives': ['Végétarien'],
    # DATA 2 ─ Indien
    'Poulet tikka masala': ['Viande'],
    'Palak paneer': ['Végétarien'],
    'Naan au beurre': ['Végétarien'],
    'Biryani de poulet': ['Viande'],
    'Samossas aux légumes': ['Végétarien'],
    'Raita au concombre': ['Végétarien'],
    # DATA 2 ─ Mexicain
    'Tacos al pastor': ['Viande'],
    'Guacamole': ['Végétarien'],
    'Enchiladas au poulet': ['Viande'],
    'Quesadillas au fromage': ['Végétarien'],
    'Fajitas de poulet': ['Viande'],
    'Pozole rouge': ['Viande', 'Soupe'],
    # DATA 2 ─ Espagnol/Méditerranéen
    'Tortilla española': ['Végétarien'],
    'Ceviche de dorade': ['Poisson'],
    'Gambas al ajillo': ['Poisson'],
    'Paella de mariscos': ['Poisson'],
    'Pisto manchego': ['Végétarien'],
    'Hummus maison': ['Végétarien'],
    'Taboulé moyen-oriental': ['Salade', 'Végétarien'],
    'Moules marinières': ['Poisson'],
    'Brandade de merlan': ['Poisson'],
    'Calamars à la plancha': ['Poisson'],
    # DATA 2 ─ Nord-africain
    'Tajine de poulet aux citrons confits': ['Viande', 'Plat mijoté'],
    'Maquereaux chermoula': ['Poisson'],
    'Pastilla au poulet': ['Viande'],
    'Msemen (crêpes feuilletées)': ['Petit-déjeuner'],
    'Adana kebab': ['Viande'],
    # DATA 2 ─ Américain
    'Pulled pork': ['Viande'],
    'Lobster mac and cheese': ['Poisson', 'Pâtes'],
    'Clam chowder': ['Poisson', 'Soupe'],
    'Buffalo wings': ['Viande'],
    'Macaroni salad': ['Salade'],
    'Coleslaw': ['Salade', 'Végétarien'],
    'Cheeseburger au bacon': ['Sandwich', 'Viande'],
    # DATA 2 ─ Japonais
    'Tonkatsu': ['Asiatique', 'Viande'],
    'Onigiri': ['Asiatique'],
    'Miso soup': ['Asiatique', 'Soupe', 'Végétarien'],
    'Tempura de crevettes': ['Asiatique', 'Poisson'],
    'Karaage (poulet frit japonais)': ['Asiatique', 'Viande'],
    'Okonomiyaki': ['Asiatique', 'Viande'],
    # DATA 2 ─ Chinois
    'Wonton soup': ['Asiatique', 'Soupe'],
    'Sweet and sour pork': ['Asiatique', 'Viande'],
    'Peking duck (canard laqué simplifié)': ['Asiatique', 'Viande'],
    'Riz gluant mangue': ['Asiatique', 'Dessert'],
    # DATA 2 ─ Grillades
    'Entrecôte grillée aux herbes': ['Viande'],
    'Brochettes de poulet mariné': ['Viande'],
    'Côtes de boeuf grillées': ['Viande'],
    'Brochettes de légumes grillés': ['Végétarien'],
    'Poulet entier grillé': ['Viande'],
    # DATA 2 ─ Salades complètes
    'Salade de lentilles et feta': ['Salade', 'Végétarien'],
    'Salade de pois chiches rôtis': ['Salade', 'Végétarien'],
    'Salade thaïlandaise verte': ['Salade', 'Asiatique'],
    # DATA 2 ─ Galettes/crêpes
    'Galette bretonne jambon-fromage': ['Viande'],
    'Blinis au saumon': ['Poisson'],
    # DATA 2 ─ Légumineuses
    'Haricots blancs à la tomate': ['Végétarien'],
    'Soupe de haricots noirs': ['Soupe', 'Végétarien'],
    'Pois chiches rôtis épicés': ['Végétarien'],
    'Salade de quinoa taboulé': ['Salade', 'Végétarien'],
    # DATA 2 ─ Volaille spéciale
    'Coq au vin': ['Viande', 'Plat mijoté'],
    'Ballotine de poulet': ['Viande'],
    'Poulet grillé marinade yaourt': ['Viande'],
    'Escalopes de dinde sautées': ['Viande'],
    # DATA 2 ─ Soupes spéciales
    'Soupe de poisson rouille': ['Poisson', 'Soupe'],
    'Soupe poireaux pommes de terre': ['Soupe', 'Végétarien'],
    'Soupe de pistou': ['Soupe', 'Végétarien'],
    'Borscht': ['Soupe', 'Viande'],
    'Soupe miso et nouilles soba': ['Asiatique', 'Soupe'],
    # DATA 2 ─ Crustacés
    'Bisque de homard': ['Poisson', 'Soupe'],
    'Coquilles Saint-Jacques gratinées': ['Poisson'],
    'Risotto aux fruits de mer': ['Poisson'],
    'Fritto misto di mare': ['Poisson'],
    # DATA 2 ─ Fromages/Entrées
    'Fondue savoyarde': ['Végétarien'],
    'Raclette classique': ['Viande'],
    'Bruschetta tomate-basilic': ['Végétarien'],
    'Tartare de saumon': ['Poisson'],
    'Tartare de boeuf': ['Viande'],
    'Gravlax de saumon': ['Poisson'],
    # DATA 2 ─ Légumes
    'Aubergines parmigiana': ['Végétarien'],
    'Légumes rôtis au four': ['Végétarien'],
    'Tian de légumes provençal': ['Végétarien'],
    'Velouté de petits pois à la menthe': ['Soupe', 'Végétarien'],
    'Carotte braisée au cumin': ['Végétarien'],
    'Poêlée de champignons': ['Végétarien'],
    # DATA 2 ─ Desserts suite
    'Profiteroles au chocolat': ['Dessert'],
    'Opéra': ['Dessert'],
    'Paris-Brest': ['Dessert'],
    'Charlotte aux fraises': ['Dessert'],
    'Gâteau au yaourt': ['Dessert'],
    'Brownies au chocolat': ['Dessert'],
    'Cheesecake new-yorkais': ['Dessert'],
    'Coulant praliné': ['Dessert'],
    'Tarte aux abricots': ['Dessert'],
    'Sorbet citron': ['Dessert'],
    'Panna cotta vanille': ['Dessert'],
    # DATA 3 ─ Coréen
    'Bibimbap': ['Asiatique', 'Viande'],
    'Kimchi jjigae': ['Asiatique', 'Viande', 'Soupe'],
    'Korean fried chicken': ['Asiatique', 'Viande'],
    'Japchae': ['Asiatique'],
    # DATA 3 ─ Vietnamien
    'Phở bo': ['Asiatique', 'Viande', 'Soupe'],
    'Bún bò Huế': ['Asiatique', 'Viande', 'Soupe'],
    'Nems frits': ['Asiatique'],
    'Bò lúc lắc': ['Asiatique', 'Viande'],
    # DATA 3 ─ Africain
    'Mafé': ['Viande', 'Plat mijoté'],
    'Thiéboudienne': ['Poisson'],
    'Jollof rice': ['Viande'],
    'Poulet yassa': ['Viande'],
    # DATA 3 ─ Italien avancé
    'Saltimbocca alla romana': ['Viande'],
    'Arancini siciliens': ['Viande'],
    'Cacio e pepe': ['Pâtes', 'Végétarien'],
    'Pappardelle au sanglier': ['Pâtes', 'Viande'],
    'Polenta crémeuse': ['Végétarien'],
    'Pâtes con le sarde': ['Pâtes', 'Poisson'],
    'Risotto al nero di seppia': ['Poisson'],
    # DATA 3 ─ Gastronomique français
    'Foie gras poêlé': ['Viande'],
    'Soufflé au fromage': ['Végétarien'],
    "Canard à l'orange": ['Viande'],
    'Turbot au beurre blanc': ['Poisson'],
    'Saint-Jacques en coquille au gratin': ['Poisson'],
    'Terrine de campagne': ['Viande'],
    'Crème vichyssoise': ['Soupe', 'Végétarien'],
    'Beurre blanc nantais': ['Végétarien'],
    # DATA 3 ─ Pâtisserie fine
    'Macarons parisiens': ['Dessert'],
    'Mille-feuille': ['Dessert'],
    'Tarte bourdaloue': ['Dessert'],
    'Bûche de Noël tiramisu': ['Dessert'],
    'Tarte passion-chocolat': ['Dessert'],
    'Entremets framboise vanille': ['Dessert'],
    # DATA 3 ─ Fermenté/levain
    'Pain de seigle au levain': ['Végétarien'],
    'Pizza napolitaine vrai VPN': ['Végétarien'],
    # DATA 3 ─ Créatif
    'Gaspacho de betterave': ['Soupe', 'Végétarien'],
    "Velouté d'asperges blanches": ['Soupe', 'Végétarien'],
    'Poulpe braisé': ['Poisson', 'Plat mijoté'],
    'Côte de veau sauce morilles': ['Viande'],
    # DATA 3 ─ Végétarien élaboré
    'Wellington végétarien': ['Végétarien'],
    'Burger végétarien betterave': ['Végétarien', 'Sandwich'],
    'Tagine de légumes': ['Végétarien', 'Plat mijoté'],
    'Soupe miso aux champignons variés': ['Asiatique', 'Soupe', 'Végétarien'],
    'Lasagnes végétariennes': ['Pâtes', 'Végétarien'],
    'Gado-gado': ['Asiatique', 'Végétarien'],
    # DATA 3 ─ Tapas/bouchées
    'Croquetas de jamón': ['Viande'],
    'Patatas bravas': ['Végétarien'],
    'Pimientos de padrón': ['Végétarien'],
    'Dumplings xiao long bao': ['Asiatique'],
    'Spanakopita': ['Végétarien'],
    # DATA 3 ─ Boissons
    'Limonade maison': ['Boisson'],
    'Kombucha maison': ['Boisson'],
    'Lassi à la mangue': ['Boisson'],
    'Horchata': ['Boisson'],
    'Matcha latte': ['Boisson'],
    # DATA 3 ─ Quotidien
    'Salade niçoise express': ['Salade', 'Poisson'],
    'Oeufs mimosa': ['Végétarien'],
    'Omelette soufflée': ['Végétarien'],
    'Poêlée de courgettes': ['Végétarien'],
    'Poêlée de pommes de terre grenailles': ['Végétarien'],
    'Riz basmati au curry': ['Végétarien'],
    'Lentilles béluga au vinaigre': ['Végétarien'],
    'Gésiers confits en salade': ['Salade', 'Viande'],
    # DATA 3 ─ Fast food sain
    'Fish tacos': ['Poisson', 'Sandwich'],
    'Doner kebab maison': ['Viande', 'Sandwich'],
    'Pita et falafel': ['Végétarien', 'Sandwich'],
    'Bowl poulet teriyaki': ['Asiatique', 'Viande'],
    'Bánh mì': ['Sandwich', 'Viande'],
    # DATA 3 ─ Festif
    'Tournedos Rossini': ['Viande'],
    'Dinde de Noël farcie': ['Viande'],
    "Saumon en croûte d'herbes": ['Poisson'],
    'Ceviche festif': ['Poisson'],
    'Agneau de Pâques rôti': ['Viande'],
    # DATA 3 ─ Économique
    'Tarte flambée (Flammekueche)': ['Viande'],
    'Goulash hongrois': ['Viande', 'Plat mijoté'],
    'Tortilla de patatas': ['Végétarien'],
    'Polpettes (boulettes italiennes)': ['Viande'],
    'Saucisses aux lentilles': ['Viande'],
    'Poireaux à la vinaigrette': ['Végétarien'],
    'Gratin de chou-fleur': ['Végétarien'],
    'Chou farci': ['Viande'],
    'Potée auvergnate': ['Viande', 'Plat mijoté'],
    'Daube provençale': ['Viande', 'Plat mijoté'],
    "Poulet des dimanches à l'estragon": ['Viande'],
    'Steak de thon grillé': ['Poisson'],
    'Gratin de macaroni au jambon': ['Pâtes', 'Viande'],
    # DATA 3 ─ Desserts finaux
    'Tarte tatin aux pêches': ['Dessert'],
    'Compote de pommes maison': ['Dessert'],
    'Verrine fraise et chantilly': ['Dessert'],
    'Salade de fruits frais': ['Dessert'],
    'Chocolat chaud maison': ['Boisson', 'Dessert'],
    'Sangria maison': ['Boisson'],
    'Houmous de betterave': ['Végétarien'],
    'Tartare de betterave aux noix': ['Végétarien'],
    'Rouleaux de printemps crus': ['Asiatique', 'Végétarien'],
    'Panzanella': ['Salade', 'Végétarien'],
    'Salade de farro aux légumes rôtis': ['Salade', 'Végétarien'],
    'Crumble aux pommes': ['Dessert'],
    'Gâteau basque': ['Dessert'],
    'Baklava': ['Dessert'],
    'Financiers aux amandes': ['Dessert'],
    'Canelés bordelais': ['Dessert'],
}


def get_cats_for_recipe(title: str, original_cat: str) -> list:
    # Unescape Dart escaped apostrophes: \' → '
    clean_title = title.replace("\\'" , "'")
    if clean_title in CATS_MAP:
        return CATS_MAP[clean_title]
    if title in CATS_MAP:
        return CATS_MAP[title]
    cat = original_cat.strip("'\"")
    return [cat] if cat else ['Végétarien']


# ── TRANSFORMATION DES FICHIERS ────────────────────────────────────────────

def dart_str_list(lst: list) -> str:
    items = ','.join(f"'{x}'" for x in lst)
    return f'[{items}]'


INGR_RE = re.compile(
    r"\['((?:[^'\\]|\\.)*)',\s*(\d+(?:\.\d+)?),\s*'((?:[^'\\]|\\.)*)'"
    r"(?:,\s*'((?:[^'\\]|\\.)*)')?\]"
)

CAT_RE = re.compile(r"'cat'\s*:\s*'([^']+)'")
CATS_RE = re.compile(r"'cats'\s*:\s*\[([^\]]*)\]")


def transform_recipe_line(line: str) -> str:
    title_match = re.search(r"'t'\s*:\s*'((?:[^'\\]|\\.)*)'", line)
    if not title_match:
        return line
    title = title_match.group(1)

    # Transformer 'cat' → 'cats'
    cat_match = CAT_RE.search(line)
    cats_match = CATS_RE.search(line)

    if cat_match and not cats_match:
        original_cat = cat_match.group(1)
        cats = get_cats_for_recipe(title, original_cat)
        cats_dart = dart_str_list(cats)
        line = CAT_RE.sub(f"'cats':{cats_dart}", line, count=1)
    elif cats_match:
        cats = get_cats_for_recipe(title, '')
        if cats:
            cats_dart = dart_str_list(cats)
            old_cats_str = cats_match.group(0)
            line = line.replace(old_cats_str, f"'cats':{cats_dart}", 1)

    # Ajouter/corriger le type de chaque ingrédient
    def replace_ingredient(m):
        name = m.group(1)
        qty = m.group(2)
        unit = m.group(3)
        t = classify(name)
        return f"['{name}',{qty},'{unit}','{t}']"

    line = INGR_RE.sub(replace_ingredient, line)
    return line


def transform_file(filename: str):
    path = os.path.join(BASE, filename)
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    new_lines = []
    missing_cats = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("{'t'"):
            new_line = transform_recipe_line(line)
            new_lines.append(new_line)
            # Vérifier si le titre est dans CATS_MAP
            m = re.search(r"'t'\s*:\s*'((?:[^'\\]|\\.)*)'", stripped)
            if m:
                raw = m.group(1)
                clean = raw.replace("\\'", "'")
                if clean not in CATS_MAP and raw not in CATS_MAP:
                    missing_cats.append(raw)
        else:
            new_lines.append(line)

    new_content = '\n'.join(new_lines)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    count = sum(1 for l in new_lines if l.strip().startswith("{'t'"))
    print(f'[OK] {filename}: {count} recettes transformées')
    if missing_cats:
        for t in missing_cats:
            print(f'  ⚠ Titre non trouvé dans CATS_MAP: {t!r}')


# ── MAIN ────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print('=== Transformation des fichiers de cache recipes ===')
    print()
    for fname in ['recipes_cache_data_1.dart', 'recipes_cache_data_2.dart', 'recipes_cache_data_3.dart']:
        transform_file(fname)
    print()
    print('=== Terminé ===')
