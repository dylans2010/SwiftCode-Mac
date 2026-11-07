import os
import re
import collections

ROOT = '/Users/dylan/Downloads/SwiftCode'
LEGACY_DIR = os.path.join(ROOT, 'SwiftCode-Legacy')

# Production directories to check
PROD_DIRS = [
    os.path.join(ROOT, 'swiftcode'),
    os.path.join(ROOT, 'frameworks'),
    os.path.join(ROOT, 'composer'),
    os.path.join(ROOT, 'sdk'),
    os.path.join(ROOT, 'tools'),
    os.path.join(ROOT, 'packaging')
]

print('Scanning production files...')
prod_files = {} # basename -> list of relative paths from ROOT
prod_swift_files = {} # path -> set of declared types
type_to_prod_file = collections.defaultdict(list)

TYPE_DECL_REGEX = re.compile(r'^\s*(?:(?:public|private|fileprivate|internal|open|final|actor|nonisolated|@\w+(?:\([^)]*\))?)\s+)*(?:class|struct|enum|protocol|actor)\s+([A-Za-z0-9_]+)', re.MULTILINE)

for pdir in PROD_DIRS:
    for root, dirs, files in os.walk(pdir):
        # Skip .build and .git
        if '.build' in root.split(os.sep) or '.git' in root.split(os.sep):
            continue
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, ROOT)
            prod_files.setdefault(f, []).append(rel)
            if f.endswith('.swift'):
                try:
                    with open(full, 'r', encoding='utf-8', errors='ignore') as sfile:
                        content = sfile.read()
                        types = set(TYPE_DECL_REGEX.findall(content))
                        prod_swift_files[rel] = types
                        for t in types:
                            type_to_prod_file[t].append(rel)
                except Exception as e:
                    pass

print(f'Total production files indexed: {sum(len(v) for v in prod_files.values())} ({len(prod_files)} unique basenames)')
print(f'Total production Swift files: {len(prod_swift_files)}')
print(f'Total production types declared: {len(type_to_prod_file)}')

print('\nScanning Legacy files...')
legacy_files = []
legacy_swift = []
for root, dirs, files in os.walk(LEGACY_DIR):
    if '.git' in root.split(os.sep):
        continue
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, LEGACY_DIR)
        legacy_files.append((rel, full))
        if f.endswith('.swift'):
            legacy_swift.append((rel, full))

print(f'Total legacy files: {len(legacy_files)}')
print(f'Total legacy Swift files: {len(legacy_swift)}')

# Analyze Swift files
exact_filename_match = []
type_matched = []
unmatched_swift = []

for rel, full in legacy_swift:
    fname = os.path.basename(rel)
    # Check exact basename match
    if fname in prod_files:
        exact_filename_match.append((rel, prod_files[fname]))
        continue
    
    # Check type matches
    try:
        with open(full, 'r', encoding='utf-8', errors='ignore') as sf:
            content = sf.read()
            types = set(TYPE_DECL_REGEX.findall(content))
    except:
        types = set()
    
    matched_dest = set()
    for t in types:
        if t in type_to_prod_file:
            for p in type_to_prod_file[t]:
                matched_dest.add((t, p))
                
    if matched_dest:
        type_matched.append((rel, types, list(matched_dest)))
    else:
        unmatched_swift.append((rel, types))

print(f'\nExact basename matches: {len(exact_filename_match)}')
print(f'Type-only matches (renamed/consolidated): {len(type_matched)}')
print(f'Unmatched Swift files (candidates for missing): {len(unmatched_swift)}')

with open('/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/unmatched_swift.txt', 'w') as out:
    for rel, types in sorted(unmatched_swift):
        out.write(f'{rel} | types: {list(types)}\n')

with open('/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/type_matched.txt', 'w') as out:
    for rel, types, matches in sorted(type_matched):
        out.write(f'{rel} -> {matches}\n')
