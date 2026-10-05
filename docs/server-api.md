---
layout: default
title: Server API and deployment
---

# Server API and deployment

[Documentation home](index.md)

## Authentication

`POST /v1/auth/apple` exchanges an Apple identity token for an Astra session.
The server verifies Apple's signature, issuer, expiry, and allowed client ID.
Pass the resulting session token as `Authorization: Bearer <session>` to
both AI endpoints. The OpenRouter key is never a client credential.

## Request

Both endpoints accept `Content-Type: application/json`:

```json
{
  "modelID": "openai/gpt-4o-mini",
  "instructions": "Return a short description.",
  "prompt": "Describe this selected excerpt.",
  "maximumResponseTokens": 512
}
```

- `POST /v1/ai/generate`: complete JSON response with `text`.
- `POST /v1/ai/stream`: SSE cumulative snapshots with `text` and `isFinal`.

[Streaming wire format and completion rules](ai/streaming.md).

## Limits and status codes

Request bodies: 64 KiB. Combined prompt and instructions: 32 KiB UTF-8.
Output: 1–2,048 tokens. Models must match `OPENROUTER_ALLOWED_MODELS`.
Provider requests have a 75-second total timeout. No automatic retries.

| HTTP status | Meaning |
| --- | --- |
| 200 | JSON result or an open SSE stream; SSE still requires a final event |
| 400 | Invalid model, empty prompt, or invalid output limit |
| 401 | Missing, invalid, or expired Astra session |
| 413 | Request body exceeds the collection limit |
| 429 | Account/process quota or provider rate limit |
| 502 | Provider failure, invalid result, or failure before streaming starts |
| 503 | Cloud key is missing or empty |

After SSE headers are committed, failures use a sanitized terminal error
event and do not emit a successful final event.

Both response modes share limits: 10 attempts per minute and 100 per 24-hour
window per account, two concurrent requests per account, and eight across
one service process. Failures count as attempts. The quota store is process
local and resets on restart; use a shared store before adding replicas.
Set an OpenRouter key spending limit for a persistent account-wide ceiling.

## Configuration

Set `OPENROUTER_API_KEY` and `OPENROUTER_ALLOWED_MODELS` in the service's
protected `/etc/browser-sync/environment.json`. The default model allowlist
is `openai/gpt-4o-mini`. Preserve all existing database and authentication
configuration when adding the AI variables. Restrict the file to the service
user with mode `0600`. Local development reads an ignored `.env`; Compose
forwards the variables at runtime. Secrets never belong in docs or images.

PM2 reads the protected environment JSON. Nginx proxies loopback port 4589
to the existing HTTPS endpoint. SSE responses set `X-Accel-Buffering: no`;
keep the proxy read timeout at 90 seconds or longer.

Push the validated server commit to the production remote. The receive hook
builds the release executable, runs migrations, and restarts PM2 only after
those checks pass. Verify the deployed revision, health response, authenticated
single response, and authenticated streaming completion after deployment.

## Tests

```sh
set -o pipefail
swift test 2>&1 | xcsift -f toon -w
```

Tests use fake providers and require neither a real OpenRouter key nor
PostgreSQL. They cover sessions, validation, quotas, SSE byte boundaries,
Unicode, normal completion, truncation, and sanitized midstream failures.

## References

- [OpenRouter chat completions](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion)
- [OpenRouter streaming](https://openrouter.ai/docs/api_reference/streaming)
- [Vapor response streaming source](https://github.com/vapor/vapor/blob/main/Sources/Vapor/Response/Response%2BBody.swift)
