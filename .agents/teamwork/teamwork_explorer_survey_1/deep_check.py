import os
import re
import collections

unmatched_file = '/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/unmatched_swift.txt'
ROOT = '/Users/dylan/Downloads/SwiftCode'
PROD = os.path.join(ROOT, 'swiftcode')

unmatched = []
with open(unmatched_file) as f:
    for line in f:
        rel = line.split(' | ')[0]
        if rel.startswith('SwiftCode/Backend/Assist/Tools'): continue
        if rel.startswith('SwiftCode/Tools/Agentic'): continue
        if rel.startswith('SwiftCode/SDK/Distribution'): continue
        unmatched.append(rel)

print(f'Checking {len(unmatched)} candidate files...')

# Map stem -> list of legacy paths
stems_to_legacy = collections.defaultdict(list)
for rel in unmatched:
    basename = os.path.basename(rel)
    stem = os.path.splitext(basename)[0]
    stems_to_legacy[stem].append(rel)

all_stems = set(stems_to_legacy.keys())
print(f'Unique stems to match: {len(all_stems)}')

stem_matches = collections.defaultdict(list)

# Single pass over production files
ID_REGEX = re.compile(r'[A-Za-z0-9_]+')

for root, dirs, files in os.walk(PROD):
    if '.build' in root.split(os.sep) or '.git' in root.split(os.sep): continue
    for f in files:
        if f.endswith('.swift'):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, ROOT)
            try:
                with open(full, 'r', encoding='utf-8', errors='ignore') as sf:
                    tokens = set(ID_REGEX.findall(sf.read()))
                    hits = all_stems.intersection(tokens)
                    for h in hits:
                        stem_matches[h].append(rel)
            except:
                pass

results = []
for stem, rels in stems_to_legacy.items():
    matches = stem_matches.get(stem, [])
    status = 'REFERENCED_OR_CONSOLIDATED' if matches else 'NOT_FOUND_BY_STEM'
    for r in rels:
        results.append((r, status, matches))

ref_count = sum(1 for r in results if r[1] == 'REFERENCED_OR_CONSOLIDATED')
not_found_count = sum(1 for r in results if r[1] == 'NOT_FOUND_BY_STEM')

print(f'Referenced / Consolidated: {ref_count}')
print(f'Not Found by Stem: {not_found_count}')

with open('/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/unmatched_analysis.txt', 'w') as out:
    for rel, status, matches in sorted(results):
        out.write(f'[{status}] {rel}\n')
        for m in matches[:5]:
            out.write(f'    -> {m}\n')

print('Results written to unmatched_analysis.txt')
