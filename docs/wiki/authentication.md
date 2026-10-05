---
layout: default
title: Authentication and credentials
nav_order: 4
parent: Browser guides
---

# Authentication and credentials

[Wiki home](index.md)

Astra account sign-in and a website's sign-in are separate systems.

## Astra account session

The app sends an Apple identity token to `POST /v1/auth/apple`. The server
verifies Apple's signature, issuer, expiry, and configured audience allowlist,
then issues an Astra session. `APPLE_CLIENT_ID` accepts comma-separated allowed
app identifiers. Session tokens currently expire after 90 days.

The client stores the session in Keychain, separately records which normalized
server endpoint issued it, and binds subsequent requests to that endpoint.
Changing servers invalidates the local signed-in state. HTTP 401 signs the
client out. Signed-in UI state alone is not proof a server token is still valid.

Sign-out removes the device's token. There is no current server-side session
revocation endpoint, so it must not be described as global token revocation.
Sync and cloud AI routes use the same verified bearer middleware.

## Website authentication

`BrowserAuthenticationPolicy` handles supported HTTP authentication methods
and limits repeated credential failures. Other challenge types use default
engine handling; do not replace system TLS validation with custom acceptance.
Browser authentication-session callbacks are tied to the active generation,
request, and window so stale pages cannot complete a different session.

Website passwords, cookies, Astra session tokens, and the server's OpenRouter
key are not interchangeable. Do not put any of them in portable settings or
ordinary browsing-data exports.

Related: [privacy](privacy-and-permissions.md), [server operations](server-operations.md),
[AI API](../server-api.md).

## Source entry points

- [BrowserSessionStore.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserSessionStore.swift)
- [SyncServerAddress.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/SyncServerAddress.swift)
- [BrowserAuthenticationPolicy.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Navigation/BrowserAuthenticationPolicy.swift)
- [BrowserAuthentication.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/Authentication/BrowserAuthentication.swift)
