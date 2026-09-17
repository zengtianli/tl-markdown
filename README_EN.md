# Folio

[中文](README.md) | **English**

[Product homepage, download and guide](https://app-mac-folio.tianli.cyou/)



A local Markdown editor for macOS with a SwiftUI window and a bundled WebKit single-pane live editor. Swift handles files, autosave and recovery. Earlier native-only memory measurements do not describe this version.

## Use

Open with Cmd+O, save with Cmd+S, find with Cmd+F. Named files autosave; drafts and recent-file history recover locally. Tables, reference links, images, math and diagrams render directly in the editor. Click a block to edit its Markdown; move to another block to render it again. Source mode preserves the original text.

Cmd+Shift+P optionally opens a second read-only live preview for side-by-side reading. Ordinary editing does not require it.

## Build and verify

Install preview build dependencies with `cd Editor && npm ci`, then run `bash build.sh --install` from the repository root. `bash scripts/test.sh` checks file IO, native editing and the optional preview independently. The app installs at `/Applications/Folio.app`.

Builds reuse the headquarters Xcode selector, CodingKey checker and icon factory. Runtime needs no Node, Python or server.

## Compatibility

The repository now lives at `~/Apps/folio`. The existing bundle ID `cyou.tianli.TLMarkdown` and `~/Library/Application Support/TLMarkdown/session.json` remain compatible, preserving file associations and saved sessions. Chinese UI labels are retained; the product name is Folio in both languages.
