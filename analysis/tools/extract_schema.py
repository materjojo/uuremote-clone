import struct, sys, json
sys.path.insert(0,'/home/ubuntu/uuyc_clone/analysis/tools')
from macho import parse

P='/home/ubuntu/rea_uuyc/slices/UURemote.arm64'
d,segs,secs=parse(P)
N=len(d)
S={(s['seg'],s['name']):s for s in secs}
def off_of(a): return a-0x100000000
def rd_str(a):
    o=off_of(a)
    if o<0 or o>=N: return None
    e=d.find(b'\0',o)
    if e<0 or e-o>400: return None
    try: return d[o:e].decode('utf-8')
    except: return None
def rel_ptr(base_addr, field_off):
    v=struct.unpack_from('<i',d,off_of(base_addr)+field_off)[0]
    return base_addr+field_off+v

typ=S[('__TEXT','__swift5_types')]
fmd=S[('__TEXT','__swift5_fieldmd')]
fm_lo,fm_hi=fmd['addr'],fmd['addr']+fmd['size']

def type_desc(i):
    rel=struct.unpack_from('<i',d,typ['off']+i*4)[0]
    return typ['addr']+i*4+rel

def desc_name(a):
    p=rel_ptr(a,8)
    return rd_str(p) if p else None

def parent_desc(a):
    try: return rel_ptr(a,4)
    except: return 0

def fields_of(a):
    fd=rel_ptr(a,16)
    if not (fm_lo<=fd<fm_hi): return None
    fo=off_of(fd)
    kind,recsize,numf=struct.unpack_from('<HHI',d,fo+8)
    if not(0<recsize<=32 and 0<=numf<400): return None
    out=[];p=fo+16
    for k in range(numf):
        rmang=struct.unpack_from('<i',d,p+4)[0]
        rfname=struct.unpack_from('<i',d,p+8)[0]
        fname=rd_str(fd+(p-fo)+8+rfname)
        mname=rd_str(fd+(p-fo)+4+rmang)
        out.append(dict(name=fname,mangled=mname))
        p+=recsize
    return out

types=[]
for i in range(typ['size']//4):
    try:
        a=type_desc(i)
        n=desc_name(a)
        if not n: continue
        par=parent_desc(a)
        pn=None
        if par and 0x100000000<=par<0x102000000:
            pn=desc_name(par)
        types.append(dict(idx=i,addr=a,name=n,parent=pn,kind=struct.unpack_from('<I',d,off_of(a))[0]&0x1f,fields=fields_of(a)))
    except Exception:
        pass

print('types',len(types))
gv=[t for t in types if (t['name'] or '').startswith('GvPb_')]
print('gv',len(gv),'storage',sum(1 for t in gv if t['name']=='StorageClass'))
json.dump(types,open('/home/ubuntu/uuyc_clone/analysis/derived/swift_types.json','w'))
for t in gv[:6]: print(t['name'],t['parent'],t['kind'],len(t['fields'] or []))
