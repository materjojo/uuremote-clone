import json, re
blocks=json.load(open('/home/ubuntu/uuyc_clone/analysis/derived/nameblocks.json'))
types=json.load(open('/home/ubuntu/uuyc_clone/analysis/derived/swift_types.json'))
msgs={}
for t in types:
    nm=t['name']; par=t['parent']
    if nm and nm.startswith('GvPb_') and nm!='StorageClass': key=nm
    elif nm=='StorageClass' and par and par.startswith('GvPb_'): key=par
    else: continue
    f=[x for x in (t['fields'] or []) if x['name']!='unknownFields']
    if key not in msgs or len(f)>len(msgs[key]): msgs[key]=f

def snake(s):
    s=re.sub(r'_p$','',s)
    s=re.sub(r'([A-Z]+)([A-Z][a-z])',r'\1_\2',s)
    s=re.sub(r'([a-z0-9])([A-Z])',r'\1_\2',s)
    return s.lower()

def norm(s): return s.replace('_','').lower()

out={}; unmatched=[]; used=set()
for name,fields in msgs.items():
    if not fields: continue
    cands=[]
    for bi,b in enumerate(blocks):
        if bi in used: continue
        if b['count']!=len(fields): continue
        score=0
        for f,e in zip(fields,b['entries']):
            if snake(f['name'])==e['name']: score+=2
            elif norm(f['name'])==norm(e['name']): score+=1
        if score>0: cands.append((score,bi))
    cands.sort(reverse=True)
    if not cands: unmatched.append(name); continue
    best=cands[0]
    bi=best[1]; used.add(bi)
    out[name]=dict(block=bi,fields=[dict(no=e['no'],proto=e['name'],swift=f['name'],mangled=f['mangled'],kind=e['kind']) for f,e in zip(fields,blocks[bi]['entries'])])
print('matched',len(out),'unmatched',len(unmatched),'blocks used',len(used))
print('unmatched sample',unmatched[:15])
lowconf=[(k,v) for k,v in out.items() if any(snake(f['swift'])!=f['proto'] for f in v['fields'])]
print('with name diffs',len(lowconf))
for k,v in list(out.items())[:3]:
    print(k,[(f['no'],f['proto'],f['swift'],f['mangled']) for f in v['fields']])
json.dump(out,open('/home/ubuntu/uuyc_clone/analysis/derived/schema.json','w'),indent=1,ensure_ascii=False)
