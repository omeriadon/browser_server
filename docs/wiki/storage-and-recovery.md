---
layout: default
title: Storage, startup, and recovery
nav_order: 2
parent: Browser guides
---

# Storage, startup, and recovery

[Wiki home](index.md)

Local browser state is stored under Application Support in a directory derived
from the running bundle identifier. Do not hard-code another app's data path.

## Files and formats

| Data | Representation |
| --- | --- |
| Browser state | Versioned `browser-state.json` envelope; current schema 3 |
| Recovery copy | `browser-state.backup.json` |
| Shutdown marker | `browser-shutdown.json` |
| Reading-list archives | Bounded files under `reading-list/` |
| Account session | Device-only Keychain item |
| WebKit restoration state | URL-bound encrypted blobs using a Keychain key |

The persistence loader tries the primary state and then its backup. Unsupported
future versions stop loading rather than being silently rewritten. Corrupt
state is preserved and reported. Saving validates the snapshot before an
atomic write. Legacy separate tab, bookmark, and workspace files are removed
only after the current snapshot has been written.

The app starts with placeholder state and hydrates disk data asynchronously.
The hydration gate prevents early writes and sync from treating incomplete
startup state as authoritative. Preserve this gate when adding stored data.

## Encryption boundary

`BrowserRestorationStore` uses AES-GCM with the page URL as authenticated data
and a device-only Keychain key. This protects the restoration blob. It does
not mean the entire JSON snapshot, website data store, or server sync payload
is end-to-end encrypted.

## Recovery procedure

Copy the existing state and backup before attempting manual recovery. Record
the error and format version. Check the backup without replacing newer-format
files with defaults. A successful build does not establish crash-recovery
behavior; corrupted-state and unexpected-quit cases require runtime acceptance.

Related: [sync](sync-and-conflicts.md), [diagnostics](diagnostics-and-verification.md).

## Source entry points

- [BrowserPersistence.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserPersistence.swift)
- [BrowserRestorationStore.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserRestorationStore.swift)
- [Browser.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Core/Browser.swift)
