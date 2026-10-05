---
layout: default
title: Releases, signing, and updates
---

# Releases, signing, and updates

[Wiki home](index.md)

Desktop release work separates unsigned PR verification from distribution.
Release branches follow `release/<version>+<build>`. The publication workflow
runs when a matching release PR merges; an ordinary documentation push is not
a desktop release.

## Distribution stages

The existing pipeline prepares temporary signing credentials, archives and
exports with Developer ID, validates signed capabilities, notarizes and staples
the app and DMG, and signs the Sparkle update archive. Missing credentials or
failed signature/capability checks stop publication. There is no ad-hoc
production-signing fallback.

Secret names and setup are documented in the existing desktop-release guide.
Keys and certificate contents belong in repository secrets, not workflow
source or documentation. Temporary keychain/profile cleanup runs even after
failure.

The artifact validator checks sandbox and networking capabilities, file access,
Sign in with Apple, Hardened Runtime, expected team, secure update feed,
quarantine, and constrained ATS exceptions. A successful unsigned archive does
not prove those exported capabilities exist.

## Updater

`UpdateManager` owns Sparkle status and user choices. Automatic checks and
automatic downloads are connected preferences. Preserve its callbacks when
changing presentation; displayed progress is not a completed installation.

Fresh-Mac Gatekeeper launch, offline stapled-ticket launch, and a sandboxed
update from an older signed build remain separate runtime acceptance cases.
Failed or canceled updates must preserve the installed app and browsing data.

Related: [verification](diagnostics-and-verification.md),
[website apps](website-apps.md).

## Source entry points

- [desktop-release.md](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/docs/desktop-release.md)
- [publish-release.yml](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/.github/workflows/publish-release.yml)
- [validate_artifact.py](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/scripts/release/validate_artifact.py)
- [UpdateManager.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/App/UpdateManager.swift)
