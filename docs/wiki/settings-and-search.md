---
layout: default
title: Settings, search, and data import
nav_order: 9
parent: Browser guides
---

# Settings, search, and data import

[Wiki home](index.md)

`BrowserDefaults` defines preference keys and defaults. `BrowserSettingsSchema`
classifies portable and device-only keys, checks their separation, and owns
the reset operation.

## Adding a preference

Add the key to the existing Defaults definitions, wire it into the relevant
settings view, and decide explicitly whether it is portable. If portable,
include it in the sync allowlist and retain the per-key modification timestamp.
If device-only, keep it out of that list. Endpoint URLs, session credentials,
file bookmarks, and local developer/UI state are not portable preferences.

Reset browser settings is not clear browsing data. It resets the documented
preferences and site settings without deleting bookmarks, download files,
extension packages, or account identity. It also resets the chosen download
folder bookmark, so later file-access behavior can change.

## Search

Search configuration separates normal and private engines, supports built-in
engines and a validated custom template, and includes keyword shortcuts.
Private remote suggestions default off. Suggestions also depend on the global
setting and the current field/focus scope. Generation, query, provider, tab,
and navigation checks prevent stale requests from becoming current results.

## Import and export

`BrowserUserData` decodes JSON browsing-data exports and HTML bookmarks. Import
is bounded to 16 MiB and validates supported versions, record counts, IDs,
URLs, and timestamps before use. Imported records remain data, not permission
to execute `astra:` routes. A browsing-data export is not a complete backup of
cookies, credentials, downloaded files, or installed extensions.

Related: [sync](sync-and-conflicts.md), [storage](storage-and-recovery.md).

## Source entry points

- [BrowserDefaults.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserDefaults.swift)
- [BrowserSettingsSchema.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserSettingsSchema.swift)
- [BrowserSearchConfiguration.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Search/BrowserSearchConfiguration.swift)
- [BrowserSearch.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Search/BrowserSearch.swift)
- [BrowserUserData.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserUserData.swift)
