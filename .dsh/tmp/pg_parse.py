import sys
import pglast
from pglast import parser

def check(path):
    text = open(path, encoding='utf-8').read()
    try:
        parser.parse_sql(text)
        return ('OK', None)
    except Exception as e:
        loc = getattr(e, 'location', None)
        line = None
        if isinstance(loc, int):
            line = text.count('\n', 0, loc) + 1
        return ('ERROR', (line, str(e).strip().replace('\n', ' ')[:300]))

for p in sys.argv[1:]:
    st, info = check(p)
    if st == 'OK':
        print('%-58s OK' % p)
    else:
        line, msg = info
        print('%-58s ERROR L%s :: %s' % (p, line, msg))