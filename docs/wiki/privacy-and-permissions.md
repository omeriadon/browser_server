---
layout: default
title: Privacy, permissions, and internal URLs
nav_order: 5
parent: Browser guides
---

# Privacy, permissions, and internal URLs

[Wiki home](index.md)

Private browsing uses a nonpersistent WebKit data store plus separate downloads,
favicons, permissions, site preferences, toast state, and content-blocking state.
Private browsers are excluded from normal persistence, window restoration,
account sync, and extension tab exposure. Ending the session cancels private
download work and clears its website data and temporary services.

Private browsing is a storage/session boundary. It does not hide network
traffic from the website or make cloud requests anonymous.

## Website permissions

Permission records are keyed by requesting origin, top-level origin, and
capability. Decisions include allow once, allow always, and deny. Temporary
permissions are distinct from saved records; private permissions are not
written to the normal permission store. Camera/microphone permission changes
can stop capture in affected controllers. Resetting permissions and clearing
website data are separate operations.

A capability appearing in the permission model is not proof that the installed
WebKit host can implement it. In particular, the existing Web Push investigation
records a system-daemon authorization boundary. Do not present native
notifications as equivalent website Web Push.

## Privileged routes

`astra:` destinations are accepted only from trusted UI or operating-system
sources. Web content, extensions, and imported data cannot invoke privileged
internal routes. The parser validates scheme, host, path, and query fields.

Custom external-app schemes use the navigation policy. HTTP/HTTPS links remain
with WebKit's ordinary navigation and platform app-link decisions. Preserve
confirmation ownership and invalidate stale prompts when navigation changes.

Related: [extensions](extensions-and-content-blocking.md), [authentication](authentication.md).

## Source entry points

- [BrowserWebSession.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Navigation/BrowserWebSession.swift)
- [BrowserSitePermissions.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Navigation/BrowserSitePermissions.swift)
- [BrowserInternalURL.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Navigation/BrowserInternalURL.swift)
- [web-push-and-app-links.md](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/docs/web-push-and-app-links.md)
