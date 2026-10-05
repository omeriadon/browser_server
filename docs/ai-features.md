---
layout: default
title: AI features
---

# AI features

`BrowserAI.shared` runs isolated AI features with single and streaming responses. Both providers
require an Astra account session. Apple Intelligence runs locally; OpenRouter
runs through the configured Astra server. Providers never switch automatically.
Signing out or changing servers invalidates pending results.

## Guides

- [Adding an AI feature](ai/adding-features.md)
- [Streaming and single responses](ai/streaming.md)

## Models

```swift
let local: BrowserAIModel = .appleIntelligence
let cloud: BrowserAIModel = .openRouter()
let selected: BrowserAIModel = .openRouter(modelID: "openai/gpt-4o-mini")
```

The default OpenRouter model is `openai/gpt-4o-mini`. The server must allow a
model ID before clients can use it. The app never contains an OpenRouter key.

## Adding a feature

Implement `BrowserAIFeature` under `astra/AI/Features`. Define its input and
output, default model, request instructions, prompt, output token limit, and
output validation. Then call the manager:

```swift
let stem = try await BrowserAI.shared.perform(
    BrowserDownloadNamingFeature(),
    input: .init(original: "report_2026", source: "example.com", fileType: "pdf")
)
```

The optional `model:` argument overrides a feature's default explicitly. A
feature owns decisions about what data may leave the device. Cloud features
must be deliberate user actions with clear data disclosure; do not silently
send private page content or automatically fall back from on-device to cloud.

Prompts and instructions have a combined 32 KiB UTF-8 limit. Output limits are
1–2,048 tokens. Handle `BrowserAIError`, provider errors, and task cancellation
at the feature's caller. Treat output as untrusted data; validation belongs in
`output(from:)`, before applying any change.

Download naming remains on-device and retains the existing setting, filename
sanitization, extension preservation, collision handling, and private-download
exclusion. Signed-out users now keep the original downloaded filename.

## Server

`POST /v1/ai/generate` and `POST /v1/ai/stream` use the existing Astra bearer session. Its JSON body is:

```json
{
  "modelID": "openai/gpt-4o-mini",
  "instructions": "Return a short filename stem.",
  "prompt": "Original filename: report_2026",
  "maximumResponseTokens": 128
}
```

The response is `{ "text": "Annual Report 2026" }`. The server owns provider
credentials, allowlisting, quotas, and provider error sanitization. See the
server README for configuration and deployment constraints.
