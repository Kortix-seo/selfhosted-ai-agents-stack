# Install self-hosted AI agents from an open-source stack

Kortix is the open-source CompanyOS, and a self-hosted instance is the full platform on a server you control. The order below works, and each step names the failure a wrong answer leaves behind.

## Point DNS at the server first

Three records, all at the same address. Each one fails differently when it is wrong:

| Name | Type | Value |
| --- | --- | --- |
| `<domain>` | A or AAAA | the server's public IP |
| `api.<domain>` | A or AAAA | the same address |
| `*.p.<domain>` | A or AAAA | the same address |

Caddy asks for a certificate on the first request, so the apex record has to resolve before `start`. A sandbox calls back to `KORTIX_URL` at `api.<domain>`, and with no record there it never starts. The wildcard carries previews. Without it, previews fall back to a path proxy that breaks root-absolute links, and the doctor fails `preview-origins`.

Verify with `./bin/preflight.sh kortix.example.com`: it resolves the apex, `api.` and a random label under `*.p.`, checks ports 80 and 443, and stops on a missing record. Run it again after any DNS or proxy change.

## Install the CLI and initialise the instance

```bash
curl -fsSL https://kortix.com/install | bash
kortix self-host init --domain kortix.example.com --admin-email you@example.com
```

`init` writes `docker-compose.yml`, `.env`, a `Caddyfile` and `updater.sh` into `~/.config/kortix/self-host/default/`. `--instance <name>` picks another directory, and `KORTIX_SELF_HOST_CONFIG_DIR` moves the whole root. One Compose project, `kortix-<instance>`, holds every service.

Only addresses in `KORTIX_PLATFORM_ADMIN_EMAILS` reach `/admin`, and the value is a whole comma-separated list, so correcting a typo means repeating every address.

## Answer configure, then start

```bash
kortix self-host configure
kortix self-host start
```

`configure` asks the setup questions again. Three answers matter: the admin address, `PLATINUM_API_KEY`, and the preview domain `p.kortix.example.com`. It writes files only, so a run with no `start` after it changes nothing.

Without a Platinum key the stack still starts and sessions do not. `init` prints a warning and continues.

## First sign-in, in this order

1. Open `https://kortix.example.com` and sign up with an address from `KORTIX_PLATFORM_ADMIN_EMAILS`. A SAML login never matches that list, so use a password or email-code sign-up here.
2. Connect GitHub at `/admin/git`. Choose Create a GitHub App, paste an existing App, or use an access token. Until this is set, Kortix cannot create project repositories.
3. Create a project at `/new`, then open the project menu, Switch Project, Create an account. The sign-up account is personal: it cannot hold SAML SSO, and a project cannot move between accounts later.
4. In the project, add a model key under Customize, Models, Providers, or run `kortix providers set <provider>`. Each project keeps its own key.
5. Invite the team from the team account.

Skipping step 2 leaves every new project without a repository; skipping step 3 leaves SSO unavailable.

## Close sign-up, or require an email

Until `EMAIL_URL` is set or `DISABLE_SIGNUP=true`, anyone who reaches the instance can create a confirmed account for any address, the admin address included. Sign in as the admin first, then pick one of the two:

```bash
kortix self-host env set DISABLE_SIGNUP=true
kortix self-host start
./bin/check-signup.sh https://kortix.example.com
```

Or set an email connection string, which turns automatic confirmation off and makes every new address prove itself with a message:

```bash
kortix self-host env set EMAIL_URL=smtp://user:password@smtp.example.com:587
```

The accepted forms are `smtp://user:pass@host:587`, `smtps://…:465`, `resend://<api-key>`, `ses://<key-id>:<secret>@<region>`, `ses://<region>` and `mailtrap://<api-token>`.

`--disable-signup` at `init` time closes sign-up from the first start, and it locks out the admin too. `check-signup.sh` exits 0 when the door is closed or email-verified, 1 when it is open, and 2 when it cannot tell. Add `--instance <name>` to read `.env` directly when the API is not answering.

## Take the first backup

```bash
sudo ./bin/backup.sh default /var/backups/kortix
```

It stops the stack so the Postgres files are consistent, archives the whole instance directory, and restarts through an `EXIT` trap. It refuses to run without `API_KEY_SECRET` in `.env`, the key that makes restored credentials readable. Copy the `.tgz`, its `.sha256` and its `.manifest.json` off the server.

## Read the first doctor

```bash
./bin/doctor.sh default
```

Seven checks, a report under `reports/`, and a fix line per failure. Exit 0 means all seven passed.

| Step | Script | Signal to expect |
| --- | --- | --- |
| DNS | `preflight.sh <domain>` | `preflight passed` |
| Stack | `doctor.sh` | `7/7 passed` |
| Sign-up | `check-signup.sh <url>` | `CLOSED` |
| Backup | `backup.sh` | `API_KEY_SECRET fingerprint` |
| Restore drill | `restore.sh` | `checksum matches` |
| Weekly | `verify-all.sh <url>` | exit 0 |

The variables behind every step, and the behaviour of the updater, are in the [Kortix self-hosting docs](https://kortix.com/docs/host).
