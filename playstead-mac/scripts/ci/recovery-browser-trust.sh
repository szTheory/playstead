#!/usr/bin/env bash
# Prepare browser trust for one validated, retained recovery target.
# All values from the private handoff and all command output remain in-process.
set -euo pipefail
set +x
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HANDOFF="${PLAYSTEAD_RECOVERY_RESTORE_HANDOFF:-}"
MODE="${1:-}"
case "$MODE" in check|ensure|remove-owned) ;; *) printf '%s\n' 'RECOVERY_BROWSER_TRUST stage=arguments outcome=blocked' >&2; exit 2 ;; esac

python3 - "$MODE" "$HANDOFF" <<'PY'
import datetime as dt
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid

mode, handoff_arg = sys.argv[1:]
OUT = "RECOVERY_BROWSER_TRUST stage={} outcome={}"
cleanup_dirs=[]
def cleanup():
    for item in cleanup_dirs:
        try: shutil.rmtree(item)
        except Exception: pass
def done(stage, outcome, code=0):
    cleanup()
    print(OUT.format(stage, outcome))
    raise SystemExit(code)
def safe_exception(exc_type, _value, _traceback):
    cleanup()
    print(OUT.format("internal", "blocked"), file=sys.stdout)
    raise SystemExit(77)
sys.excepthook=safe_exception
def fail(stage="preflight"):
    done(stage, "blocked", 77)
def run(args, timeout=15, input_data=None):
    try:
        kwargs={"capture_output":True,"timeout":timeout,"check":False}
        if input_data is None: kwargs["stdin"]=subprocess.DEVNULL
        else: kwargs["input"]=input_data
        return subprocess.run(args, **kwargs)
    except Exception:
        return None
def restricted_regular(path, owner=os.getuid(), mode_bits=0o600, max_bytes=1024*1024):
    try:
        st=path.lstat()
        return stat.S_ISREG(st.st_mode) and st.st_uid==owner and stat.S_IMODE(st.st_mode)==mode_bits and st.st_size<=max_bytes
    except OSError:
        return False
def parse_json_file(path):
    try:
        value=json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value,dict) else None
    except Exception:
        return None
def file_digest(path):
    try:
        h=hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda:stream.read(65536),b""): h.update(block)
        return h.hexdigest()
    except OSError:
        return None

if sys.platform != "darwin" or os.geteuid()==0 or not handoff_arg:
    fail()
handoff=pathlib.Path(handoff_arg)
if not handoff.is_absolute() or handoff.is_symlink() or not restricted_regular(handoff): fail()
try: handoff=handoff.resolve(strict=True)
except OSError: fail()
try:
    handoff_parent=handoff.parent.lstat()
    if handoff.parent.is_symlink() or handoff_parent.st_uid!=os.getuid() or (stat.S_IMODE(handoff_parent.st_mode)&0o022)!=0: fail()
except OSError: fail()
h=parse_json_file(handoff)
if not isinstance(h,dict) or set(h)!={"schema","correlation_id","project","url","receipt_path","ca_path"} or h.get("schema")!="playstead.restore-handoff.v1": fail()
try: uuid.UUID(h["correlation_id"])
except Exception: fail()
if not isinstance(h.get("project"),str) or not re.fullmatch(r"playstead-restore-[a-z0-9-]+",h["project"]): fail()
receipt=pathlib.Path(h.get("receipt_path","")); ca=pathlib.Path(h.get("ca_path",""))
if not receipt.is_absolute() or not ca.is_absolute() or receipt.is_symlink() or ca.is_symlink() or receipt.name!="restore-receipt.json" or ca.name!="caddy-root-ca.pem": fail()
try: receipt=receipt.resolve(strict=True); ca=ca.resolve(strict=True)
except OSError: fail()
if receipt.parent!=handoff.parent or ca.parent!=handoff.parent: fail()
if not restricted_regular(receipt) or not restricted_regular(ca): fail()
r=parse_json_file(receipt)
if not isinstance(r,dict) or set(r)!={"schema","state","correlation_id","target","chain_ids","stages","verified_at"} or r.get("schema")!="playstead.restore-receipt.v1" or r.get("state")!="verified" or r.get("correlation_id")!=h["correlation_id"] or r.get("stages")!=["chain","preflight","database","cas","manifest","api"] or not isinstance(r.get("chain_ids"),list) or not r["chain_ids"] or not all(isinstance(v,str) and v for v in r["chain_ids"]): fail()
t=r.get("target")
if not isinstance(t,dict) or set(t)!={"project","network","volumes","ports"} or t.get("project")!=h["project"] or t.get("network")!=h["project"]+"_default" or t.get("volumes")!=[h["project"]+"_db",h["project"]+"_blobs"]: fail()
ports=t.get("ports")
if not isinstance(ports,dict) or type(ports.get("https")) is not int or not 1<=ports["https"]<=65535: fail()
try:
    u=urllib.parse.urlparse(h["url"])
    if (u.scheme,u.hostname,u.username,u.password,u.query,u.fragment,u.port)!=("https","localhost",None,None,"","",ports["https"]) or u.path not in ("","/"): fail()
except Exception: fail()
try:
    if mode!="remove-owned":
        verified=dt.datetime.fromisoformat(r["verified_at"].replace("Z","+00:00"))
        now=dt.datetime.now(dt.timezone.utc)
        if verified.tzinfo is None or now-verified.astimezone(dt.timezone.utc)>dt.timedelta(hours=24) or verified>now+dt.timedelta(minutes=5): fail()
except Exception: fail()
try:
    ca_snapshot_dir=pathlib.Path(tempfile.mkdtemp(prefix="playstead-recovery-ca-"))
    cleanup_dirs.append(ca_snapshot_dir)
    os.chmod(ca_snapshot_dir,0o700)
    ca_snapshot=ca_snapshot_dir/"ca.pem"
    ca_bytes=ca.read_bytes()
    if not ca_bytes or len(ca_bytes)>1024*1024: fail()
    if not re.fullmatch(rb"\s*-----BEGIN CERTIFICATE-----\s*[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\s*",ca_bytes): fail("ca_validation")
    fd=os.open(ca_snapshot,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
    with os.fdopen(fd,"wb") as stream: stream.write(ca_bytes); stream.flush(); os.fsync(stream.fileno())
except Exception: fail()
ca_hash=file_digest(ca_snapshot)
if ca_hash is None: fail()

# Cleanup is intentionally available after the retained container is retired.
ownership=handoff.parent/"browser-trust-ownership.json"
login_result=run(["security","login-keychain"],timeout=10)
try:
    import shlex
    login_parts=shlex.split(login_result.stdout.decode("utf-8")) if login_result and login_result.returncode==0 else []
    login=pathlib.Path(login_parts[0]) if len(login_parts)==1 else pathlib.Path("/")
except Exception: login=pathlib.Path("/")
try:
    keychain_stat=login.lstat()
    login_safe=(login.is_absolute() and not stat.S_ISLNK(keychain_stat.st_mode) and stat.S_ISREG(keychain_stat.st_mode)
        and keychain_stat.st_uid==os.getuid() and (stat.S_IMODE(keychain_stat.st_mode)&0o022)==0 and keychain_stat.st_size<=16*1024*1024)
except OSError: login_safe=False
if not login_safe:
    done("login_keychain","blocked",77)
if mode=="remove-owned":
    if not restricted_regular(ownership): done("cleanup_ownership","unowned")
    record=parse_json_file(ownership)
    if not isinstance(record,dict) or set(record)!={"schema","correlation_id","ca_sha256","state"} or record.get("schema")!="playstead.recovery-browser-trust.v1" or record.get("correlation_id")!=h["correlation_id"] or record.get("ca_sha256")!=ca_hash or record.get("state") not in ("installed_by_helper","pending"): done("cleanup_ownership","blocked",77)
    removed=run(["security","remove-trusted-cert",str(ca_snapshot)],timeout=120)
    if removed is None or removed.returncode!=0: done("cleanup_authorization","authorization_required",77)
    try: ownership.unlink()
    except OSError: done("cleanup_record","blocked",77)
    done("cleanup","removed")

# Read-only inspection: exactly one Caddy service in the selected isolated
# namespace, exact project network, loopback-only publication and CA volume.
listed=run(["docker","ps","--no-trunc","--filter",f"label=com.docker.compose.project={h['project']}","--filter","label=com.docker.compose.service=caddy","--format","{{.ID}}"],timeout=15)
if listed is None: fail("container_tool")
if listed.returncode!=0: fail("container_query")
ids=[x for x in listed.stdout.decode("utf-8","replace").splitlines() if re.fullmatch(r"[0-9a-f]{12,64}",x.strip())]
if len(ids)!=1: fail("container_identity")
inspected=run(["docker","inspect",ids[0]],timeout=15)
try: containers=json.loads(inspected.stdout) if inspected and inspected.returncode==0 else []
except Exception: containers=[]
if not isinstance(containers,list) or len(containers)!=1: fail("container_identity")
c=containers[0]
labels=c.get("Config",{}).get("Labels",{}) or {}
if labels.get("com.docker.compose.project")!=h["project"] or labels.get("com.docker.compose.service")!="caddy" or not c.get("State",{}).get("Running"): fail("container_identity")
networks=c.get("NetworkSettings",{}).get("Networks",{}) or {}
if set(networks)!={h["project"]+"_default"}: fail("container_network")
mounts=c.get("Mounts",[])
caddy_vols=[m for m in mounts if m.get("Type")=="volume" and m.get("Destination")=="/data" and m.get("Name")==h["project"]+"_caddy_data" and m.get("RW") is True]
if len(caddy_vols)!=1: fail("container_ca_volume")
bindings=c.get("NetworkSettings",{}).get("Ports",{}).get("443/tcp",[]) or []
if len(bindings)!=1 or bindings[0].get("HostIp") not in ("127.0.0.1","::1") or str(bindings[0].get("HostPort"))!=str(ports["https"]): fail("container_https_binding")

# Compare the Caddy public root bytes using stdout held only in memory.
live=run(["docker","exec",ids[0],"cat","/data/caddy/pki/authorities/local/root.crt"],timeout=15)
if live is None or live.returncode!=0 or not live.stdout or len(live.stdout)>1024*1024: fail("ca_validation")
live_der=run(["openssl","x509","-inform","PEM","-outform","DER"],timeout=10,input_data=live.stdout)
expected_der=run(["openssl","x509","-in",str(ca_snapshot),"-outform","DER"],timeout=10)
if not live_der or live_der.returncode!=0 or not expected_der or expected_der.returncode!=0 or live_der.stdout!=expected_der.stdout: fail("ca_mismatch")
try:
    context=ssl.create_default_context(cafile=str(ca_snapshot)); context.check_hostname=True
    with socket.create_connection(("127.0.0.1",ports["https"]),timeout=8) as raw:
        with context.wrap_socket(raw,server_hostname="localhost") as tls:
            if tls.version() not in ("TLSv1.2","TLSv1.3"): fail("live_tls")
except Exception: fail("live_tls")

# Security's URL form evaluates the full live chain under ordinary SSL policy.
url="https://localhost:"+str(ports["https"])+"/healthz"
trust=run(["security","verify-cert","-v",url],timeout=15)
already_trusted=bool(trust and trust.returncode==0)

if mode=="check":
    done("browser_trust", "trusted" if already_trusted else "required",0 if already_trusted else 77)
if mode!="ensure": fail("arguments")
pending={"schema":"playstead.recovery-browser-trust.v1","correlation_id":h["correlation_id"],"ca_sha256":ca_hash,"state":"pending"}
def read_ownership():
    if not ownership.exists() and not ownership.is_symlink(): return None
    if not restricted_regular(ownership): done("ownership_record","conflict",77)
    value=parse_json_file(ownership)
    if (not isinstance(value,dict) or set(value)!={"schema","correlation_id","ca_sha256","state"}
        or value.get("schema")!=pending["schema"] or value.get("correlation_id")!=pending["correlation_id"]
        or value.get("ca_sha256")!=pending["ca_sha256"] or value.get("state") not in ("pending","installed_by_helper")):
        done("ownership_record","conflict",77)
    return value
def store_ownership(value,exclusive=False):
    temp=ownership.with_name(ownership.name+"."+uuid.uuid4().hex+".tmp")
    try:
        fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
        with os.fdopen(fd,"w",encoding="utf-8") as stream:
            json.dump(value,stream,sort_keys=True); stream.flush(); os.fsync(stream.fileno())
        if exclusive:
            # Link the fully written inode into place without replacing a race winner.
            os.link(temp,ownership,follow_symlinks=False)
            temp.unlink()
        else:
            os.replace(temp,ownership)
        os.chmod(ownership,0o600)
    except OSError:
        try: temp.unlink()
        except OSError: pass
        done("ownership_record","blocked",77)

existing=read_ownership()
if already_trusted:
    if existing and existing["state"]=="pending":
        store_ownership({**pending,"state":"installed_by_helper"})
        done("browser_trust","installed")
    # A preexisting trust without our ownership record remains unclaimed.
    done("browser_trust","already_trusted")
if existing is None:
    # Persist pending ownership before the authorization UI. Reconcile after
    # a timeout so a delayed import remains safely attributable.
    store_ownership(pending,exclusive=True)

added=run(["security","add-trusted-cert","-r","trustRoot","-p","ssl","-k",str(login),str(ca_snapshot)],timeout=120)
# Recheck the exact live leaf via the same SSL hostname policy.
recheck=run(["security","verify-cert","-v",url],timeout=20)
if recheck and recheck.returncode==0:
    try:
        installed={**pending,"state":"installed_by_helper"}
        temp=ownership.with_suffix(".tmp")
        fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
        with os.fdopen(fd,"w",encoding="utf-8") as stream:
            json.dump(installed,stream,sort_keys=True); stream.flush(); os.fsync(stream.fileno())
        os.replace(temp,ownership)
        done("browser_trust","installed")
    except OSError: done("ownership_record","reconcile_required",77)
else:
    error=(added.stderr.decode("utf-8","replace").lower() if added else "")
    authorization_failure=(added is None or (added and added.returncode==124)
        or any(term in error for term in ("authorization", "user canceled", "user cancelled", "interaction not allowed", "denied")))
    if authorization_failure:
        done("browser_trust","authorization_required",77)
    if added is not None and added.returncode!=0:
        try: ownership.unlink()
        except OSError: pass
    done("browser_trust","install_failed",77)
PY
