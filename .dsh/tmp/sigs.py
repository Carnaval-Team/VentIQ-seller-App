import re, sys
for path in sys.argv[1:]:
    lines = open(path, encoding='utf-8').read().split('\n')
    print('===', path)
    for i, l in enumerate(lines):
        if re.match(r'CREATE OR REPLACE FUNCTION public\.\w+\(', l):
            name = l.strip()
            j = i + 1
            params = []
            while not lines[j].strip().startswith(')'):
                params.append(lines[j].strip())
                j += 1
            types = []
            for p in params:
                p = p.split(' DEFAULT ')[0].split('::')[0].strip()
                types.append(p.split()[-1])
            print('  %-70s (%s)' % (name.replace('CREATE OR REPLACE FUNCTION public.', '').rstrip('('), ', '.join(types)))
