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
