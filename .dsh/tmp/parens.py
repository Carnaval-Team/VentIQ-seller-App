import sys
def scan(text):
    depth=0; i=0; n=len(text); line=1; bad=None
    stack=[]
    while i<n:
        c=text[i]
        if c=='\n': line+=1; i+=1; continue
        if c=='-' and i+1<n and text[i+1]=='-':
            j=text.find('\n',i); i=n if j<0 else j; continue
        if c=='/' and i+1<n and text[i+1]=='*':
            j=text.find('*/',i+2)
            if j<0: return (line,'comentario sin cerrar')
            line+=text.count('\n',i,j); i=j+2; continue
        if c=="'":
            i+=1
            while i<n:
                if text[i]=='\n': line+=1
                if text[i]=="'":
                    if i+1<n and text[i+1]=="'": i+=2; continue
                    i+=1; break
                i+=1
            continue
        if c=='(':
            depth+=1; stack.append(line)
        elif c==')':
            depth-=1
            if depth<0: return (line,'parentesis de mas')
            stack.pop()
        i+=1
    if depth!=0: return (stack[-1] if stack else line, 'quedan %d parentesis abiertos (ultimo abierto en L%s)'%(depth, stack[-1] if stack else '?'))
    return None
for p in sys.argv[1:]:
    r=scan(open(p,encoding='utf-8').read())
    print('%-58s %s' % (p, 'OK' if r is None else 'PROBLEMA: L%s %s'%r))
