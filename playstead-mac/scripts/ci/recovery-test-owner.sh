#!/usr/bin/env bash
# Explicit, isolated disposable owner setup for the retained recovery target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"
if [[ "$MODE" != prepare && "$MODE" != check && "$MODE" != approve-once ]]; then
  printf '%s\n' 'RECOVERY_TEST_OWNER stage=arguments outcome=blocked' >&2
  exit 2
fi
APPROVAL_PROFILE="${2:-}"
if [[ "$MODE" == approve-once && "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL:-}" != 1 ]]; then
  printf '%s\n' 'RECOVERY_TEST_OWNER stage=approval_driver outcome=disabled' >&2
  exit 77
fi
if [[ "$MODE" == approve-once && "$#" -ne 2 ]]; then
  printf '%s\n' 'RECOVERY_TEST_OWNER stage=arguments outcome=blocked' >&2
  exit 2
fi

stage=handoff
blocked() {
  printf 'RECOVERY_TEST_OWNER stage=%s outcome=blocked\n' "$stage" >&2
  exit 77
}

HANDOFF="${PLAYSTEAD_RECOVERY_RESTORE_HANDOFF:-}"
[[ -n "$HANDOFF" ]] || blocked
if ! "$SCRIPT_DIR/recovery-e2e.sh" --validate-only >/dev/null 2>&1; then blocked; fi
stage=browser_trust
if ! PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SCRIPT_DIR/recovery-browser-trust.sh" check >/dev/null 2>&1; then blocked; fi
stage=target_scope

# All private values stay in the Python process or are sent over stdin to the
# exact validated app container. Neither Docker output nor RPC output is shown.
exec python3 - "$MODE" "$HANDOFF" "$APPROVAL_PROFILE" <<'PY'
import datetime as dt, json, os, pathlib, re, secrets, stat, subprocess, sys, time
import signal

mode, handoff_arg, profile_arg = sys.argv[1:]
stage = "target_scope"
def status(outcome):
    print(f"RECOVERY_TEST_OWNER stage={stage} outcome={outcome}")
    raise SystemExit(0 if outcome in {"ready", "prepared", "reused", "approved"} else 77)
def refuse(): status("blocked")
active_process=None
def stop_process(_signum, _frame):
    global active_process
    if active_process is not None and active_process.poll() is None:
        active_process.terminate()
        try: active_process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            active_process.kill(); active_process.wait()
    raise SystemExit(143)
signal.signal(signal.SIGTERM,stop_process)
def run(args, *, data=None, timeout=30):
    global active_process
    try:
        active_process=subprocess.Popen(args,stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        stdout,stderr=active_process.communicate(input=data,timeout=timeout)
        result=subprocess.CompletedProcess(args,active_process.returncode,stdout,stderr)
        active_process=None
        return result
    except subprocess.TimeoutExpired:
        if active_process is not None:
            active_process.terminate()
            try: active_process.wait(timeout=1)
            except subprocess.TimeoutExpired: active_process.kill(); active_process.wait()
            active_process=None
        return None
    except Exception:
        active_process=None
        return None

try:
    stage="private_files"
    handoff = pathlib.Path(handoff_arg)
    if not handoff.is_absolute() or handoff.is_symlink() or not handoff.is_file() or stat.S_IMODE(handoff.stat().st_mode) != 0o600:
        refuse()
    root = handoff.parent.resolve(strict=True)
    if root != handoff.parent or not root.is_dir() or root.is_symlink() or root.stat().st_uid != os.getuid() or stat.S_IMODE(root.stat().st_mode) & 0o022:
        refuse()
    h=json.loads(handoff.read_text())
    stage="handoff_shape"
    if set(h)!={"schema","correlation_id","project","url","receipt_path","ca_path"} or h["schema"]!="playstead.restore-handoff.v1": refuse()
    project=h["project"]
    if not re.fullmatch(r"playstead-restore-[a-z0-9-]+",project): refuse()
    if h["receipt_path"] != str(root/"restore-receipt.json") or h["ca_path"] != str(root/"caddy-root-ca.pem"): refuse()
    record_path=root/"test-owner.json"
    stage="owner_record"
    if record_path.exists() or record_path.is_symlink():
        if record_path.is_symlink() or not record_path.is_file() or stat.S_IMODE(record_path.stat().st_mode)!=0o600 or record_path.stat().st_uid!=os.getuid(): refuse()
        record=json.loads(record_path.read_text())
        if set(record)!={"schema","correlation_id","test_only","email","password","state"} or record.get("schema")!="playstead.recovery-test-owner.v1" or record.get("correlation_id")!=h["correlation_id"] or record.get("test_only") is not True or record.get("state") not in {"pending","ready"} or not isinstance(record.get("email"),str) or not isinstance(record.get("password"),str) or len(record["email"])>320 or len(record["password"])>256 or record_path.stat().st_size>4096: refuse()
    else: record=None

    # Prove the three selected services belong only to this isolated Compose
    # project/network and mount only the project-owned persistence volumes.
    stage="target_scope"
    ps=run(["docker","ps","--filter",f"label=com.docker.compose.project={project}","--format","{{.ID}}"])
    if ps is None or ps.returncode or not ps.stdout: refuse()
    ids=ps.stdout.decode("ascii","strict").splitlines()
    if len(ids)!=3 or any(not re.fullmatch(r"[0-9a-f]{12,64}",x) for x in ids): refuse()
    ins=run(["docker","inspect",*ids])
    if ins is None or ins.returncode: refuse()
    containers=json.loads(ins.stdout)
    services={}
    for c in containers:
        labels=c.get("Config",{}).get("Labels",{}) or {}
        service=labels.get("com.docker.compose.service")
        if labels.get("com.docker.compose.project")!=project or service not in {"app","db","caddy"} or service in services or not re.fullmatch(r"[0-9a-f]{64}",c.get("Id","")) or not c.get("State",{}).get("Running"): refuse()
        nets=set((c.get("NetworkSettings",{}).get("Networks") or {}).keys())
        if nets!={project+"_default"}: refuse()
        services[service]=c
    if set(services)!={"app","db","caddy"}: refuse()
    expected={"db":{(project+"_db","/var/lib/postgresql/data")},"app":{(project+"_blobs","/app/blobs"),(project+"_caddy_data","/caddy_data")},"caddy":{(project+"_caddy_data","/data"),(project+"_caddy_config","/config")}}
    allowed_volumes={project+suffix for suffix in ("_db","_blobs","_caddy_data","_caddy_config")}
    for service,expected_mounts in expected.items():
        mounts=services[service].get("Mounts",[])
        actual={(m.get("Name"),m.get("Destination")) for m in mounts if m.get("Type")=="volume"}
        if actual!=expected_mounts or any(m.get("Type")=="volume" and m.get("Name") not in allowed_volumes for m in mounts): refuse()
        if service in {"app","db"} and any(any(bindings or []) for bindings in (services[service].get("NetworkSettings",{}).get("Ports") or {}).values()): refuse()
    app_id=services["app"]["Id"]
    app_env=services["app"].get("Config",{}).get("Env",[])
    database_url=next((item.split("=",1)[1] for item in app_env if item.startswith("DATABASE_URL=")),"")
    if not re.fullmatch(r"ecto://playstead_restore:[^/@:]+@db(?::5432)?/playstead_restore",database_url): refuse()

    # Container topology guard above plus coordinator validation ensures the
    # exact retained restore is selected. The DB verifier checks auth only.
    stage="owner_record"
    def eval_app(code, payload, timeout=45):
        return run(["docker","exec","-i",app_id,"bin/playstead","eval",code],data=payload,timeout=timeout)
    if mode=="approve-once":
        if not record or record["state"]!="ready": refuse()
        code='''Application.load(:playstead)
input=IO.read(:stdio,:eof)
{:ok,result,_}=Ecto.Migrator.with_repo(Playstead.Repo,fn _ ->
  case Jason.decode(input) do
    {:ok,%{"email"=>email,"password"=>password}} ->
      case Playstead.Accounts.get_user_by_password(email,password) do
        %Playstead.Accounts.User{role: :owner} -> true
        _ -> false
      end
    _ -> false
  end
end)
if result, do: IO.puts("RECOVERY_OWNER_AUTH_VALID"), else: System.halt(2)'''
        auth=eval_app(code,json.dumps({"email":record["email"],"password":record["password"]}).encode())
        if auth is None or auth.returncode or b"RECOVERY_OWNER_AUTH_VALID" not in auth.stdout: refuse()
        stage="approval_request"
        profile=pathlib.Path(profile_arg)
        if not profile.is_absolute() or profile.name!="profile" or profile.is_symlink() or not profile.is_dir(): refuse()
        profile=profile.resolve(strict=True)
        private_root=profile.parent
        if private_root.is_symlink() or private_root.stat().st_uid!=os.getuid() or stat.S_IMODE(private_root.stat().st_mode)!=0o700 or profile.stat().st_uid!=os.getuid() or stat.S_IMODE(profile.stat().st_mode)!=0o700: refuse()
        target_file=profile/"recovery-target.url"
        if target_file.is_symlink() or not target_file.is_file() or target_file.stat().st_uid!=os.getuid() or stat.S_IMODE(target_file.stat().st_mode)!=0o600: refuse()
        if target_file.read_bytes()!=h["url"].encode("utf-8"): refuse()
        approval_file=profile/"recovery-approval-request.json"
        deadline=time.monotonic()+120
        while time.monotonic()<deadline and not approval_file.exists() and not approval_file.is_symlink(): time.sleep(0.25)
        if approval_file.is_symlink() or not approval_file.exists() or not approval_file.is_file() or approval_file.stat().st_uid!=os.getuid() or stat.S_IMODE(approval_file.stat().st_mode)!=0o600 or approval_file.stat().st_size>1024: refuse()
        request=json.loads(approval_file.read_text(encoding="utf-8"))
        if not isinstance(request,dict) or set(request)!={"schema","display_code","requested_at"} or request.get("schema")!="playstead.recovery-test-approval.v1": refuse()
        display_code=request.get("display_code")
        if not isinstance(display_code,str) or not re.fullmatch(r"[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}",display_code): refuse()
        try: requested_at=dt.datetime.fromisoformat(request["requested_at"].replace("Z","+00:00"))
        except Exception: refuse()
        now=dt.datetime.now(dt.timezone.utc)
        file_mtime=dt.datetime.fromtimestamp(approval_file.stat().st_mtime,dt.timezone.utc)
        requested_at=requested_at.astimezone(dt.timezone.utc) if requested_at.tzinfo else None
        if requested_at is None or abs((file_mtime-requested_at).total_seconds())>10 or abs((now-requested_at).total_seconds())>120: refuse()
        payload=json.dumps({"email":record["email"],"password":record["password"],"display_code":display_code,"requested_at":requested_at.isoformat()}).encode()
        code='''Application.load(:playstead)
import Ecto.Query
input=IO.read(:stdio,:eof)
{:ok,%{"email"=>email,"password"=>password,"display_code"=>display_code,"requested_at"=>requested_value}}=Jason.decode(input)
{:ok,approved,_}=Ecto.Migrator.with_repo(Playstead.Repo,fn _ ->
  owner=Playstead.Accounts.get_user_by_password(email,password)
  if owner == nil or owner.role != :owner do
    false
  else
    {:ok,requested_at,_}=DateTime.from_iso8601(requested_value)
    lower=DateTime.add(requested_at,-10,:second)
    upper=DateTime.add(requested_at,10,:second)
    now=DateTime.utc_now()
    candidates=from(r in Playstead.Pairing.PairingRequest,
      where: r.status=="pending" and r.display_code==^display_code and
        r.inserted_at>=^lower and r.inserted_at<=^upper and r.expires_at>^now)
      |> Playstead.Repo.all()
    case candidates do
      [request] ->
        case Playstead.Pairing.approve(Playstead.Accounts.Scope.for_user(owner),request.id) do
          {:ok,%Playstead.Pairing.PairingRequest{status: "approved"}} -> true
          _ -> false
        end
      _ -> false
    end
  end
end)
if approved, do: IO.puts("RECOVERY_TEST_OWNER_APPROVAL=approved"), else: System.halt(2)'''
        remaining=max(1,int(deadline-time.monotonic()))
        print("approval_driver=test_owner",file=sys.stderr)
        approval=eval_app(code,payload,timeout=remaining)
        if approval is None or approval.returncode or b"RECOVERY_TEST_OWNER_APPROVAL=approved" not in approval.stdout: refuse()
        stage="approval_driver"; status("approved")
    if record:
        code='''Application.load(:playstead)
input=IO.read(:stdio,:eof)
{:ok,result,_}=Ecto.Migrator.with_repo(Playstead.Repo, fn _ ->
  case Jason.decode(input) do
    {:ok,%{"email"=>email,"password"=>password}} -> not is_nil(Playstead.Accounts.get_user_by_password(email,password))
    _ -> false
  end
end)
if result, do: IO.puts("RECOVERY_OWNER_AUTH_VALID"), else: System.halt(2)'''
        checked=eval_app(code,json.dumps({"email":record["email"],"password":record["password"]}).encode())
        valid=checked is not None and checked.returncode==0 and b"RECOVERY_OWNER_AUTH_VALID" in checked.stdout
        if mode=="check":
            if not valid or record["state"]!="ready": refuse()
            stage="complete"; status("ready")
        if record["state"]=="ready":
            if not valid: refuse()
            stage="complete"; status("reused")
        if valid:
            record["state"]="ready"
            temp=record_path.with_name("test-owner.json."+secrets.token_hex(8)+".tmp")
            fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            with os.fdopen(fd,"wb") as f: f.write((json.dumps(record,separators=(",",":"))+"\n").encode()); f.flush(); os.fsync(f.fileno())
            os.replace(temp,record_path); os.chmod(record_path,0o600)
            stage="complete"; status("reused")
    elif mode=="check":
        stage="complete"; status("required")

    stage="owner_reset"
    password=record["password"] if record else secrets.token_urlsafe(32)
    email=record["email"] if record else ""
    if not record:
        code='''Application.load(:playstead)
{:ok,email,_}=Ecto.Migrator.with_repo(Playstead.Repo,fn _ ->
  case Playstead.Accounts.get_owner() do %{email: value} -> value; _ -> nil end
end)
if is_binary(email), do: IO.puts("RECOVERY_TEST_OWNER_EMAIL:" <> email), else: System.halt(2)'''
        owner=eval_app(code,b"",timeout=45)
        if owner is None or owner.returncode: refuse()
        owner_lines=[line[len(b"RECOVERY_TEST_OWNER_EMAIL:"):].decode("utf-8") for line in owner.stdout.splitlines() if line.startswith(b"RECOVERY_TEST_OWNER_EMAIL:")]
        if len(owner_lines)!=1: refuse()
        email=owner_lines[0]
        if not email or len(email)>320 or "\n" in email: refuse()
        record={"schema":"playstead.recovery-test-owner.v1","correlation_id":h["correlation_id"],"test_only":True,"email":email,"password":password,"state":"pending"}
        data=(json.dumps(record,separators=(",",":"))+"\n").encode()
        fd=os.open(record_path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,"wb") as f: f.write(data); f.flush(); os.fsync(f.fileno())
    # Reset issuance and consumption run within the selected app's own BEAM.
    # The URL/token is captured via a private group leader and parsed only in
    # memory; stdout contains only the final private JSON for this process.
    code='''Application.load(:playstead)
input=IO.read(:stdio,:eof)
{:ok,%{"email"=>email,"password"=>password}}=Jason.decode(input)
true=is_binary(email) and is_binary(password) and byte_size(password)>=24
{:ok,io}=StringIO.open("")
old=Process.group_leader()
Process.group_leader(self(),io)
result=Playstead.Release.reset_owner_password()
Process.group_leader(self(),old)
{_,output}=StringIO.contents(io)
StringIO.close(io)
token=case Regex.run(~r{/reset/([^\\s/?#]+)},output,capture: :all_but_first) do [value] -> value; _ -> nil end
if result==:ok and is_binary(token) do
  consumed=Ecto.Migrator.with_repo(Playstead.Repo,fn _ ->
    case Playstead.Accounts.reset_password_with_token(token,%{password: password}) do
      {:ok,{user,_}} when user.email==email -> {:ok,user.email}
      _ -> :failed
    end
  end)
  case consumed do
    {:ok,{:ok,^email},_} -> IO.puts("RECOVERY_TEST_OWNER_RESULT:" <> Jason.encode!(%{"email"=>email,"password"=>password}))
    _ -> System.halt(2)
  end
else
  System.halt(2)
end'''
    payload=json.dumps({"email":email,"password":password}).encode()
    changed=eval_app(code,payload,timeout=120)
    if changed is None or changed.returncode: refuse()
    result_lines=[line[len(b"RECOVERY_TEST_OWNER_RESULT:"):] for line in changed.stdout.splitlines() if line.startswith(b"RECOVERY_TEST_OWNER_RESULT:")]
    if len(result_lines)!=1: refuse()
    private=json.loads(result_lines[0].decode("utf-8"))
    if set(private)!={"email","password"} or private["email"]!=email or private["password"]!=password: refuse()
    record["state"]="ready"
    temp=record_path.with_name("test-owner.json."+secrets.token_hex(8)+".tmp")
    fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as f: f.write((json.dumps(record,separators=(",",":"))+"\n").encode()); f.flush(); os.fsync(f.fileno())
    os.replace(temp,record_path); os.chmod(record_path,0o600)
    stage="complete"; status("prepared")
except SystemExit:
    raise
except Exception:
    status("blocked")
PY
