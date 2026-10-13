#!/usr/bin/env python3
"""Fail-closed raw emulator PNG oracle; stdlib only, exact authored tile masks."""
import argparse,importlib.util,json,struct,zlib
from pathlib import Path
spec=importlib.util.spec_from_file_location('fixture',Path(__file__).with_name('build_fixture.py')); fixture=importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
def decode(path):
    b=path.read_bytes(); assert b[:8]==b'\x89PNG\r\n\x1a\n'; at=8; compressed=b''
    while at<len(b):
        n=struct.unpack('>I',b[at:at+4])[0]; kind=b[at+4:at+8]; data=b[at+8:at+8+n]; crc=struct.unpack('>I',b[at+8+n:at+12+n])[0]
        assert zlib.crc32(kind+data)&0xFFFFFFFF==crc,'PNG CRC mismatch'
        if kind==b'IHDR': w,h,depth,color,comp,filt,inter=struct.unpack('>IIBBBBB',data)
        if kind==b'IDAT': compressed+=data
        at+=n+12
    assert (w,h,depth,color,comp,filt,inter)==(160,144,8,2,0,0,0),'unexpected PNG format'
    raw=zlib.decompress(compressed); stride=w*3; prior=[0]*stride; rows=[]; at=0
    def paeth(a,b,c):
        p=a+b-c; ds=[abs(p-a),abs(p-b),abs(p-c)]; return [a,b,c][ds.index(min(ds))]
    for _ in range(h):
        f=raw[at]; at+=1; row=list(raw[at:at+stride]); at+=stride; assert f<=4
        for x in range(stride):
            left=row[x-3] if x>=3 else 0; above=prior[x]; ul=prior[x-3] if x>=3 else 0
            row[x]=(row[x]+[0,left,above,(left+above)//2,paeth(left,above,ul)][f])&255
        rows.append([tuple(row[x:x+3]) for x in range(0,stride,3)]); prior=row
    assert at==len(raw); return rows
def verify(path,system,counter,require_color=True):
    pixels=decode(path); expected=[[False]*160 for _ in range(144)]
    for row,text in [(2,'PLAYSTEAD'),(4,system.upper()),(6,'SAVE'),(8,f'{counter:02X}'),(10,'A SAVE')]:
        for col,ch in enumerate(text,2):
            for y,line in enumerate(fixture.FONT[ch]):
                for x,v in enumerate(line): expected[row*8+y][col*8+x+1]=v=='1'
    actual=[[min(rgb)<200 for rgb in row] for row in pixels]
    mismatch=sum(a!=e for ar,er in zip(actual,expected) for a,e in zip(ar,er)); assert mismatch==0,f'wrong rendered screen: {mismatch} pixels differ'
    colors={rgb for row in pixels for rgb in row}; red=any(r>g+100 and r>b+100 for r,g,b in colors)
    if system=='gbc' and require_color: assert red,'GBC fixture failed to render its red palette'
    return dict(file=path.name,system=system,counter=counter,matched_pixels=160*144,color_verified=red,colors=len(colors))
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('png',type=Path); p.add_argument('system',choices=['gb','gbc']); p.add_argument('counter',type=lambda x:int(x,0)); p.add_argument('--legacy-monochrome',action='store_true'); a=p.parse_args(); print(json.dumps(verify(a.png,a.system,a.counter,not a.legacy_monochrome)))
