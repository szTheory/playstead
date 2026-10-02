#!/usr/bin/env python3
"""Hostile continuation protocol tests with isolated process doubles.

Only the test process monkeypatches IsolationRunner/bounded_run. No real
containment boundary, fixture payload, emulator, or test bypass is activated.
"""
import contextlib, importlib.util, io, json, os, subprocess, sys, tempfile, time, uuid
from pathlib import Path

CI = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("continuation_protocol", CI / "continuation_protocol.py")
protocol = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = protocol
spec.loader.exec_module(protocol)

def uid(): return str(uuid.uuid4())
def check(value, message):
    if not value: raise AssertionError(message)
def refused(fn, label):
    try: fn()
    except (protocol.Refused, ValueError, TypeError, OSError): return
    raise AssertionError(label + " unexpectedly passed")
def contract():
    return {"schema":"local-continuation-contract-v1","contract_id":uid(),"fixture_id":uid(),
            "adapter_protocol":protocol.PROTOCOL,"same_host_required":True,
            "network_required":"enforced-deny","required_actions":list(protocol.ACTIONS),
            "oracle_requirement":"repeatable-visible-state"}
def receipt():
    return {"schema":"playstead.recovery-e2e-local.v1","run_id":uid(),
            "lane":"same_host_restored_target","stage":"complete","outcome":"passed"}
def qualification(c):
    return {"schema":"local-continuation-qualification-v1","contract_id":c["contract_id"],
            "adapter_protocol":protocol.PROTOCOL,"outcome":"qualified",
            "capabilities":{"initial_run":True,"safe_exit":True,"fresh_process":True,"continue":True,
                            "repeatable_visible_oracle":True,"repeat_count":2,"oracle_agreement":True}}
def action(c, kind, **updates):
    result={"schema":"local-continuation-action-v1","contract_id":c["contract_id"],
            "adapter_protocol":protocol.PROTOCOL,"outcome":"passed","child_id":uid()}
    if kind=="initial-run": result.update(save_transition=True,safe_exit=True)
    else: result.update(fresh_process=True,continue_complete=True,oracle_agreement=True,repeat_count=2)
    result.update(updates)
    return result

class FakeRunner:
    events=[]
    mode="pass"
    current_contract=None
    first_id=None
    action_roots=[]
    def __init__(self, selector):
        check(selector=="macos-seatbelt-v1","bad selector reached fake runner")
        self.events=type(self).events
        self.events.append("construct")
    def probe(self):
        self.events.append("probe")
        if type(self).mode=="network-allowed": raise protocol.Refused()
    def run(self, action_name, adapter_path, root):
        self.probe()
        check(Path(adapter_path).is_file(),"adapter boundary missing")
        check(Path(root).is_dir(),"private root missing")
        self.events.append(action_name)
        mode=type(self).mode; c=type(self).current_contract
        if action_name=="qualify":
            if mode=="dirty-qualify": (Path(root)/"persistent-save").mkdir()
            result=qualification(c)
            if mode=="unqualified": result["outcome"]="blocked-capability"
            return json.dumps(result).encode()
        type(self).action_roots.append((action_name, str(root)))
        if action_name=="initial-run":
            (Path(root)/"persistent-save"/"save.bin").write_bytes(b"test-double")
            result=action(c,action_name)
            if mode=="bad-save": result["save_transition"]=False
            if mode=="unsafe-exit": result["safe_exit"]=False
            if mode=="extra-key": result["private"]="reject"
            if mode=="reused-id": type(self).first_id=result["child_id"]
            if mode=="timeout": raise TimeoutError()
            if mode=="stale-child": raise protocol.Refused()
            if mode=="process-failure": raise subprocess.CalledProcessError(65,["test-double"])
            return json.dumps(result).encode()
        result=action(c,action_name)
        if mode=="reused-id": result["child_id"]=type(self).first_id
        if mode=="fresh-process": result["fresh_process"]=False
        if mode=="continue-incomplete": result["continue_complete"]=False
        if mode=="oracle-disagreement": result["oracle_agreement"]=False
        if mode=="oracle-repeat-one": result["repeat_count"]=1
        if mode=="extra-key": result["private"]="reject"
        return json.dumps(result).encode()

def run_execute(directory, mode="pass", *, c=None, r=None, fixture=True,
                qualify_only=False, forbid_fixture_lookup=False):
    c=c or contract(); r=r or receipt()
    cpath=directory/"contract.json"; rpath=directory/"receipt.json"
    adapter_path=directory/"adapter"; fpath=directory/"fixture.bin"
    cpath.write_text(json.dumps(c)); rpath.write_text(json.dumps(r))
    cpath.chmod(0o600); rpath.chmod(0o600)
    check(cpath.is_absolute() and cpath.resolve(strict=True)==cpath,"test contract path is not canonical absolute")
    adapter_path.write_text("#!/bin/sh\nexit 0\n"); adapter_path.chmod(0o700)
    fpath.write_bytes(b"fixture content remains unread by repository code"); fpath.chmod(0o600)
    env={"PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM":"macos-seatbelt-v1",
         "PLAYSTEAD_CONTINUATION_CONTRACT":str(cpath),"PLAYSTEAD_RECOVERY_E2E_RECEIPT":str(rpath),
         "PLAYSTEAD_CONTINUATION_ADAPTER":str(adapter_path),
         "PLAYSTEAD_CONTINUATION_FIXTURE":str(fpath if fixture else directory/"missing-fixture")}
    if forbid_fixture_lookup:
        class FixtureLookupForbidden(dict):
            def get(self, key, default=None):
                if key == "PLAYSTEAD_CONTINUATION_FIXTURE":
                    raise AssertionError("qualification-only read fixture environment")
                return super().get(key, default)
        env=FixtureLookupForbidden(env)
    FakeRunner.events=[]; FakeRunner.mode=mode; FakeRunner.current_contract=c; FakeRunner.action_roots=[]
    old=protocol.IsolationRunner; protocol.IsolationRunner=FakeRunner
    old_local=protocol.local_file
    def observed_local_file(value, **kwargs):
        if str(value)==str(fpath if fixture else directory/"missing-fixture"):
            FakeRunner.events.append("fixture-stat")
        return old_local(value, **kwargs)
    protocol.local_file=observed_local_file
    try: result=protocol.execute(env,qualify_only=qualify_only)
    finally:
        protocol.IsolationRunner=old
        protocol.local_file=old_local
    return result,FakeRunner.events,fpath

def main():
  with tempfile.TemporaryDirectory(prefix="continuation-protocol-test.") as tmp:
    d=Path(tmp).resolve(); d.chmod(0o700)
    c=contract()
    protocol.validate_contract(c); protocol.validate_receipt(receipt())
    for field in ("contract_id","fixture_id"):
        invalid=dict(c); invalid[field]="opaque"
        refused(lambda x=invalid: protocol.validate_contract(x),"non-UUID "+field)
    extra=dict(c); extra["private"]="reject"
    refused(lambda: protocol.validate_contract(extra),"extra contract key")
    dup=d/"duplicate.json"; dup.write_text('{"schema":"one","schema":"two"}'); dup.chmod(0o600)
    refused(lambda: protocol.strict_json(dup),"duplicate key")
    large=d/"large.json"; large.write_bytes(b"{"+b" "*65536+b"}"); large.chmod(0o600)
    refused(lambda: protocol.strict_json(large),"oversized JSON")
    link=d/"link.json"; link.symlink_to(dup)
    refused(lambda: protocol.strict_json(link),"symlinked contract")
    badreceipt=receipt(); badreceipt["private"]="reject"
    refused(lambda: protocol.validate_receipt(badreceipt),"receipt extra key")

    q=qualification(c); protocol.validate_qualification(q,c["contract_id"])
    for badq in (dict(q,private="reject"),dict(q,outcome="blocked-capability"),
                 dict(q,isolation_attestation=True)):
        refused(lambda x=badq: protocol.validate_qualification(x,c["contract_id"]),"qualification shape")
    badq=qualification(c); badq["capabilities"]["repeat_count"]=1
    refused(lambda: protocol.validate_qualification(badq,c["contract_id"]),"single oracle")
    initial=action(c,"initial-run"); protocol.validate_action(initial,c["contract_id"],"initial-run")
    for field,stage in (("save_transition","initial-save"),("safe_exit","safe-exit")):
        bad=dict(initial); bad[field]=False
        try: protocol.validate_action(bad,c["contract_id"],"initial-run")
        except protocol.LifecycleFailure as error: check(error.stage==stage,"wrong initial failure stage")
        else: raise AssertionError(field+" failure passed")
    for field,stage in (("fresh_process","fresh-launch"),("continue_complete","continue"),
                        ("oracle_agreement","oracle")):
        bad=action(c,"continue"); bad[field]=False
        try: protocol.validate_action(bad,c["contract_id"],"continue")
        except protocol.LifecycleFailure as error: check(error.stage==stage,"wrong continue failure stage")
        else: raise AssertionError(field+" failure passed")
    refused(lambda: protocol.validate_action(dict(initial,child_id="not-uuid"),c["contract_id"],"initial-run"),
            "non-UUID child id")
    refused(lambda: protocol.validate_action(dict(initial,private="reject"),c["contract_id"],"initial-run"),
            "extra action key")
    refused(lambda: protocol.validate_action(initial,c["contract_id"],"qualification"),
            "unknown action token")

    result,events,_=run_execute(d)
    check(events != ["construct"], "preflight stopped before probe; files/modes may be invalid")
    check(result==("oracle","passed",0),"success double did not pass: "+repr(result)+" events="+repr(events))
    check(events==["construct","probe","probe","qualify","fixture-stat",
                   "probe","initial-run","probe","continue",
                   "probe","initial-run","probe","continue"],
          "per-action probe ordering wrong: "+repr(events))
    roots=[root for _action,root in FakeRunner.action_roots]
    check(len(roots)==4 and roots[0]==roots[1] and roots[2]==roots[3] and roots[0]!=roots[2],
          "fixture repetitions did not use two independent save roots")
    result,events,_=run_execute(d,qualify_only=True,forbid_fixture_lookup=True)
    check(result==("qualification","qualified-only",0),
          "synthetic-only qualification did not return its distinct pass: "+repr(result))
    check(events==["construct","probe","probe","qualify"],
          "qualification-only resolved fixture metadata or launched a lifecycle action: "+repr(events))
    result,events,_=run_execute(d,mode="dirty-qualify",qualify_only=True,forbid_fixture_lookup=True)
    check(result==("qualification","blocked-capability",77) and events==["construct","probe","probe","qualify"],
          "qualification accepted a non-empty owned root or continued into fixture work")
    badc=contract(); badc["contract_id"]="bad"
    result,events,_=run_execute(d,c=badc)
    check(result[1:]==("blocked-capability",77) and events==["construct"],"bad metadata reached adapter")
    badr=receipt(); badr["outcome"]="blocked"
    result,events,_=run_execute(d,r=badr)
    check(result[1:]==("blocked-capability",77) and events==["construct"],"bad receipt reached adapter")
    result,events,_=run_execute(d,mode="unqualified",fixture=False)
    check(result[1:]==("blocked-capability",77) and events[-2:]==["probe","qualify"],
          "unqualified adapter resolved fixture or launched lifecycle")
    result,events,_=run_execute(d,fixture=False)
    check(result[1:]==("blocked-capability",77) and events[-3:]==["probe","qualify","fixture-stat"],
          "missing fixture launched lifecycle")
    check(events.index("fixture-stat") > events.index("qualify"),"fixture path resolved before qualification")
    result,events,_=run_execute(d,mode="dirty-qualify")
    check(result[1:]==("blocked-capability",77) and events[-2:]==["probe","qualify"],
          "dirty qualification root was accepted")
    expected={"bad-save":"initial-save","unsafe-exit":"safe-exit","fresh-process":"fresh-launch",
              "continue-incomplete":"continue","oracle-disagreement":"oracle","oracle-repeat-one":"oracle",
              "reused-id":"fresh-launch","extra-key":"initial-save","timeout":"initial-save",
              "stale-child":"initial-save","process-failure":"initial-save"}
    for mode,stage in expected.items():
        result,_,_=run_execute(d,mode)
        check(result==(stage,"failed-stage",1),"bad failure mapping "+mode+": "+repr(result))
    result,events,_=run_execute(d,mode="network-allowed")
    check(result==("preflight","blocked-capability",77) and events==["construct","probe"],
          "network-allowed probe passed or reached fixture")

    # Verify real bounded_run scrubs the environment and kills a same-group
    # child after timeout; neither this nor the doubles launch an emulator.
    marker=d/"late-marker"
    code=("import subprocess,time; subprocess.Popen(['/usr/bin/python3','-c',"
          +repr("import time,pathlib; time.sleep(.5); pathlib.Path("+repr(str(marker))+").write_text('late')")+"]); time.sleep(10)")
    try: protocol.bounded_run(["/usr/bin/python3","-c",code],timeout=.1,cwd=d)
    except (protocol.Refused,subprocess.SubprocessError,TimeoutError): pass
    else: raise AssertionError("bounded_run did not stop timed-out child")
    time.sleep(.6); check(not marker.exists(),"timeout left stale child")
    # The child process environment contains only the fixed PATH; its cwd is
    # the owned root and argv contains only the approved action token.
    env_probe=d/"boundary-probe"
    env_probe.write_text("#!/usr/bin/python3\nimport json,os,sys; print(json.dumps({'cwd':os.getcwd(),'env':dict(os.environ),'argv':sys.argv[1:]}))\n")
    env_probe.chmod(0o700)
    owned=d/"playstead-continuation.env"; owned.mkdir(mode=0o700)
    old_secret=os.environ.get("PRIVATE_TEST_TOKEN")
    os.environ["PRIVATE_TEST_TOKEN"]="must-not-propagate"
    try: status,raw=protocol.bounded_run([str(env_probe),"continue"],timeout=2,cwd=owned)
    finally:
        if old_secret is None: os.environ.pop("PRIVATE_TEST_TOKEN",None)
        else: os.environ["PRIVATE_TEST_TOKEN"]=old_secret
    observed=json.loads(raw)
    keys=set(observed["env"])
    forbidden={"HOME","PRIVATE_TEST_TOKEN","HTTP_PROXY","HTTPS_PROXY","ALL_PROXY",
               "PLAYSTEAD_CONTINUATION_CONTRACT","PLAYSTEAD_CONTINUATION_FIXTURE",
               "PLAYSTEAD_CONTINUATION_ADAPTER","PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM"}
    check(status==0 and observed["env"].get("PATH")==protocol.CLEAN_ENV["PATH"] and not (keys & forbidden),
          "child environment retained private inputs or credentials")
    check(observed["cwd"]==str(owned) and observed["argv"]==["continue"],"child cwd or argv leaked private inputs")
    # Direct adapter invocation test uses a monkeypatched process boundary.
    runner=object.__new__(protocol.IsolationRunner); runner.selector="macos-seatbelt-v1"
    runner.boundary=["/usr/bin/sandbox-exec","-p","fixed"]
    adapter_path=d/"adapter"; adapter_path.write_text("#!/bin/sh\n"); adapter_path.chmod(0o700)
    frontend_path=d/"continuation-libretro-frontend"
    frontend_path.write_text("#!/bin/sh\nexit 0\n"); frontend_path.chmod(0o700)
    fixture_frontend_path=d/"continuation-fixture-libretro-frontend"
    fixture_frontend_path.write_text("#!/bin/sh\nexit 0\n"); fixture_frontend_path.chmod(0o700)
    working=d/"playstead-continuation.runner"; working.mkdir(mode=0o700)
    calls=[]; real_bounded=protocol.bounded_run
    def fake_bounded(command,*,timeout,cwd=None):
        calls.append((command,timeout,cwd))
        return (77,b"") if len(calls)==1 else (0,b"{}")
    protocol.bounded_run=fake_bounded
    try: protocol.IsolationRunner.run(runner,"initial-run",adapter_path,working)
    finally: protocol.bounded_run=real_bounded
    check(len(calls)==2 and calls[0][1]==5,"action skipped fixed denied-network probe")
    command,timeout,cwd=calls[1]
    check(command[-2:]==[str(adapter_path),"initial-run"],"adapter received more than exact action token")
    child_argv=command[-2:]
    check(command[0]==runner.boundary[0] and "fixture" not in " ".join(child_argv) and
          "contract" not in " ".join(child_argv),"runner passed private path material to adapter argv")
    profile=command[command.index("-p")+1]
    expected_execs={str(path) for path in protocol.macos_exec_allowlist(
        adapter_path,[frontend_path,fixture_frontend_path])}
    check('(deny process-exec)' in profile and
          all('(allow process-exec (literal "'+path+'"))' in profile for path in expected_execs) and
          "(allow process-fork)" in profile and
          'process-exec (literal "/bin/date")' not in profile and
          "process-exec*" not in profile,
          "macOS boundary did not deny unlisted child execution and allow only exact required executables")
    check(str(frontend_path) in profile and str(fixture_frontend_path) in profile,
          "macOS boundary did not bind both frontend exceptions to validated adjacent binaries")
    check(timeout==120 and cwd==working,"runner did not bind child to bounded private cwd")

    # Linux runner uses only the parent-owned network/PID namespace flags and
    # binds the one owned child root; neither selector is caller-supplied argv.
    linux=object.__new__(protocol.IsolationRunner); linux.selector="linux-bwrap-v1"
    linux.boundary=["/usr/bin/bwrap","--unshare-net","--unshare-pid","--die-with-parent",
                    "--new-session","--ro-bind","/","/","--proc","/proc","--dev","/dev"]
    calls=[]
    def fake_linux(command,*,timeout,cwd=None):
        calls.append((command,timeout,cwd)); return (77,b"") if len(calls)==1 else (0,b"{}")
    protocol.bounded_run=fake_linux
    try: protocol.IsolationRunner.run(linux,"continue",adapter_path,working)
    finally: protocol.bounded_run=real_bounded
    command,timeout,cwd=calls[1]
    offset=len(linux.boundary)
    check(command[:offset]==linux.boundary and
          command[offset:offset+3]==["--bind",str(working),str(working)],
          "Linux containment namespace/root binding was not fixed")
    check(command[-2:]==[str(adapter_path),"continue"] and timeout==120 and cwd==working,
          "Linux adapter action boundary was malformed")

    # Unsupported platform and absent mechanism executable fail closed.
    real_system=protocol.platform.system; real_access=protocol.os.access
    try:
        protocol.platform.system=lambda: "Windows"
        refused(lambda: protocol.IsolationRunner("macos-seatbelt-v1"),"wrong-host selector")
        protocol.platform.system=lambda: "Darwin"
        protocol.os.access=lambda path,*args,**kwargs: False if path=="/usr/bin/sandbox-exec" else real_access(path,*args,**kwargs)
        refused(lambda: protocol.IsolationRunner("macos-seatbelt-v1"),"missing fixed executable")
    finally:
        protocol.platform.system=real_system; protocol.os.access=real_access

    # A contained child that connects successfully, exits incorrectly, or
    # writes unexpected probe output cannot qualify the parent boundary.
    for status,raw in ((0,b""),(2,b""),(77,b"unexpected")):
        def bad_probe(command,*,timeout,cwd=None,s=status,o=raw): return s,o
        protocol.bounded_run=bad_probe
        try: refused(lambda: protocol.IsolationRunner.probe(runner),"invalid probe result")
        finally: protocol.bounded_run=real_bounded

    # The optional coordinator tail emits only the child receipt and propagates
    # its exit status; it cannot print a prior recovery pass on child refusal.
    coordinator=(CI/"recovery-e2e.sh").read_text(encoding="utf-8")
    start=coordinator.index('recovery_result="$(emit_local_receipt complete passed)"')
    with tempfile.TemporaryDirectory(prefix="continuation-coordinator-double.") as tail_tmp:
        td=Path(tail_tmp).resolve(); (td/"bin").mkdir()
        tail=coordinator[start:]
        harness=('#!/usr/bin/env bash\nset -euo pipefail\nSCRIPT_DIR='+repr(str(td))+"\n"
                 'private_root='+repr(str(td))+"\nRUN_ID='"+uid()+"'\n"
                 'emit_local_receipt(){ printf \'%s\\n\' \'{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"complete","outcome":"passed"}\'; }\n'
                 +tail)
        (td/"coordinator-tail.sh").write_text(harness,encoding="utf-8"); (td/"coordinator-tail.sh").chmod(0o700)
        for code,status,wanted in (("blocked-capability",77,77),("passed",0,0)):
            child=td/"continuation-spike.sh"
            child.write_text("#!/usr/bin/env bash\nprintf '%s\\n' '{\"schema\":\"playstead.continuation-local.v1\",\"run_id\":\"123e4567-e89b-42d3-a456-426614174000\",\"stage\":\""+(
                "preflight\" ,\"outcome\":\"blocked-capability" if code=="blocked-capability" else "oracle\",\"outcome\":\"passed")+"\"}'\nexit "+str(status)+"\n",encoding="utf-8")
            child.chmod(0o700)
            ran=subprocess.run([str(td/"coordinator-tail.sh")],env={**os.environ,"PLAYSTEAD_CONTINUATION_RUN":"1"},
                               capture_output=True,text=True,timeout=5)
            check(ran.returncode==wanted,"optional coordinator did not propagate child status")
            check("playstead.recovery-e2e-local.v1" not in ran.stdout and
                  '"schema":"playstead.continuation-local.v1"' in ran.stdout,
                  "optional coordinator printed/promoted recovery success before child result")

    # The real sanitizer preserves an oracle failure as a reduced receipt too.
    failed_output=io.StringIO()
    with contextlib.redirect_stdout(failed_output): protocol.emit("oracle","failed-stage")
    failed=json.loads(failed_output.getvalue())
    check(set(failed)=={"schema","run_id","stage","outcome"} and
          failed["stage"]=="oracle" and failed["outcome"]=="failed-stage",
          "sanitizer dropped the real oracle failure stage")

    # The real sanitizer accepts only the reduced pass and emits no added fields.
    good_output=io.StringIO()
    with contextlib.redirect_stdout(good_output): protocol.emit("oracle","passed")
    emitted=json.loads(good_output.getvalue())
    check(set(emitted)=={"schema","run_id","stage","outcome"} and
          emitted["stage"]=="oracle" and emitted["outcome"]=="passed",
          "sanitizer-approved pass emitted non-public fields")
    qualified_output=io.StringIO()
    with contextlib.redirect_stdout(qualified_output): protocol.emit("qualification","qualified-only")
    qualified=json.loads(qualified_output.getvalue())
    check(set(qualified)=={"schema","run_id","stage","outcome"} and
          qualified["stage"]=="qualification" and qualified["outcome"]=="qualified-only",
          "sanitizer-approved synthetic-only qualification emitted non-public fields")
    # Sanitizer failure must suppress receipt output.
    real_subprocess_run=protocol.subprocess.run
    protocol.subprocess.run=lambda *a,**k: subprocess.CompletedProcess(a[0],1)
    output=io.StringIO()
    try:
        try:
            with contextlib.redirect_stdout(output): protocol.emit("oracle","passed")
        except protocol.Refused: pass
        else: raise AssertionError("sanitizer failure accepted")
    finally: protocol.subprocess.run=real_subprocess_run
    check(output.getvalue()=="","sanitizer failure emitted a receipt")
  print("continuation protocol process-double corpus passed")

if __name__=="__main__": main()
