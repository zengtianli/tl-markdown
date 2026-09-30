import Foundation
import Darwin

@main enum GraphEngineTests {
    static func main() throws {
        let fm = FileManager.default
        let temporary = realpath(fm.temporaryDirectory.path, nil)!
        let root = URL(fileURLWithPath: String(cString: temporary)).appendingPathComponent("folio-graph-tests-" + UUID().uuidString)
        free(temporary)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fputs("FAIL \(label)\n", stderr); exit(1) }
            checks += 1; print("PASS \(label)")
        }
        func write(_ path: String, _ content: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        func payload(_ url: URL) throws -> [String: Any] {
            let html = try String(contentsOf: url, encoding: .utf8)
            let prefix = "<script id=\"data\" type=\"application/json\">"
            guard let from = html.range(of: prefix), let to = html.range(of: "</script>", range: from.upperBound..<html.endIndex) else { fatalError("missing payload") }
            return try JSONSerialization.jsonObject(with: Data(html[from.upperBound..<to.lowerBound].utf8)) as! [String: Any]
        }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); check(false, label) } catch { check(true, label) }
        }
        try write("README.md", """
        ---
        name: Folder overview
        tags: ["#alpha", second]
        relations:
          - type: explains
            target: docs/detail.md
            label: Details
        ---
        # Overview
        [Read details](docs/detail.md)
        [[detail]]
        [Ignored](https://example.invalid/no-fetch)
        ```markdown
        [Ignored code](ghost.md)
        ```
        | # | Name | File |
        | -- | ---- | ---- |
        | 1 | Detail item | [read](docs/detail.md) |
        """)
        try write("docs/detail.md", "# Detail\nSynthetic fixture\n")
        try write("docs/图 文.markdown", "# Unicode\n")
        try write(".hidden/private.md", "# Should not be read\n")
        try write("node_modules/skip.md", "# Should not be read\n")
        try write("excluded/skip.md", "# Should not be read\n")
        try write("quiet/skip.md", "# Should not be read\n")
        try write("temp-old/skip.md", "# Should not be read\n")
        try write("cache-area/skip.md", "# Should not be read\n")
        try write("notes-摘录区-2026/skip.md", "# Should not be read\n")
        try write("text-only/visible.md", "# Graph visible, excluded from full text\n")
        try write("catalog.yaml", """
        display_name: Catalog title
        tags: [folder]
        knowledge_graph:
          nodes:
            - id: topic:guide
              name: A topic
              description: |
                First line
                Second line
              tags: [alpha]
              sources:
                - path: README.md
                  title: Source
            - id: doc:overview
              path: README.md
              name: Overview record
              table_rows: true
            - id: doc:detail
              path: docs/detail.md
          edges:
            - source: topic:guide
              target: doc:overview
              label: Explains
              both: true
              sources: [{path: README.md, note: "Curated"}]
          overview: [topic:guide, doc:overview]
        """)
        try write("project.yaml", "display_name: Selected folder\n")
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("linked.md").path, withDestinationPath: root.appendingPathComponent("docs/detail.md").path)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("linked-dir").path, withDestinationPath: root.appendingPathComponent("docs").path)
        _ = mkfifo(root.appendingPathComponent("pipe.md").path, 0o600)
        var config = FolioIndexConfig()
        config.skipPaths = [root.appendingPathComponent("excluded").path]
        config.fullTextExcludedPaths = [root.appendingPathComponent("text-only").path]
        config.restrictedNames = ["QUIET"]
        config.restrictedPrefixes = ["cache-"]
        config.restrictedSubstrings = ["摘录区"]
        config.skipDirectorySuffixes = ["-old"]
        let output = try FolioGraphEngine.generate(root: root, launcher: true, config: config)
        let result = try payload(output)
        let nodes = result["nodes"] as! [String: [String: Any]]
        let atlas = result["atlas"] as! [String: Any]
        let aliases = atlas["aliases"] as! [String: String]
        let graphNodes = atlas["nodes"] as! [[String: Any]]
        let edges = atlas["edges"] as! [[String: Any]]
        let paths = nodes.values.compactMap { $0["path"] as? String }
        check(nodes["home"]?["name"] as? String == "Selected folder", "project registration overrides catalog while retaining knowledge metadata")
        check(result["static_mode"] as? Bool == true && (result["domains"] as? [String])?.isEmpty == true, "static selected-directory scope has no preconfigured domains")
        check(paths.contains(root.appendingPathComponent("docs/图 文.markdown").path), "Unicode and markdown extension preserved")
        check(!paths.contains(where: { $0.contains("linked") || $0.contains("pipe.md") || $0.contains(".hidden") || $0.contains("node_modules") || $0.contains("/excluded/") || $0.contains("/quiet") || $0.contains("temp-old") || $0.contains("cache-area") || $0.contains("摘录区") }), "symlinks FIFO hidden and configured restrictions excluded")
        check(paths.contains(root.appendingPathComponent("text-only/visible.md").path), "full-text-only exclusion does not remove graph metadata")
        check((result["home_overview"] as? [String]) == ["topic:guide", aliases["doc:overview"]!], "curated overview resolves topic aliases and real file identities")
        check(graphNodes.contains(where: { $0["id"] as? String == "topic:guide" && ($0["desc"] as? String)?.contains("First line\nSecond line") == true }), "block scalar topic description and catalog node retained")
        check(edges.contains(where: { $0["label"] as? String == "Explains" && $0["both"] as? Bool == true }), "curated sourced bidirectional edge retained")
        check((result["semantic_edges"] as! [[String: Any]]).contains(where: { $0["kind"] as? String == "reference" }), "Markdown references resolve without network access")
        check((result["semantic_edges"] as! [[String: Any]]).contains(where: { $0["kind"] as? String == "explains" }), "frontmatter relation resolves relative to source")
        check((result["tags"] as! [[String: Any]]).contains(where: { $0["name"] as? String == "alpha" && ($0["members"] as? [String])?.count == 2 }), "frontmatter and curated tags share one explicit tag node")
        check(graphNodes.contains(where: { $0["kind"] as? String == "导航表记录" && $0["name"] as? String == "Detail item" && $0["source_line"] as? Int != nil }), "opted-in table rows preserve source line and original-record status")
        check(edges.contains(where: { $0["basis"] as? String == "原表路径引用（非提交或有效性判断）" }), "navigation row file reference retained")
        let command = try String(contentsOf: root.appendingPathComponent("知识图谱.command"), encoding: .utf8)
        check(command.contains("folio graph \"$PWD\" --launcher") && !command.contains("python"), "launcher invokes installed Folio CLI")
        check((try fm.attributesOfItem(atPath: root.appendingPathComponent("知识图谱.command").path)[.posixPermissions] as? Int) == 0o700, "launcher private executable permissions")
        let report = try FolioGraphEngine.generateReport(root: root, launcher: true, config: config)
        let counts = (result["status"] as! [String: Any])["counts"] as! [String: Int]
        check(report.path == output.path && report.launcher != nil && report.directories == counts["directory"] && report.files == counts["file"]
              && report.nodes == nodes.count && report.edges == edges.count, "generation report carries the page's own counts")
        let refreshed = try payload(FolioGraphEngine.generate(root: root, launcher: true, config: config))
        check((refreshed["nodes"] as! [String: Any]).count == nodes.count, "idempotent refresh excludes generated HTML and launcher")
        let original = try Data(contentsOf: output)
        rejects("cancellation preserves existing output") { _ = try FolioGraphEngine.generate(root: root, config: config, cancelled: { true }) }
        check(try Data(contentsOf: output) == original, "cancelled generation does not modify graph")
        try write("other.html", "owner content")
        rejects("foreign output rejected") { _ = try FolioGraphEngine.generate(root: root, output: root.appendingPathComponent("other.html"), config: config) }
        try write("知识图谱.command", "owner launcher")
        rejects("foreign launcher rejected before modifying HTML") { _ = try FolioGraphEngine.generate(root: root, launcher: true, config: config) }
        check(try Data(contentsOf: output) == original, "launcher conflict preserves graph")
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("out.html").path, withDestinationPath: output.path)
        rejects("output symlink rejected") { _ = try FolioGraphEngine.generate(root: root, output: root.appendingPathComponent("out.html"), config: config) }
        rejects("selected symlink root rejected") { _ = try FolioGraphEngine.generate(root: root.appendingPathComponent("linked-dir"), config: config) }
        let escaped = root.appendingPathComponent("escaped.html")
        try write("docs/unsafe.md", "---\nname: '</script><script>bad()</script>'\n---\n# text")
        _ = try FolioGraphEngine.generate(root: root, output: escaped, config: config)
        let html = try String(contentsOf: escaped, encoding: .utf8)
        check(!html.contains("</script><script>bad()"), "payload escapes script-closing markup")
        check(html.contains("connect-src 'none'"), "offline renderer disallows outgoing connections")
        let yaml = try FolioGraphYAML.parse("items:\n- id: topic:one\n  tags: ['a,b', second]\nvalue: {path: detail.md, note: 'ok # quoted'}")
        check((yaml["items"] as? [[String: Any]])?.count == 1 && (yaml["value"] as? [String: String])?["note"] == "ok # quoted", "limited YAML handles indentless sequences quoted commas and flow maps")
        rejects("YAML aliases fail closed") { _ = try FolioGraphYAML.parse("value: *unsafe") }
        print("Graph engine checks passed (\(checks))")
    }
}
