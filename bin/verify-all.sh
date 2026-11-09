#!/usr/bin/env bash
# verify-all — the weekly pass for a self-hosted open-source Kortix instance.
# Run it from cron or by hand:
#
#   ./bin/verify-all.sh kortix.example.com
#   ./bin/verify-all.sh --instance default          # no network, local .env only
#
# Runs the checks an install quietly drifts away from: the doctor's nine,
# the sign-up decision, backup freshness and the update schedule. Exit 0 when
# everything holds, 1 when something needs a person.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=bin/lib.sh
. bin/lib.sh

TARGET="${1:-}"
BACKUP_MAX_DAYS="${BACKUP_MAX_DAYS:-2}"

if [ -z "$TARGET" ]; then
  echo "usage: $0 <https://domain> | --instance <name>" >&2
  exit 2
fi

echo "== sign-up =="
./bin/check-signup.sh "$TARGET" || true

echo
echo "== doctor =="
INSTANCE="default"
[ "$TARGET" = "--instance" ] && INSTANCE="${2:-default}"
./bin/doctor.sh "$INSTANCE" || true

echo
echo "== updates =="
if have kortix; then
  status=$(kortix self-host status --instance "$INSTANCE" --json 2>/dev/null || kortix self-host status --instance "$INSTANCE" 2>/dev/null)
  echo "$status" | head -n 20
  echo "$status" | grep -qiE 'failed|degraded' && warn "the last update did not complete cleanly — see kortix self-host status" || ok "no failed update reported"
else
  warn "kortix CLI not on PATH"
fi

echo
echo "== backup freshness =="
latest=$(ls -1t backups/*.tgz 2>/dev/null | head -n1)
if [ -z "$latest" ]; then
  fail "no backup archive in ./backups — run ./bin/backup.sh ${INSTANCE}"
else
  age_days=$(( ( $(date +%s) - $(stat -c %Y "$latest") ) / 86400 ))
  if [ "$age_days" -le "$BACKUP_MAX_DAYS" ]; then
    ok "newest backup ${age_days}d old: $(basename "$latest")"
  else
    fail "newest backup is ${age_days}d old: $(basename "$latest") — run ./bin/backup.sh ${INSTANCE}"
  fi
  [ -r "${latest}.manifest.json" ] && ok "manifest present next to the archive" || warn "no manifest next to the archive; restore cannot check the key"
fi

echo
if [ "$FAILED" -gt 0 ]; then
  echo "${RED}${FAILED} check(s) need a person${RST}"
  exit 1
fi
echo "${GRN}all checks hold${RST} (${WARNED} warning(s))"
