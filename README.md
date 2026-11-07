# Self-hosted AI agents: an open-source operator kit for Kortix

Kortix is the open-source CompanyOS. This repo holds what one operator runs on the server that hosts the instance: six scripts and a small library that answer whether the install is safe to hand to a team, and what to do when it is not.

Self-hosting Kortix puts the control plane, the Postgres database and the stored files on a machine you own. Sessions run on sandboxes elsewhere, and model calls go to the providers you hold keys for. Four checks decide whether the split holds through the first week, and every check here exits non-zero when it does not.

## The four checks

| Check | Command | Failure it prevents |
| --- | --- | --- |
| Closed sign-up | `make signup DOMAIN=<domain>` | A stranger claiming an admin address |
| Reachable API | `make preflight DOMAIN=<domain>` | Sessions that never start, broken previews |
| Backup with the key | `make backup` | Credentials unreadable after a restore |
| A doctor someone reads | `make doctor` | Failures that only surface after an update |

`make` forwards arguments and nothing else. Run the scripts under `bin/` directly when a target gets in the way.

## Quickstart

Run this on the server with your own domain and address. `preflight.sh` is safe before the stack exists, and every step after it assumes that check passed.

```bash
# from a clone of this repo
./bin/preflight.sh kortix.example.com
curl -fsSL https://kortix.com/install | bash
kortix self-host init --domain kortix.example.com --admin-email you@example.com
kortix self-host configure
kortix self-host start
```

`preflight.sh` checks DNS, ports, disk and memory before anything is written. `init` writes `docker-compose.yml`, `.env`, a `Caddyfile` and `updater.sh` into `~/.config/kortix/self-host/default/`. `configure` asks for the admin address, `PLATINUM_API_KEY` and the preview domain `p.kortix.example.com`, and `start` applies the answers. Then do these before you invite anyone:

1. Open `https://kortix.example.com` and sign up with the admin address.
2. Connect GitHub at `/admin/git`. Kortix creates every project repository through that identity.
3. Create a project at `/new`, then use the project menu, Switch Project, Create an account to make the team account. Add a model key under Customize, Models, Providers.
4. Close the door: `kortix self-host env set DISABLE_SIGNUP=true`, then `kortix self-host start`, then `./bin/check-signup.sh https://kortix.example.com` until it reports CLOSED.
5. Take the first backup with `sudo ./bin/backup.sh default /var/backups/kortix` and copy the archive, its `.sha256` and its `.manifest.json` off the server.
6. Put `./bin/verify-all.sh https://kortix.example.com` in cron for the weekly pass, and read its exit code.

## What is in `bin/`

| Script | What it does |
| --- | --- |
| `preflight.sh <domain>` | DNS, ports 80 and 443, disk, memory, tooling before `init` |
| `doctor.sh [instance]` | Decodes doctor JSON, prints a fix per failure, saves a report |
| `check-signup.sh <url>` | Asks `/auth/v1/settings` whether a stranger can join |
| `backup.sh [instance] [dest]` | Stops the stack, archives the instance, records the key fingerprint |
| `restore.sh <archive>` | Checks checksum and key, refuses a mismatched key |
| `verify-all.sh <url>` | Sign-up, doctor, update status and backup age in one pass |
| `lib.sh` | Shared helpers: instance path, key fingerprint, output |

Reports land in `reports/doctor-<timestamp>-<instance>.json`. Archives, checksums and manifests land in `backups/` by default. Both directories are gitignored.

## Requirements

- A Linux server with a public IP, ports 80 and 443 open inbound, and Docker Engine with the Compose plugin. `preflight.sh` fails without them, and the CLI install assumes both.
- DNS before the first start: `A` or `AAAA` for `<domain>` and `api.<domain>`, plus a wildcard `*.p.<domain>` for sandbox previews.
- `python3`, `tar` and `sha256sum`. The scripts decode JSON and archive with them.
- 2048MB free on `/` at minimum, which is the floor where `kortix-updater` stops.
- Roughly 6GB of RAM for the published limits alone, and 7.5GB before `preflight.sh` stops warning. The arithmetic is in [docs/checks.md](docs/checks.md).
- A Platinum API key in `PLATINUM_API_KEY`. Without it, sessions do not start.
- A model provider key per project, added in the web app after the first sign-in.

## What this does not do

The kit wraps the official CLI. `kortix self-host init` owns the stack, and every check reads what it wrote, so upgrade the CLI rather than this repo.

Self-hosted here means the control plane, the database and the files. Sessions run on Platinum sandboxes that `kortix-api` creates with your key, and each sandbox calls back to the instance's public `KORTIX_URL`. The scripts can prove that the callback resolves and that previews have their wildcard. They cannot tell you whether a sandbox provider is having a bad day, and in local mode there are no sessions to check at all.

This is not monitoring. Nothing pages anyone: `verify-all.sh` exits 1 and leaves the reading to you. On a server with several instances, run `doctor.sh <instance>` and `check-signup.sh --instance <instance>` for each; `verify-all.sh` covers one pass. The kit does not rotate secrets, manage TLS, or prune old archives.

## Where the rest of the setup lives

The full install path, every environment variable and the command list are in the [Kortix self-hosting docs](https://kortix.com/docs/developers#self-hosting). The same install is walked through in order at [selfhostedaiagents.com](https://selfhostedaiagents.com): the three DNS records, the five commands, the four failures that show up after the stack is up, and the update window. It is the long version of the Quickstart. The [Kortix blog](https://kortix.com/blog/self-hosted-ai-agents) covers what each check protects against on a live instance. The source is at [Kortix on GitHub](https://github.com/kortix-ai/CompanyOS).

If the question is which stack to run rather than how to check the one you have, [the same site compares six self-hosted installs](https://selfhostedaiagents.com/best-self-hosted-ai-agents) by what each one exposes on the server after the first minute: the Compose file, the ports, the sandboxing default and the licence each ships under.

Where each run’s computer actually comes from, and what a hosting choice leaves on your server, is set out at [AI agent hosting](https://selfhostedaiagents.com/ai-agent-hosting).

The monthly bill for that server — the service limits, the disk and the backups — is totalled at [what a self-hosted install costs](https://selfhostedaiagents.com/self-hosted-ai-agents-cost). If the open question is still framework or platform, [open source AI agents](https://selfhostedaiagents.com/open-source-ai-agents) separates the two by what you own after the install.

Two questions come up once the stack is up. What a held tool call waits for, who can release it and what the audit row keeps is set out at [agent approvals and the audit trail](https://selfhostedaiagents.com/self-hosted-agent-platform-approvals-audit). If the team works in Slack, [what a self-hosted Slack agent gateway has to decide](https://selfhostedaiagents.com/self-hosted-ai-agent-gateway-for-slack) covers which sandbox a thread gets, whose credentials it holds and who approves a write.

Self-host is free. The managed cloud is the same platform on someone else's servers, run by [Kortix](https://kortix.com), for teams that would rather not carry the pager.
