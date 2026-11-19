import struct, json, re
d=open('/home/ubuntu/rea_uuyc/slices/UURemote.arm64','rb').read()
CS_LO,CS_HI=0x1013f1b40,0x1013f1b40+0x10f368
def isptr(v): return CS_LO<=v<CS_HI
def cstr(v):
    o=v-0x100000000; e=d.index(b'\0',o); return d[o:e].decode('utf-8')
start,end=0x1920180,0x1920180+0x89880
blocks=[]; off=start
while off<end-16:
    n=struct.unpack_from('<Q',d,off)[0]
    m=struct.unpack_from('<Q',d,off+8)[0]
    if 1<=n<=90 and m==2*n and struct.unpack_from('<Q',d,off+16)[0]==1 and isptr(struct.unpack_from('<Q',d,off+24)[0]):
        entries=[];p=off+16
        ok=True
        for k in range(n):
            num=struct.unpack_from('<Q',d,p)[0]
            ptr=struct.unpack_from('<Q',d,p+8)[0]
            ln=struct.unpack_from('<Q',d,p+16)[0]
            if not isptr(ptr) or num!=k+1: ok=False; break
            nm=cstr(ptr)
            if len(nm)!=ln: ok=False; break
            entries.append(dict(no=num,name=nm,kind=struct.unpack_from('<Q',d,p+24)[0]))
            p+=0x38
        if ok and entries:
            blocks.append(dict(addr=off,count=n,entries=entries))
            off=p; continue
    off+=8
print('blocks',len(blocks))
types=json.load(open('/home/ubuntu/uuyc_clone/analysis/derived/swift_types.json'))
msgs={}
for t in types:
    nm=t['name']; par=t['parent']
    if nm and nm.startswith('GvPb_') and nm!='StorageClass':
        key=nm
    elif nm=='StorageClass' and par and par.startswith('GvPb_'):
        key=par
    else: continue
    f=[x for x in (t['fields'] or []) if x['name']!='unknownFields']
    prev=msgs.get(key)
    if prev is None or len(f)>len(prev):
        msgs[key]=f
print('msgs',len(msgs))
from collections import Counter
print(Counter(len(v) for v in msgs.values()))
print(Counter(b['count'] for b in blocks))
json.dump(blocks,open('/home/ubuntu/uuyc_clone/analysis/derived/nameblocks.json','w'))
