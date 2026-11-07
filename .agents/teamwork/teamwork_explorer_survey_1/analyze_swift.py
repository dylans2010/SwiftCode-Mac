import collections
import os

parity_file = '/Users/dylan/Downloads/SwiftCode/MIGRATION_FEATURE_PARITY.md'
legacy_dir = '/Users/dylan/Downloads/SwiftCode/SwiftCode-Legacy'

ma_not_started = []
all_not_started_swift = []
all_parity_paths = set()

with open(parity_file, 'r', encoding='utf-8') as f:
    for line in f:
        if not line.startswith('| `'):
            continue
        parts = [p.strip() for p in line.split('|')[1:-1]]
        if len(parts) < 4:
            continue
        path = parts[0].strip('`')
        disp = parts[1]
        dest = parts[2].strip('`')
        status = parts[3]
        all_parity_paths.add(path)
        
        if status == 'NOT STARTED':
            if disp == 'MIGRATE_AND_ADAPT':
                ma_not_started.append((path, disp, dest))
            if path.endswith('.swift'):
                all_not_started_swift.append((path, disp, dest))

print(f'Total MIGRATE_AND_ADAPT NOT STARTED: {len(ma_not_started)}')
print(f'Total .swift files NOT STARTED in parity: {len(all_not_started_swift)}')

# Group by folder
by_dir = collections.defaultdict(list)
for p, d, dest in all_not_started_swift:
    folder = '/'.join(p.split('/')[:-1])
    by_dir[folder].append(p.split('/')[-1])

print('\n=== Unmigrated .swift files by directory ===')
for folder, files in sorted(by_dir.items()):
    print(f'{folder} ({len(files)} files):')
    for f in files[:5]:
        print(f'  - {f}')
    if len(files) > 5:
        print(f'  ... and {len(files) - 5} more')

# Check if there are any swift files in SwiftCode-Legacy not in parity ledger
untracked_swift = []
for root, dirs, files in os.walk(legacy_dir):
    for f in files:
        if f.endswith('.swift'):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, legacy_dir)
            if rel not in all_parity_paths:
                untracked_swift.append(rel)

print(f'\nSwift files in SwiftCode-Legacy not in parity ledger: {len(untracked_swift)}')
for u in untracked_swift:
    print(f'  - {u}')
