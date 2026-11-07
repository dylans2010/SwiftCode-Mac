import collections

parity_file = '/Users/dylan/Downloads/SwiftCode/MIGRATION_FEATURE_PARITY.md'

status_by_top = collections.defaultdict(lambda: collections.defaultdict(int))
disp_by_status = collections.defaultdict(lambda: collections.defaultdict(int))
missing_by_top = collections.defaultdict(list)

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
        
        top = path.split('/')[0]
        if top == 'SwiftCode' and '/' in path:
            top = '/'.join(path.split('/')[:2])
            
        status_by_top[top][status] += 1
        disp_by_status[status][disp] += 1
        if status == 'NOT STARTED':
            missing_by_top[top].append((path, disp, dest))

print('=== Status by Top Directory ===')
for top, stats in sorted(status_by_top.items()):
    stat_str = ', '.join(f'{k}: {v}' for k, v in sorted(stats.items()))
    print(f'{top:35}: {stat_str}')

print('\n=== Dispositions for NOT STARTED ===')
for disp, cnt in sorted(disp_by_status['NOT STARTED'].items(), key=lambda x: -x[1]):
    print(f'{disp:35}: {cnt}')

print('\n=== Non-swift MIGRATE_AND_ADAPT NOT STARTED ===')
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
        if status == 'NOT STARTED' and disp == 'MIGRATE_AND_ADAPT' and not path.endswith('.swift'):
            print(f'{path} -> {dest}')
