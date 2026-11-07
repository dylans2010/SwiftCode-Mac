import collections

parity_file = '/Users/dylan/Downloads/SwiftCode/MIGRATION_FEATURE_PARITY.md'

disp_swift = collections.defaultdict(list)

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
        if status == 'NOT STARTED' and path.endswith('.swift'):
            disp_swift[disp].append((path, dest))

for disp, items in sorted(disp_swift.items(), key=lambda x: -len(x[1])):
    print(f'=== {disp}: {len(items)} swift files ===')
    for p, d in items[:10]:
        print(f'  {p} -> {d}')
    if len(items) > 10:
        print(f'  ... and {len(items) - 10} more')
