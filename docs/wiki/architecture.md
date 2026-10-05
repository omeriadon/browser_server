---
layout: default
title: Architecture and ownership
---

# Architecture and ownership

[Wiki home](index.md)

Astra is a SwiftUI browser built around system WebKit. WebKit owns page rendering,
JavaScript, web storage, protocol networking, and engine security. Astra owns
browser organization, native interfaces, application policy, and persistence.

## Code map

| Component | Responsibility |
| --- | --- |
| `Browser` | A window's tabs, selection, spaces, bookmarks, history, and mutations |
| `BrowserTab` / `OpenTab` | Live tab behavior / serializable tab state |
| `BrowserController` | WebView navigation, delegate behavior, and page state |
| `BrowserWebSession` | Website data store and session-scoped services |
| `BrowserWindowRegistry` | Window registration and shared-tab display ownership |
| `BrowserWorkspace` / `BrowserSpace` | Space membership, pins, ordering, and selection |
| `BrowserPersistence` | Local snapshots, migration, and recovery |
| `BrowserSync` | Account authentication and synchronization transport |

Normal windows use the shared web session. Private windows create a separate
session. Mini Astra does not participate in the normal window persistence and
sync path. A shared normal tab can appear in several windows, but the registry
coordinates which window owns its live display; duplicating a WebView is not
the mechanism for mirroring it.

## Extending the browser

Put durable mutations in the existing model owner. Keep rendering and delegate
logic with its controller, and session policy with the session service. Preserve
stable tab and window IDs. Adding a window or UI surface must account for focus,
selected-tab ownership, teardown, and private browsing.

The AI manager is a separate feature execution boundary. Its implementation
currently lives in the AI worktree; the cloud server is deployed. Read
[the AI overview](../ai-features.md) before adding AI-specific execution code.

Related: [storage](storage-and-recovery.md), [sync](sync-and-conflicts.md),
[privacy](privacy-and-permissions.md).

## Source entry points

- [Browser.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Core/Browser.swift)
- [BrowserWindowRegistry.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Core/BrowserWindowRegistry.swift)
- [BrowserWebSession.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Navigation/BrowserWebSession.swift)
