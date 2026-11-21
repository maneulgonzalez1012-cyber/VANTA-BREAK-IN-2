import re,sys,lupa
lua=lupa.LuaRuntime()
compile_=lua.execute("return function(s) local f,e=load(s,'S') if f then return 'OK' else return e end end")
bad=0
for p in sys.argv[1:]:
    src=open(p,encoding='utf-8').read()
    out=[]
    for line in src.split("\n"):
        m=re.match(r'^(\s*)([\w\.\[\]"\']+?)\s*(\+=|-=|\*=|/=)\s*(.+)$', line)
        if m and not line.lstrip().startswith('--'):
            ind,lhs,op,rhs=m.groups()
            line=f'{ind}{lhs} = {lhs} {op[0]} ({rhs})'
        out.append(line)
    r=compile_("\n".join(out))
    if r!='OK':
        bad+=1; print("FAIL",p,"->",r)
    else:
        print("OK  ",p)
sys.exit(1 if bad else 0)
