# The four checks that keep a self-hosted open-source agent install alive

A self-hosted Kortix instance rarely fails on the model. It fails on something measurable before the first person signs in: an open door, an API a sandbox cannot reach, a backup without its key, or a doctor nobody read. Kortix is the open-source CompanyOS, and these four readings cover the first week.

## Who can sign up

A domain or tunnel instance without `EMAIL_URL` starts at `KORTIX_SIGNUP_MODE=invite`: the auth service creates an account only for an address with a pending invitation, and the admin account comes from `kortix self-host admin add`. Neither the admin address nor any address in `KORTIX_PLATFORM_ADMIN_EMAILS` can be claimed by signing up.

`open` admits anyone, and it is the default on a laptop instance and on any instance with `EMAIL_URL`, where every new account must confirm its address. Without `EMAIL_URL`, auth confirms each sign-up without sending mail, so an open instance lets the first person to type an address hold it. That is why a public instance starts at `invite`.

```
$ ./bin/check-signup.sh --instance default
instance: default (/home/ops/.config/kortix/self-host/default/.env)
KORTIX_SIGNUP_MODE=invite — only an address with a pending invitation creates an account
```

`check-signup.sh` reads `/auth/v1/settings` and exits 0 when sign-up is invite-only, closed or email-verified, 1 when it admits unverified addresses, 2 when it cannot tell. With `--instance <name>` it reads `DISABLE_SIGNUP`, `EMAIL_URL` and `KORTIX_SIGNUP_MODE` from `.env`, which works when the API is down.

Run it after the first admin sign-in and after updates. Closing sign-up takes `kortix self-host env set KORTIX_SIGNUP_MODE=closed`.

## An API a sandbox can reach

No session runs on the server. `kortix-api` creates each one on a Platinum sandbox with `PLATINUM_API_KEY`, and that sandbox calls back to the instance's public `KORTIX_URL`. If `api.<domain>` does not resolve to the server, the stack looks healthy and no session starts. Local mode has no public URL: the app answers on port 13737 and nothing starts.

```
$ ./bin/preflight.sh kortix.example.com
FAIL api.kortix.example.com does not resolve — sessions call back to that URL and will not start without it
```

The same run probes a preview label. Without the wildcard record, previews go through a path proxy and root-absolute links break:

```
 FAIL preview-origins: domain mode with KORTIX_PREVIEW_BASE_DOMAIN empty
      fix: add the wildcard DNS record, then: kortix self-host env set KORTIX_PREVIEW_BASE_DOMAIN=p.<domain> / start
```

Run `preflight.sh` before `init` and after any DNS, proxy or certificate change. It also checks ports 80 and 443, which only Caddy may hold in domain mode.

## A backup that carries the key

The instance directory is the unit to copy: `.env` holds the secrets and signing keys, `volumes/db/data` is Postgres, `volumes/storage` keeps files. A database dump captures one of those three and leaves the key behind. `API_KEY_SECRET` decrypts every stored secret, so a copy without it restores a stack that serves and cannot read its own credentials. Expect three strings when that happens: `Undecryptable` on a project secret, `credential_undecryptable` from a connector call, and `409 SECRET_UNDECRYPTABLE` from any request that needs a value.

`backup.sh` stops the stack, archives the directory, checks the three paths are inside, and writes a sha256 plus a 16-hex key fingerprint. The fingerprint is a hash, and the value never leaves the shell. `restore.sh` fingerprints the archived key and refuses the swap that breaks everything:

```
$ ./bin/restore.sh backups/kortix-default-20261021T200633Z.tgz --instance default
 ok    checksum matches ...tgz.sha256
 ok    archive API_KEY_SECRET fingerprint 886cf16380f71220
 FAIL  API_KEY_SECRET differs: live instance ebba8706326c194c, archive 886cf16380f71220
       restoring replaces the key, so every secret, connector credential and token stored now becomes unreadable
```

`--force` continues anyway, for a rebuild where the old credentials should go; the directory stays as `*.pre-restore-*`. Back up before every update and `env` change, and run a restore drill on a spare instance.

## A doctor someone reads

Nine checks: `docker`, `docker-compose`, `compose-config`, `capture-store`, `instance-dir`, `email-url`, `preview-origins`, `wildcard-tls`, `open-sign-up`. Eight of nine is the usual first result.

```
$ ./bin/doctor.sh default
 ok   docker
 ok   docker-compose
 ok   compose-config
 ok   capture-store
 ok   instance-dir
 ok   email-url
 FAIL preview-origins: domain mode with KORTIX_PREVIEW_BASE_DOMAIN empty
      fix: add the wildcard DNS record, then: kortix self-host env set KORTIX_PREVIEW_BASE_DOMAIN=p.<domain> / start
 ok   wildcard-tls
 ok   open-sign-up

8/9 passed
```

`doctor.sh` decodes `--json` into that table, prints a fix line for the failure, and keeps a timestamped report under `reports/`. Exit 0 means all passed, 1 a failure. Read it before anyone signs in, and after updates. An install that only ran the bootstrap leaves both outward-facing checks failing.

## Sizing, disk and the daily update

The published limits sum to `kortix-api` 2048m, `llm-gateway` 2048m, `frontend` 512m and Postgres fixed at 1280m. That is 5888MB of containers before host memory, so `preflight.sh` fails below 6000MB, warns to 7500, and passes above. Disk has a floor: `kortix-updater` stops below `KORTIX_MIN_FREE_DISK_MB`, 2048 by default.

The updater runs at 02:00 in `America/New_York` unless `KORTIX_UPDATE_TIME` or `KORTIX_UPDATE_TZ` says otherwise. It pulls the channel, runs `kortix-migrate`, then rolls the API, gateway and front end. A failed migration swaps nothing and the old version keeps answering. `kortix self-host status` shows the last outcome, and `rollback --release <version>` returns to the old version.

## What a schedule buys

In cron, `verify-all.sh` reruns sign-up, doctor, update status and backup age, and exits 1 when a person is needed.
