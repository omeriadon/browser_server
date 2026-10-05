---
layout: default
title: Extensions and content blocking
---

# Extensions and content blocking

[Wiki home](index.md)

Astra hosts web extensions through `WKWebExtensionController` and exposes
browser windows and tabs through adapter types. Compatibility is bounded by
WebKit's extension APIs; importing a Chrome package does not implement every
Chrome API or guarantee that every store extension works.

## Extension ownership

The extension manager owns preparation, installed/enabled package state,
contexts, actions, and load errors. Tab adapters require the tab to belong to
the expected browser and exclude private browsers and native internal pages.
Window registration, activation, updates, and removal must stay synchronized
with browser ownership; a stale adapter must not act on another tab.

Package parsing, installation, enabled state, and successful context loading
are separate steps. Use the recorded context errors when diagnosing an
extension. Do not treat a package being installed as runtime compatibility.

## Native content rules

Native blocking uses validated JSON compiled into `WKContentRuleList` objects.
The source has a 2 MB import bound. Preparation can reuse compiled rules;
site exceptions and source changes notify affected controllers. Private
sessions have separate rule-store cleanup.

Unsupported persisted rule records are preserved in read-only state. Invalid
sources produce a visible validation error. Do not rewrite unknown versions
or replace failed imports with an empty list as a silent success.

These native rules and extension-based blockers are different mechanisms.
When a site fails, identify which is active, inspect the relevant exception,
and compare with the rule source/context error before changing unrelated
navigation behavior.

Related: [privacy](privacy-and-permissions.md), [diagnostics](diagnostics-and-verification.md).

## Source entry points

- [BrowserExtensionManager.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Extensions/BrowserExtensionManager.swift)
- [ChromeExtensionPackage.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/Extensions/ChromeExtensionPackage.swift)
- [BrowserContentBlocking.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Web/ContentBlocking/BrowserContentBlocking.swift)
