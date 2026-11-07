import os
import re

ROOT = '/Users/dylan/Downloads/SwiftCode'
LEGACY = os.path.join(ROOT, 'SwiftCode-Legacy')

not_found_list = []
with open('/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/unmatched_analysis.txt') as f:
    for line in f:
        if line.startswith('[NOT_FOUND_BY_STEM]'):
            rel = line.strip().split(' ', 1)[1]
            not_found_list.append(rel)

print(f'Analyzing {len(not_found_list)} files...')

TYPE_DECL_REGEX = re.compile(r'^\s*(?:(?:public|private|fileprivate|internal|open|final|actor|nonisolated|@\w+(?:\([^)]*\))?)\s+)*(?:class|struct|enum|protocol|actor)\s+([A-Za-z0-9_]+)', re.MULTILINE)

report_lines = []
for rel in sorted(not_found_list):
    full = os.path.join(LEGACY, rel)
    if not os.path.exists(full):
        continue
    with open(full, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        lines = len(content.splitlines())
        types = TYPE_DECL_REGEX.findall(content)
        report_lines.append((rel, lines, types))

with open('/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_1/not_found_details.txt', 'w') as out:
    for rel, lines, types in report_lines:
        out.write(f'{rel:70} | {lines:4} lines | types: {types}\n')

print(f'Wrote details for {len(report_lines)} files to not_found_details.txt')
