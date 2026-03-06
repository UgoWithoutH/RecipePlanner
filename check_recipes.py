import re, os

BASE = r'c:\Users\E082903\Desktop\RecipePlanner\lib\data\services'
files = ['recipes_cache_data_1.dart','recipes_cache_data_2.dart','recipes_cache_data_3.dart']

total_recipes = 0
missing_cats = []
missing_type = []

for fname in files:
    with open(os.path.join(BASE, fname), encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if not stripped.startswith("{'t'"):
                continue
            total_recipes += 1

            # title
            m = re.search(r"'t'\s*:\s*'((?:[^'\\]|\\.)*)'", stripped)
            title = m.group(1).replace("\\'", "'") if m else '?'

            # cats
            cats_m = re.search(r"'cats'\s*:\s*\[([^\]]*)\]", stripped)
            if not cats_m or not cats_m.group(1).strip():
                missing_cats.append(f'{fname}: {title}')

            # each ingredient — check 4th element present
            ingr_all = re.findall(
                r"\['(?:[^'\\]|\\.)*',\s*\d+(?:\.\d+)?,\s*'(?:[^'\\]|\\.)*'((?:,\s*'(?:[^'\\]|\\.)*')?)\]",
                stripped
            )
            for suffix in ingr_all:
                if not suffix.strip():
                    # find ingredient name for context
                    nm = re.search(r"\['((?:[^'\\]|\\.)*)',", stripped)
                    missing_type.append(f'{fname} [{title}]')

print(f'Total recettes  : {total_recipes}')
print(f'Sans cats       : {len(missing_cats)}')
for x in missing_cats:
    print(f'  ⚠ {x}')
print(f'Ingr. sans type : {len(missing_type)}')
for x in missing_type[:30]:
    print(f'  ⚠ {x}')
if len(missing_type) > 30:
    print(f'  ... et {len(missing_type)-30} autres')
