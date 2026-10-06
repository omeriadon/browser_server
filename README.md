# brower_server

Swift Vapor server for browser sync. The production process listens on
`127.0.0.1:4589`; Nginx publishes it at
`https://203.17.177.58:9644/`.

## Local development

Copy `.env.example` to `.env`, set the database password and session secret,
then run:

```bash
swift run
swift test
```

## Production deployment

Build from `/var/www/browser-sync` with Swift 6.3 or newer:

```bash
set -o pipefail
swiftly run swift build -c release --jobs 1 +6.3.3 2>&1 | \
  (command -v xcsift >/dev/null && xcsift -f toon -w || cat)
```

Create `/etc/browser-sync/environment.json` readable by the deployment user,
containing the variables from `.env.example` as JSON. Keep the file out of the
repository and restrict it to the service user, for example:

```json
{
  "APPLE_CLIENT_ID": "com.omeriadon.astra,com.omeriadon.astra.AstraWatch.watchkitapp",
  "SESSION_SECRET": "replace-with-a-long-random-secret",
  "DATABASE_HOST": "127.0.0.1",
  "DATABASE_PORT": "5432",
  "DATABASE_NAME": "browser_sync",
  "DATABASE_USERNAME": "browser_sync",
  "DATABASE_PASSWORD": "replace-with-the-role-password"
}
```

The PostgreSQL database and `browser_sync` role must already exist. Run the
release executable's migrations before starting the service. This loads the
protected JSON without putting credentials in the command line:

The production database connection is local loopback plaintext, while the
public browser-sync API is protected by Nginx HTTPS on port 9644.

Enable the port 80 server block from `deploy/nginx-browser-sync.conf` first.
Create the ACME webroot and request the IP certificate with the existing
Certbot account:

```bash
sudo install -d -o www-data -g www-data /var/lib/browser-sync-acme
sudo certbot certonly --webroot \
  -w /var/lib/browser-sync-acme \
  --ip-address 203.17.177.58 \
  --preferred-profile shortlived \
  --cert-name browser-sync-ip \
  --deploy-hook "systemctl reload nginx"
```

This reuses the installed Certbot account; no new email or terms-of-service
settings are required. The existing Certbot renewal timer renews the certificate
and reloads Nginx. Enable the full Nginx site after certificate issuance.

```bash
python3 - <<'PY'
import json
import os
import subprocess

with open("/etc/browser-sync/environment.json", encoding="utf-8") as file:
    environment = os.environ | json.load(file)

subprocess.run(
    [
        "/var/www/browser-sync/.build/release/brower_server",
        "migrate",
        "--env",
        "production",
        "--yes",
    ],
    env=environment,
    check=True,
)
PY
```

Install `deploy/ecosystem.config.cjs`, then start or reload it with PM2:

```bash
pm2 start deploy/ecosystem.config.cjs
pm2 save
```

Install `deploy/nginx-browser-sync.conf` as an Nginx site, then reload Nginx.

## Apple Watch sign-in

`APPLE_CLIENT_ID` accepts a comma-separated allowlist of Apple app identifiers.
Include `com.omeriadon.astra.AstraWatch.watchkitapp` for direct watch sign-in.
Enable Sign in with Apple for the watch App ID in Apple Developer and group it
with the primary `com.omeriadon.astra` App ID so both apps use the same Apple
subject and account snapshots. Apply the updated allowlist to the production
environment and reload the server after deployment.

## Git deployment

The `prod` remote is `rackmill:/var/repo/browser-sync.git`. Push with
`git push prod HEAD:main`. Its installed `deploy/post-receive` hook checks out
`main`, builds the release executable, runs migrations, and restarts PM2.
Build or migration failures stop deployment before the process restarts.

## AI provider

## Website monitoring

Authenticated `/v1/monitors` routes create, list, pause, and delete durable website
monitors. Daily, weekly, fortnightly, and calendar-monthly intervals are supported.
The server checks due monitors every minute, independent of any connected Mac.
Matched results remain available for clients to deliver notifications and pinned
space tabs when they reconnect. Notification delivery while Astra is quit requires
an APNs configuration; results are not lost when no client is running.

Monitoring uses OpenRouter only (`MONITOR_OPENROUTER_MODEL`, default
`openai/gpt-4o-mini`) and the existing account quotas. Public page text is extracted
with SwiftSoup. `/usr/bin/curl` must be installed: connections pin a validated public
DNS address, retain HTTPS hostname verification, check every redirect, and reject
local/private/reserved addresses, credentials, and nonstandard ports. Fetches have
size/time limits. Browser cookies and private page data are not sent to the server.

AI requests can opt into the OpenRouter web-search plugin with `webSearch: true`.

`POST /v1/ai/generate` and `POST /v1/ai/stream` require the same verified bearer session as sync.
Set `OPENROUTER_API_KEY` in the protected environment JSON for production or
the ignored `.env` for local development. Do not put it in app resources,
source files, Docker images, or shared settings. Restrict secret files to mode
`0600`. The existing PM2 configuration loads the JSON into the service; Docker
Compose forwards the environment variables at runtime.

`OPENROUTER_ALLOWED_MODELS` is a comma-separated model allowlist, defaulting
to `inclusionai/ling-3.1-flash,openai/gpt-4o-mini`. An empty allowlist disables every model. Missing or
empty keys disable cloud generation with HTTP 503 without disabling sync.

The request contains `modelID`, `instructions`, `prompt`, and
`maximumResponseTokens`, and optional `images` (name, mediaType, base64 data); the response contains `text`.
Images are forwarded as native OpenRouter image content. At most eight images totaling
10 MiB are accepted, and MIME types are checked against their file signatures. Request bodies are
limited to 20 MiB, prompts to 16 MiB UTF-8, instructions to 32 KiB UTF-8, and output
to 1–2,048 tokens. Unknown model IDs are rejected before contacting the
provider. Provider requests time out after 75 seconds; failures are sanitized
and never retried automatically. Truncated or empty completions are rejected.

Usage limits count attempts: 10 per minute and 100 per 24-hour window per
account, two concurrent requests per account, and eight across the process.
These limits are process-local and reset when the service restarts. Use a
shared quota store before deploying multiple workers or replicas. Set an
OpenRouter key spending limit separately for an account-wide cost ceiling.

The proxy uses OpenRouter's documented
[chat completion API](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion).
AI tests use a fake provider and require neither a real key nor PostgreSQL.

## Documentation

[Published documentation](https://omeriadon.github.io/browser_server/)
includes [feature development](docs/ai/adding-features.md),
[streaming semantics](docs/ai/streaming.md), and the
[server API](docs/server-api.md). GitHub Pages builds `main:/docs` with Jekyll.

The streaming endpoint sends cumulative text snapshots and a required final
event, or a sanitized terminal error. Both endpoints share authentication and
quotas. SSE responses disable Nginx buffering through `X-Accel-Buffering: no`.

[Browser and server wiki](https://omeriadon.github.io/browser_server/wiki/)
covers architecture, storage/recovery, sync, authentication, privacy, downloads,
extensions, website apps, settings/search, releases, diagnostics, and operations.
