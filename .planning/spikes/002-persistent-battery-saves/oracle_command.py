#!/usr/bin/env python3
"""Generate a bounded Lua command for the *shipped* mGBA scripting console.

Observe RAM and screenshot; drive one A-button edge through emulator input API.
Never write game memory/save bytes. Run through the console with computer use.
"""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('case'); p.add_argument('label'); p.add_argument('--observe-only',action='store_true'); p.add_argument('--frames',type=int,default=20); args=p.parse_args()
assert args.frames>=2
root=Path(__file__).resolve().parents[3]/'playstead-mac/.local/gb-gbc-spike'/args.case
base=str(root/'screenshots'/args.label); oracle=str(root/(args.label+'-oracle.json'))
before=f'local initial=emu:read8(0xC000); emu:screenshot({json.dumps(base+"-before.png")}); '
output='local f=assert(io.open('+json.dumps(oracle)+',"w")); f:write(string.format(\'{"before":%d,"after":%d,"input_edges":%d,"platform":%d}\\n\',initial,emu:read8(0xC000),'+('0' if args.observe_only else '1')+',emu:platform())); f:close(); console:log("ORACLE '+args.label+' before="..initial.." after="..emu:read8(0xC000)); emu:screenshot('+json.dumps(base+'-after.png')+'); '
if args.observe_only: command=before+output
else: command=before+'local n=0; local cb; cb=callbacks:add("frame",function() n=n+1; if n==1 then emu:addKey(0) elseif n=='+str(min(10,args.frames))+' then emu:clearKey(0) end; if n=='+str(args.frames)+' then '+output+'callbacks:remove(cb) end end)'
print(command)
