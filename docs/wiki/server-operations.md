---
layout: default
title: Server configuration and operations
---

# Server configuration and operations

[Wiki home](index.md)

The Vapor service provides Apple sign-in, device snapshots, and OpenRouter
proxying. PostgreSQL stores snapshots; cloud AI uses the server's provider key.
Sync payloads are not end-to-end encrypted against this server.

## Runtime configuration

| Variable | Purpose |
| --- | --- |
| `APPLE_CLIENT_ID` | Allowed Apple app audiences |
| `SESSION_SECRET` | Server session signing; at least 32 bytes |
| `DATABASE_HOST`, `DATABASE_PORT` | PostgreSQL connection location |
| `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` | Database access |
| `OPENROUTER_API_KEY` | Provider credential kept only on the server |
| `OPENROUTER_ALLOWED_MODELS` | Comma-separated model allowlist |

Production PM2 reads a protected environment JSON file. Local development uses
an ignored `.env`; Compose forwards variables at runtime. Keep secret files
restricted to the service user. Missing AI keys disable cloud generation with
503 while leaving sync routes available.

The server listens on loopback behind Nginx HTTPS. SSE disables buffering and
the proxy read timeout is 90 seconds. Both AI endpoints share account/process
quotas; they reset on restart and are not a multi-replica quota system.

## Deployment and troubleshooting

The production receive hook checks out the accepted revision, builds release
code, runs migrations, and restarts PM2 after those steps succeed. Verify all
stages, the deployed revision, health, and both response modes. Fix code/build
errors before another push; unchanged infrastructure failures are not helped
by repeated pushes.

401 means an Astra session problem, not an OpenRouter key prompt. 429 can be
local quota or provider throttling. 502 is a sanitized provider/protocol failure.
503 means cloud AI is unconfigured. SSE can fail after HTTP 200; require its
final event. For 413 sync errors, check the client/server limit mismatch.

Related: [AI API](../server-api.md), [sync](sync-and-conflicts.md),
[authentication](authentication.md).

## Source entry points

- [configure.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/configure.swift)
- [BrowserAIService.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/AI/BrowserAIService.swift)
- [post-receive](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/deploy/post-receive)
- [ecosystem.config.cjs](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/deploy/ecosystem.config.cjs)
