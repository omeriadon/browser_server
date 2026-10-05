---
layout: default
title: Downloads and file access
nav_order: 6
parent: Browser guides
---

# Downloads and file access

[Wiki home](index.md)

`BrowserDownloadManager` owns download lifecycle, destinations, resume state,
progress, and user-facing items. `WKDownload` remains the baseline transfer
path. The segmented engine is an optional acceleration path with separate
eligibility and replay restrictions.

## File lifecycle

Suggested names are sanitized, destinations are selected under the user's
file-access permissions, and collisions receive unique destinations. Files
are committed through the manager's existing finalization path. Security-scoped
folder and file bookmarks are device-local capabilities, not sync data.
Preview, drag, and reopen operations must hold the required access for their
full lifetime.

Download failure can retain WebKit resume data. Pause, retry, resume, quit,
and relaunch are distinct states; lack of resume data is a visible limitation,
not evidence that a partial file is complete. Unreadable saved download state
is preserved instead of silently replaced.

## Segmented transfers

The range path sends `Range`, `If-Range`, and identity encoding. It requires
stored segment metadata and a range validator. Replay excludes authorization,
cookies, and browser-managed headers. Redirects that change the segmented
transfer destination trigger failure/fallback rather than unrestricted replay.
Do not apply acceleration indiscriminately to authenticated downloads.

## Private downloads and AI

Private sessions use a separate manager and staging lifecycle. Explicitly
saved files can remain on disk after a private session; clearing private
metadata is not a promise to erase user-selected files.

The AI worktree delegates filename generation to `BrowserDownloadNamingFeature`.
It stays on-device, requires sign-in, respects the existing setting, and skips
private and file-scoped destinations. Existing collision and extension
handling still run after feature output validation.

Related: [AI features](../ai-features.md), [privacy](privacy-and-permissions.md).

## Source entry points

- [BrowserDownloadManager.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Downloads/BrowserDownloadManager.swift)
- [SegmentedDownloadEngine.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Downloads/SegmentedDownloadEngine.swift)
- [BrowserDownload.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Library/BrowserDownload.swift)
