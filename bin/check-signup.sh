#!/usr/bin/env bash
# check-signup — for a reachable self-hosted open-source instance, answer the
# one question that decides whether it is safe: can a stranger create an account?
#
#   ./bin/check-signup.sh https://kortix.example.com     # probe a live instance
#   ./bin/check-signup.sh --instance default             # read the local .env
#
# 0 = closed or email-verified, 1 = open, 2 = could not determine.
#
# The public auth settings endpoint is /auth/v1/settings (GoTrue behind Kong).
# It reports disable_signup and mailer_autoconfirm without credentials.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=bin/lib.sh
. bin/lib.sh

target="${1:-}"
if [ -z "$target" ]; then
  echo "usage: $0 <https://domain> | --instance <name>" >&2
  exit 2
fi

verdict_from_json() {
  python3 - "$1" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    d = json.loads(raw)
except Exception:
    print("could not parse the settings response"); sys.exit(2)
signup_off = bool(d.get("disable_signup", False))
autoconfirm = bool(d.get("mailer_autoconfirm", False))
providers = [k for k, v in (d.get("external") or {}).items() if v]
print(f"disable_signup={signup_off} mailer_autoconfirm={autoconfirm} external={','.join(providers) or 'none'}")
if signup_off:
    print("CLOSED — only an existing user or a platform admin can create an account"); sys.exit(0)
if autoconfirm:
    print("AUTO-CONFIRM ON — sign-up confirms an address without an email.")
    print("      With KORTIX_SIGNUP_MODE=open that admits any address; invite mode still")
    print("      requires a pending invitation. Admin addresses cannot be claimed by sign-up.")
    print("      read the mode locally: check-signup.sh --instance <name>")
    sys.exit(2)
print("INVITE or EMAIL-VERIFIED — sign-up requires an invitation or a confirmed address")
sys.exit(0)
PY
}

if [ "$target" = "--instance" ]; then
  INSTANCE="${2:-${KORTIX_INSTANCE:-default}}"
  envfile="$(instance_dir "$INSTANCE")/.env"
  if [ ! -r "$envfile" ]; then
    fail "no readable .env at $envfile — wrong instance name, or the stack was never initialised"
    exit 2
  fi
  disable=$(env_get "$envfile" DISABLE_SIGNUP)
  email_url=$(env_get "$envfile" EMAIL_URL)
  mode=$(env_get "$envfile" KORTIX_SIGNUP_MODE)
  # A domain or tunnel instance without EMAIL_URL defaults to invite.
  [ -z "$mode" ] && [ -z "$email_url" ] && mode="invite (default)"
  echo "instance: $INSTANCE ($envfile)"
  if [ "$disable" = "true" ]; then
    ok "DISABLE_SIGNUP=true — sign-up closed"
    exit 0
  fi
  case "$mode" in
    closed)
      ok "KORTIX_SIGNUP_MODE=closed — nobody creates an account by signing up"
      exit 0 ;;
    invite*)
      ok "KORTIX_SIGNUP_MODE=$mode — only an address with a pending invitation creates an account"
      exit 0 ;;
    open)
      if [ -n "$email_url" ]; then
        ok "KORTIX_SIGNUP_MODE=open with EMAIL_URL — anyone may sign up and must confirm the address"
        exit 0
      fi
      fail "KORTIX_SIGNUP_MODE=open and no EMAIL_URL — any address is confirmed without an email"
      note "fix: kortix self-host env set KORTIX_SIGNUP_MODE=invite   (or set EMAIL_URL)"
      exit 1 ;;
    *)
      fail "unknown KORTIX_SIGNUP_MODE=$mode — expected invite, open or closed"
      exit 2 ;;
  esac
fi

base="${target%/}"
echo "probing ${base}/auth/v1/settings"
body=$(curl -fsS --max-time 15 "${base}/auth/v1/settings" 2>/dev/null)
if [ -z "$body" ]; then
  fail "no answer from ${base}/auth/v1/settings — is the stack up and Caddy routing /auth/v1?"
  note "read the value locally instead: $0 --instance <name>"
  exit 2
fi
verdict_from_json "$body"
