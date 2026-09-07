# Folio

[中文](README.md)

A lightweight local Markdown editor for macOS. SwiftUI and AppKit provide the default native editing path; no WebKit process is created during ordinary editing.

## Use

Open with Cmd+O, save with Cmd+S, find with Cmd+F. Named files autosave; drafts and recent-file history recover locally. Local standalone images use bounded thumbnail caching. Tables remain monospaced Markdown in the native editor.

Cmd+Shift+P opens an optional read-only WebKit snapshot for tables, math, Mermaid and richer syntax. Close and reopen to refresh it; helper-process reclamation is controlled by macOS.

## Build and verify

Install preview build dependencies with `cd Editor && npm ci`, then run `bash build.sh --install` from the repository root. `bash scripts/test.sh` checks file IO, native editing and the optional preview independently. The app installs at `/Applications/Folio.app`.

Builds reuse the headquarters Xcode selector, CodingKey checker and icon factory. Runtime needs no Node, Python or server.

## Compatibility

The existing bundle ID `cyou.tianli.TLMarkdown`, repository directory and `~/Library/Application Support/TLMarkdown/session.json` remain unchanged. Renaming does not change the default Markdown file association. Chinese UI labels are retained; the product name is Folio in both languages.
