---
layout: default
title: Astra wiki
---

# Astra wiki

Source-based reference for browser development and operations. The app baseline
is commit `8652ae2`; AI manager additions remain in the separate AI worktree.
The server AI implementation is deployed from `2b6d558`. These pages explain
implemented behavior and its limits, not blanket runtime certification.

## Browser internals

| Guide | Covers |
| --- | --- |
| [Architecture and ownership](architecture.md) | Window, tab, WebView, session, and space ownership |
| [Storage, startup, and recovery](storage-and-recovery.md) | Snapshots, startup hydration, encryption boundaries, and recovery |
| [Sync and conflict resolution](sync-and-conflicts.md) | Merges, deletion records, portable state, and payload limits |
| [Authentication and credentials](authentication.md) | Apple sign-in, device sessions, and website authentication |
| [Privacy, permissions, and internal URLs](privacy-and-permissions.md) | Private sessions, permission scope, and privileged routes |
| [Downloads and file access](downloads.md) | File access, resume, segmented transfers, and AI naming |
| [Extensions and content blocking](extensions-and-content-blocking.md) | Extension adapters, compatibility, and native rules |
| [Website apps and Mini Astra](website-apps.md) | Helper installation, Mini Astra, Dock behavior, and signing |
| [Settings, search, and data import](settings-and-search.md) | Preference schema, suggestions, and import/export |
| [Releases, signing, and updates](releases-and-updates.md) | Release triggers, signing, notarization, and Sparkle |
| [Diagnostics, troubleshooting, and verification](diagnostics-and-verification.md) | Safe reports, troubleshooting, and evidence levels |
| [Server configuration and operations](server-operations.md) | Environment, deployment, quotas, and service failures |

## AI development

- [AI manager and model selection](../ai-features.md)
- [Adding a feature](../ai/adding-features.md)
- [Streaming and single responses](../ai/streaming.md)
- [Server API](../server-api.md)

## Maintaining these pages

Update the relevant guide when a behavior, data format, limit, or ownership rule
changes. Follow the source links and record the reviewed revision. Distinguish
source completion, build evidence, deployed-server checks, and manual app
acceptance. Keep unresolved capability gates explicit. Never add secret values,
user browsing data, or unverified release claims.

The browsable wiki is published through the existing GitHub Pages site from
`browser_server/main:/docs`. Documentation-only updates go to GitHub; they do
not need a production service restart. Markdown copies also live in the app's
AI worktree under `docs/wiki`.
