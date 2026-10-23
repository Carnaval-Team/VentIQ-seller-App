import sys, re

# Heuristica estricta: dentro de un cuerpo $tag$ (o de todo el archivo), marca las
# lineas cuyo numero de comillas simples (fuera de comentario de linea) es IMPAR,
# porque en estos archivos ninguna cadena deberia cruzar de linea.
def odd_lines(text):
    out = []
    for n, raw in enumerate(text.split('\n'), start=1):
        s = raw
        # cortar comentario de linea (fuera de string)
        res = []
        i = 0
        instr = False
        while i < len(s):
            if not instr and s[i] == '-' and i+1 < len(s) and s[i+1] == '-':
                break
            if s[i] == "'":
                if instr and i+1 < len(s) and s[i+1] == "'":
                    i += 2; continue
                instr = not instr
            res.append(s[i]); i += 1
        code = ''.join(res)
        if code.count("'") % 2 == 1:
            out.append((n, raw.strip()[:110]))
    return out

def bodies(text):
    # devuelve el texto sin los delimitadores $tag$ para analizar solo cuerpos
    return re.sub(r'\$[A-Za-z_0-9]*\$', '\n', text)

for p in sys.argv[1:]:
    t = open(p, encoding='utf-8').read()
    o_all = odd_lines(t)
    o_body = odd_lines(bodies(t))
    print('=== %s' % p)
    if not o_all:
        print('   sin lineas de comillas impares: OK')
    else:
        for n, txt in o_all:
            marca = 'BODY' if any(b[0] == n for b in o_body) else 'fuera-de-cuerpo'
            print('   L%-5d [%s] %s' % (n, marca, txt))