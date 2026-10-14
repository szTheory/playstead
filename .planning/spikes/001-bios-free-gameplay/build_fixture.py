#!/usr/bin/env python3
"""Self-authored GB/GBC battery-counter homebrew, no external assembler/ROM/BIOS.

The standard cartridge recognition logo bytes are format metadata only. All
executable code, font pixels and game behavior below are authored for this spike.
Boot reads a counter; only a new A-button edge changes battery bytes. Thus loading
cannot manufacture a persistence pass by overwriting the save on startup.
"""
from pathlib import Path
import argparse, hashlib, json

FONT = {
' ': ['00000']*7,
'0':['01110','10001','10011','10101','11001','10001','01110'],
'1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','10001','00001','00010','00100','01000','11111'],
'3':['11110','00001','00001','01110','00001','00001','11110'],
'4':['00010','00110','01010','10010','11111','00010','00010'],
'5':['11111','10000','10000','11110','00001','00001','11110'],
'6':['01110','10000','10000','11110','10001','10001','01110'],
'7':['11111','00001','00010','00100','01000','01000','01000'],
'8':['01110','10001','10001','01110','10001','10001','01110'],
'9':['01110','10001','10001','01111','00001','00001','01110'],
'A':['01110','10001','10001','11111','10001','10001','10001'],
'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'],
'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'],
'F':['11111','10000','10000','11110','10000','10000','10000'],
'G':['01111','10000','10000','10111','10001','10001','01111'],
'I':['01110','00100','00100','00100','00100','00100','01110'],
'L':['10000','10000','10000','10000','10000','10000','11111'],
'M':['10001','11011','10101','10101','10001','10001','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'],
'P':['11110','10001','10001','11110','10000','10000','10000'],
'R':['11110','10001','10001','11110','10100','10010','10001'],
'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'V':['10001','10001','10001','10001','10001','01010','00100'],
'Y':['10001','10001','01010','00100','00100','00100','00100'],
}
CHARS=list(FONT)

class ASM:
    def __init__(self): self.code=bytearray(); self.labels={}; self.refs=[]
    def emit(self,*bs): self.code.extend(bs)
    def word(self,v): self.emit(v&255,v>>8)
    def label(self,n): self.labels[n]=0x150+len(self.code)
    def ld(self,addr): self.emit(0xFA); self.word(addr)
    def store(self,addr): self.emit(0xEA); self.word(addr)
    def a(self,v): self.emit(0x3E,v)
    def jump(self,n,op=0xC3):
        self.emit(op); self.refs.append((len(self.code),n)); self.word(0)
    def finish(self):
        for at,n in self.refs:
            v=self.labels[n]; self.code[at:at+2]=v.to_bytes(2,'little')
        return self.code

def fixture(name,cgb,cart,ram):
    a=ASM(); a.emit(0xF3,0x31,0xFE,0xFF) # DI; SP=$FFFE
    a.label('vblank'); a.emit(0xF0,0x44,0xFE,144); a.jump('vblank',0xDA)
    a.emit(0xAF,0xE0,0x40,0xE0,0x42,0xE0,0x43) # LCD off, scroll zero
    a.a(0xE4); a.emit(0xE0,0x47)
    if cgb:
        a.a(0x80); a.emit(0xE0,0x68)
        for v in bytes.fromhex('ff7f001c000c1f00'):
            a.a(v); a.emit(0xE0,0x69)
    a.a(0x0A); a.store(0x0000) # enable cartridge RAM
    a.emit(0xAF); a.store(0xC000); a.store(0xC001) # counter, prior input
    a.ld(0xA000); a.emit(0xFE,0x50); a.jump('tiles',0xC2)
    a.ld(0xA002); a.emit(0xFE,0x53); a.jump('tiles',0xC2)
    a.ld(0xA001); a.store(0xC000)
    a.label('tiles'); a.emit(0x21); a.refs.append((len(a.code),'font')); a.word(0)
    a.emit(0x11); a.word(0x8000); a.emit(0x01); a.word(len(CHARS)*16)
    a.label('copy'); a.emit(0x2A,0x12,0x13,0x0B,0x78,0xB1); a.jump('copy',0xC2)
    a.emit(0x21); a.word(0x9800); a.emit(0x01); a.word(1024)
    a.label('clear'); a.emit(0xAF,0x22,0x0B,0x78,0xB1); a.jump('clear',0xC2)
    for row,text in [(2,'PLAYSTEAD'),(4,'GBC' if cgb else 'GB'),(6,'SAVE'),(10,'A SAVE')]:
        for col,ch in enumerate(text,2): a.a(CHARS.index(ch)); a.store(0x9800+row*32+col)
    a.jump('display',0xCD); a.a(0x91); a.emit(0xE0,0x40)
    a.label('loop') # poll continuously; short synthesized presses must not miss VBlank
    a.a(0x10); a.emit(0xE0,0x00,0xF0,0x00,0xF0,0x00,0x2F,0xE6,1,0x47)
    a.ld(0xC001); a.emit(0xB8); a.jump('loop',0xCA)
    a.emit(0x78); a.store(0xC001); a.emit(0xA7); a.jump('loop',0xCA)
    a.ld(0xC000); a.emit(0x3C); a.store(0xC000); a.store(0xA001)
    a.a(0x50); a.store(0xA000); a.a(0x53); a.store(0xA002)
    a.label('draw_wait'); a.emit(0xF0,0x44,0xFE,144); a.jump('draw_wait',0xDA)
    a.jump('display',0xCD); a.jump('loop')
    a.label('display'); a.ld(0xC000); a.emit(0xCB,0x37,0xE6,15,0xC6,1); a.store(0x9902)
    a.ld(0xC000); a.emit(0xE6,15,0xC6,1); a.store(0x9903); a.emit(0xC9)
    a.label('font')
    for rows in FONT.values():
        for row in rows+['00000']:
            v=int(row,2)<<2; a.emit(v,v)
    rom=bytearray(32768); rom[0x100:0x104]=bytes([0,0xC3,0x50,0x01])
    rom[0x104:0x134]=bytes.fromhex('ce ed 66 66 cc 0d 00 0b 03 73 00 83 00 0c 00 0d 00 08 11 1f 88 89 00 0e dc cc 6e e6 dd dd d9 99 bb bb 67 63 6e 0e ec cc dd dc 99 9f bb b9 33 3e')
    title=name.upper().encode()[:15]; rom[0x134:0x134+len(title)]=title
    rom[0x143]=0xC0 if cgb else 0; rom[0x147]=cart; rom[0x148]=0; rom[0x149]=ram
    rom[0x14A]=1; rom[0x14D]=(-sum(rom[0x134:0x14D])-25)&255
    code=a.finish(); rom[0x150:0x150+len(code)]=code
    total=sum(rom)&0xFFFF; rom[0x14E:0x150]=total.to_bytes(2,'big')
    return rom

def main():
    p=argparse.ArgumentParser(); p.add_argument('--out',type=Path,required=True); args=p.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    cases=[('gb-mbc1-8k',False,0x03,2,8192),('gbc-mbc5-32k',True,0x1B,3,32768),('gbc-mbc3-rtc',True,0x10,3,32768)]
    registry=[]
    for name,cgb,cart,ram,save in cases:
        data=fixture(name,cgb,cart,ram); path=args.out/(name+('.gbc' if cgb else '.gb')); path.write_bytes(data)
        registry.append(dict(name=name,system='gbc' if cgb else 'gb',cartridge_type=cart,sram_bytes=save,rtc=cart==0x10,path=str(path.resolve()),sha256=hashlib.sha256(data).hexdigest()))
    (args.out/'fixtures.json').write_text(json.dumps(registry,indent=2)+'\n')
    print(json.dumps({'authored_fixtures':len(registry),'output':str(args.out),'startup_writes_battery':False}))
if __name__=='__main__': main()
