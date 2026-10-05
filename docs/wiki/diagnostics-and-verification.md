---
layout: default
title: Diagnostics, troubleshooting, and verification
---

# Diagnostics, troubleshooting, and verification

[Wiki home](index.md)

Diagnostic reports export bounded browser metadata rather than page content.
`BrowserDiagnosticReport` has schema 1, a 32 KiB encoded limit, and at most 64
recent events. Codes are restricted to a short safe character set.

Normal reports include version/build, OS and WebKit information, counts, and
sanitized failure categories. Private reports omit tab counts, failure details,
and events. Private activity does not enter the shared event store. Do not add
URLs, titles, cookies, tokens, prompts, or page text to diagnostic payloads.

## Choose the right evidence

| Check | Establishes |
| --- | --- |
| Source inspection | Implemented branches and ownership rules |
| Xcode MCP build | Compilation for the selected scheme/destination |
| Server unit tests | Contracts exercised with controlled providers |
| Live endpoint check | Deployed server behavior for the checked request |
| Manual app acceptance | Behavior observed on the tested OS/device |

The roadmap and handoff ledgers contain historical implementation evidence.
Their presence is not current runtime certification. This documentation pass
inspects source and links; it does not run Astra or certify all browser features.

For browser problems, record normal/private scope, app/OS version, feature,
error category, and reproduction steps. Check existing narrow assets under
`checks/` and the roadmap runtime-verification ledger before inventing a new
harness. Avoid destructive data resets as a diagnosis step.

For AI errors, distinguish sign-in, local model availability, rejected input,
HTTP status, partial-stream failure, and quota exhaustion. Partial text after
an error is not a successful result.

Related: [recovery](storage-and-recovery.md), [server operations](server-operations.md).

## Source entry points

- [BrowserDiagnosticReport.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/App/BrowserDiagnosticReport.swift)
- [BrowserDiagnostics.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/App/BrowserDiagnostics.swift)
- [RUNTIME_VERIFICATION.md](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/docs/astra-roadmap/RUNTIME_VERIFICATION.md)
