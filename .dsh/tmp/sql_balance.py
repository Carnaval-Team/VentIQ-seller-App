import sys, re

def check(path):
    s = open(path, encoding='utf-8').read()
    i = 0
    n = len(s)
    line = 1
    errs = []
    while i < n:
        c = s[i]
        if c == '\n':
            line += 1; i += 1; continue
        if c == '-' and i + 1 < n and s[i+1] == '-':
            j = s.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            if j < 0:
                errs.append((line, 'comentario /* sin cerrar')); break
            line += s.count('\n', i, j); i = j + 2; continue
        if c == "'":
            start = line; i += 1; closed = False
            while i < n:
                if s[i] == '\n':
                    line += 1
                if s[i] == "'":
                    if i + 1 < n and s[i+1] == "'":
                        i += 2; continue
                    closed = True; i += 1; break
                i += 1
            if not closed:
                errs.append((start, 'comilla simple sin cerrar'))
            continue
        if c == '$':
            m = re.match(r'\$([A-Za-z_0-9]*)\$', s[i:])
            if m:
                tag = m.group(0)
                j = s.find(tag, i + len(tag))
                if j < 0:
                    errs.append((line, 'dollar-quote %s sin cerrar' % tag)); break
                line += s.count('\n', i, j)
                i = j + len(tag)
                continue
        i += 1
    print('%-58s lineas=%-5d %s' % (path, line, errs if errs else 'OK'))

for p in sys.argv[1:]:
    check(p)