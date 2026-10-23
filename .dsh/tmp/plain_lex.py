import sys

path = sys.argv[1]
a = int(sys.argv[2]); b = int(sys.argv[3])
lines = open(path, encoding='utf-8').read().split('\n')[a-1:b]

in_str = False
str_start = None
for idx, raw in enumerate(lines, start=a):
    # quitar comentario de linea fuera de string
    s = raw
    i = 0
    stripped = ''
    while i < len(s):
        if not in_str and s[i] == '-' and i+1 < len(s) and s[i+1] == '-':
            break
        if s[i] == "'":
            if in_str:
                if i+1 < len(s) and s[i+1] == "'":
                    i += 2; continue
                in_str = False
            else:
                in_str = True; str_start = idx
        i += 1
    if in_str and str_start is not None:
        tag = ' <- ABRE string sin cerrar aqui' if str_start == idx else ''
        print('L%-4d EN_STRING desde L%-4d%s | %s' % (idx, str_start, tag, s.strip()[:90]))
print('---')
print('estado final: en_string=%s desde L%s' % (in_str, str_start))