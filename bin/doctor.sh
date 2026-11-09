#!/usr/bin/env bash
# doctor — decode the open-source Kortix doctor output into a readable table,
# keep a dated copy of the report, and say what to do about each failure.
#
#   ./bin/doctor.sh [instance]
#
# Exit code follows doctor: 0 all pass, 1 one failed. Reports land in reports/.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=bin/lib.sh
. bin/lib.sh

INSTANCE="${1:-${KORTIX_INSTANCE:-default}}"
mkdir -p reports
OUT="reports/doctor-$(date -u +%Y%m%dT%H%M%SZ)-${INSTANCE}.json"

if ! have kortix; then
  fail "kortix CLI not found — install it with: curl -fsSL https://kortix.com/install | bash"
  exit 1
fi

set +e
raw=$(kortix self-host doctor --instance "$INSTANCE" --json 2>&1)
rc=$?
set -e

printf '%s\n' "$raw" > "$OUT"

# The report is JSON; print a table from it and fall back to raw output when
# a build prints something else.
python3 - "$OUT" "$rc" <<'PY'
import json, sys
path, rc = sys.argv[1], int(sys.argv[2])
raw = open(path, encoding="utf-8", errors="replace").read().strip()
FIX = {
  "docker": "install Docker Engine (apt install docker.io or get.docker.com)",
  "docker-compose": "install the Compose plugin: apt install docker-compose-plugin",
  "compose-config": "read the value the error names and correct it: kortix self-host env set KEY=VALUE",
  "instance-dir": "the instance directory moved — run kortix self-host configure (or env set) to re-anchor it",
  "email-url": "EMAIL_URL does not parse — use smtp://user:pass@host:587, smtps://, resend://, ses:// or mailtrap://",
  "preview-origins": "add the wildcard DNS record, then: kortix self-host env set KORTIX_PREVIEW_BASE_DOMAIN=p.<domain> / start",
  "wildcard-tls": "domain mode still gets one certificate per host: run kortix self-host tls wildcard and add the DNS records it prints (UDP and TCP 53 open)",
  "open-sign-up": "sign-up is open with email confirmation off: kortix self-host env set KORTIX_SIGNUP_MODE=invite (or set EMAIL_URL)",
}
try:
    data = json.loads(raw)
except Exception:
    if raw:
        print(raw)
    sys.exit(rc)

checks = data.get("checks") or data.get("results") or []
if isinstance(checks, dict):
    checks = [{"name": k, **(v if isinstance(v, dict) else {"ok": bool(v)})} for k, v in checks.items()]
failed = 0
for c in checks:
    name = c.get("name") or c.get("check") or "?"
    ok = c.get("ok", c.get("pass", c.get("passed")))
    msg = c.get("message") or c.get("detail") or c.get("error") or ""
    if ok:
        print(f" ok   {name}")
    else:
        failed += 1
        print(f" FAIL {name}: {msg}")
        if name in FIX:
            print(f"      fix: {FIX[name]}")
print()
print(f"{len(checks) - failed}/{len(checks)} passed")
sys.exit(0 if failed == 0 else 1)
PY
out_rc=$?
echo
echo "report saved: $OUT"
[ "$out_rc" -eq 0 ] || exit 1
exit "$rc"
