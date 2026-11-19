import json,re
types=json.load(open('/home/ubuntu/uuyc_clone/analysis/derived/swift_types.json'))
blocks=json.load(open('/home/ubuntu/uuyc_clone/analysis/derived/nameblocks.json'))

def snake(s):
    s=re.sub(r'_p$','',s); s=s.lstrip('_')
    s=re.sub(r'([A-Z]+)([A-Z][a-z])',r'\1_\2',s)
    s=re.sub(r'([a-z0-9])([A-Z])',r'\1_\2',s)
    return s.lower()
def camel(s):
    return ''.join(w.capitalize() for w in s.split('_'))

structs={t['name']:t for t in types if (t['name'] or '').startswith('GvPb_') and t['kind']==17}
classes=[t for t in types if t['name']=='_StorageClass']
def clean(fs): return [f for f in fs if f['name'] not in ('unknownFields',)]
HEAP={'GvPb_ConnectOptions':0,'GvPb_Screen':1,'GvPb_Message':2,'GvPb_MumuSettingRange':3,'GvPb_CaptureSettingRequest':4}
oneof_cases={}
for t in types:
    if (t['name'] or '').startswith('OneOf_') and t['parent']:
        oneof_cases[t['parent']]=[f['name'] for f in (t['fields'] or [])]

msgs={}
for name,t in structs.items():
    if name in HEAP:
        fs=clean(classes[HEAP[name]]['fields'] or [])
        fs=[dict(name=f['name'],mangled=f['mangled']) for f in fs]
    else:
        fs=clean(t['fields'] or [])
    msgs[name]=dict(fields=fs, oneof=[snake(c) for c in oneof_cases.get(name,[])])

# match blocks
used=set(); matched={}
order=sorted(msgs.keys())
for name in order:
    m=msgs[name]
    n=len(m['fields'])
    total=n
    if name in HEAP and name=='GvPb_Message':
        total=n-1+len(m['oneof'])
    cands=[]
    for bi,b in enumerate(blocks):
        if bi in used: continue
        if b['count']!=total: continue
        score=0
        protos=[e['name'] for e in b['entries']]
        swift=[snake(f['name']) for f in m['fields']]
        for s in swift:
            if s in protos: score+=2
        for c in m['oneof']:
            if c in protos: score+=2
        cands.append((score,bi))
    cands.sort(reverse=True)
    if cands and cands[0][0]>0:
        bi=cands[0][1]; used.add(bi)
        matched[name]=dict(block=blocks[bi],fields=m['fields'],oneof=m['oneof'])
print('matched',len(matched),'of',len(msgs))
un=[n for n in msgs if n not in matched]
print('unmatched',len(un),un[:20])
json.dump({k:dict(fields=v['fields'],oneof=v['oneof'],entries=v['block']['entries']) for k,v in matched.items()},
          open('/home/ubuntu/uuyc_clone/analysis/derived/schema_matched.json','w'),indent=1)
# print core
for k in ['GvPb_Message','GvPb_ConnectOptions','GvPb_CaptureSettingRequest','GvPb_Screen']:
    if k in matched:
        print('==',k)
        for e,f in zip(matched[k]['block']['entries'],matched[k]['fields']+[{}]*0):
            print('  ',e['no'],e['name'],'|',f['name'],repr(f['mangled'])[:20])
