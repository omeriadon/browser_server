---
layout: default
title: Sync and conflict resolution
nav_order: 3
parent: Browser guides
---

# Sync and conflict resolution

[Wiki home](index.md)

Astra keeps a local cache and synchronizes a versioned `BrowserSyncDocument`.
The client merges documents; the server stores one snapshot per Apple subject
and device ID. A server revision is transport metadata, not the winner for
every individual browser item.

## Merge rules

Stable IDs identify records. Modification timestamps choose between competing
versions of tabs, bookmarks, reading-list entries, history, spaces, and
portable settings. Timestamped deletion records prevent older snapshots from
resurrecting deleted data. Workspace ordering and selection have their own
merge handling. New fields must preserve backward decoding and deletion rules.

Before uploading, the projection removes local-only tab state, file-access
bookmarks, peeks, restoration data, and nonportable URLs. It strips URL
credentials. Only allowlisted preferences may leave the device.

## Request flow

After hydration, the signed-in client fetches snapshots, validates supported
versions and structure, merges them with local data, protects edits made while
the request was in flight, persists the result, and uploads its current device
snapshot when needed. Generation and endpoint checks reject stale account work.

Transient GET/PUT failures can retry. Authentication and AI POST requests do
not automatically retry. Offline browser data remains local; a sync error is
not an instruction to clear it.

## Payload limit mismatch

The current client allows a 16 MiB raw outgoing payload, but the server accepts
at most **5,000,000 raw bytes** and a 7 MB collected JSON body. Base64 encoding
also enlarges the request. Large documents can therefore fail server validation
even when the client accepts them. Use the server limit when diagnosing HTTP
413; the local copy is not a disposable cache.

Related: [authentication](authentication.md), [settings](settings-and-search.md).

## Source entry points

- [BrowserSyncDocument.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Core/BrowserSyncDocument.swift)
- [BrowserSync.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserSync.swift)
- [routes.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/routes.swift)
- [SyncSnapshot.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/Models/SyncSnapshot.swift)
