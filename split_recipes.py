import re, os

BASE = r'c:\Users\E082903\Desktop\RecipePlanner\lib\data\services'
OUT  = r'c:\Users\E082903\Desktop\RecipePlanner\lib\data\services\recipes_cache_split'
os.makedirs(OUT, exist_ok=True)

files = ['recipes_cache_data_1.dart','recipes_cache_data_2.dart','recipes_cache_data_3.dart']

# Collect all recipe lines in order
recipe_lines = []
for fname in files:
    with open(os.path.join(BASE, fname), encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("{'t':"):
                recipe_lines.append(stripped)

print(f"Total recipes: {len(recipe_lines)}")

CHUNK = 50
file_index = 1
for start in range(0, len(recipe_lines), CHUNK):
    chunk = recipe_lines[start:start+CHUNK]
    varname = f'recipeCacheData{file_index}'
    lines = [f'const List<Map<String, dynamic>> {varname} = [\n']
    for r in chunk:
        # ensure trailing comma
        if r.endswith('},'):
            lines.append(f'  {r}\n')
        elif r.endswith('}'):
            lines.append(f'  {r},\n')
        else:
            lines.append(f'  {r},\n')
    lines.append('];\n')
    out_path = os.path.join(OUT, f'recipes_cache_data_{file_index}.dart')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print(f"  recipes_cache_data_{file_index}.dart : {len(chunk)} recipes")
    file_index += 1

print(f"Done — {file_index-1} files created.")
