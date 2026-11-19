import struct, sys

LC_SEGMENT_64=0x19
def parse(path):
    d=open(path,'rb').read()
    magic=struct.unpack_from('<I',d,0)[0]
    assert magic==0xfeedfacf, hex(magic)
    ncmds=struct.unpack_from('<I',d,16)[0]
    off=32; segs=[]; secs=[]
    for _ in range(ncmds):
        cmd,size=struct.unpack_from('<II',d,off)
        if cmd==LC_SEGMENT_64:
            segname=d[off+8:off+24].split(b'\0')[0].decode()
            vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',d,off+24)
            nsects=struct.unpack_from('<I',d,off+64)[0]
            so=off+72
            for i in range(nsects):
                sname=d[so:so+16].split(b'\0')[0].decode()
                sseg=d[so+16:so+32].split(b'\0')[0].decode()
                addr,sz=struct.unpack_from('<QQ',d,so+32)
                foff=struct.unpack_from('<I',d,so+48)[0]
                flags,=struct.unpack_from('<I',d,so+64)
                secs.append(dict(seg=sseg,name=sname,addr=addr,size=sz,off=foff,flags=flags))
                so+=80
            segs.append(dict(name=segname,vmaddr=vmaddr,vmsize=vmsize,off=fileoff,size=filesize))
        off+=size
    return d,segs,secs

if __name__=='__main__':
    d,segs,secs=parse(sys.argv[1])
    print('segments:')
    for s in segs: print(' ',s)
    print('sections:')
    for s in secs: print(f"  {s['seg']},{s['name']} off={s['off']:#x} size={s['size']:#x} addr={s['addr']:#x}")
