#!/usr/bin/env python3
"""Add the iPhone section to an existing verified Mac site, preserving its release.

The base is produced by scripts/build-site.py. This site-only adapter reuses that
builder's validation, allowlist and atomic replacement; it never rebuilds the App
or relaxes the Mac release/performance checks.
"""
import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import tempfile
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEGIN = "<!-- FOLIO IPHONE BEGIN -->"
END = "<!-- FOLIO IPHONE END -->"
CSS_BEGIN = "/* FOLIO IPHONE BEGIN */"
CSS_END = "/* FOLIO IPHONE END */"
ASSETS = ("iphone-read.png", "iphone-table.png", "iphone-draft.png", "iphone-icon.png",
          "iphone-tour.mp4", "iphone-tour.jpg", "iphone-tour.vtt", "iphone-capture.json")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def block(text, begin, end):
    assert text.count(begin) == text.count(end) == 1, "Missing or duplicate iPhone source block"
    return text.split(begin, 1)[1].split(end, 1)[0]

def without_block(text, begin, end):
    return re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=ROOT / "build/site")
    parser.add_argument("--out", type=Path, default=ROOT / "build/site")
    args = parser.parse_args()
    assert not args.base.is_symlink() and not args.out.is_symlink()
    base, out = args.base.resolve(), args.out.resolve()
    spec = importlib.util.spec_from_file_location("folio_site", ROOT / "scripts/build-site.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    manifest = json.loads((base / "site-manifest.json").read_text())
    assert manifest["product"] == "Folio" and manifest["preview"] is False, "A complete Mac base is required"
    builder.validate_file_set(base, manifest)
    for item in manifest["files"]:
        assert sha(base / item["path"]) == item["sha256"], f'Changed base asset: {item["path"]}'
    builder.validate(base)
    release = json.loads((base / "release.json").read_text())
    assert release["download_url"] == builder.release_tools.github_assets(release)["download_url"]
    # The Mac generator no longer mirrors installers. Verify the unchanged original local archive.
    archives = [path.parent / release["filename"] for path in ROOT.glob("build/release*/release.json")]
    assert any(path.is_file() and path.stat().st_size == release["bytes"] and sha(path) == release["sha256"]
               for path in archives), "Original Mac release ZIP is missing or changed"
    perf = json.loads((ROOT / "ios/01-源程序/perf/lightweight.json").read_text())
    capture = json.loads((ROOT / "site/media/iphone-capture.json").read_text())
    launch = next(p for p in perf["speed_gui"] if p["key"] == "first_screen_ready")
    facts = {"PERF_VERSION": perf["version"], "PERF_DATE": perf["measured_at"],
             "PERF_DEVICE": perf["device"], "SIZE": f'{perf["size"]["download_bytes"] / 1e6:.2f}',
             "INSTALLED": f'{perf["size"]["installed_bytes"] / 1e6:.2f}',
             "MEMORY": str(perf["idle"]["memory_mb"]), "CPU": f'{perf["idle"]["cpu_pct"]:.2f}',
             "LAUNCH": f'{launch["median_ms"] / 1000:.3f}', "RUNS": str(launch["runs"]),
             "SHOT_VERSION": f'{capture["version"]} ({capture["build"]})',
             "SHOT_DATE": capture["recorded_at"].split(" ")[0]}
    section = BEGIN + block((ROOT / "site/iphone.html").read_text(), BEGIN, END) + END + "\n"
    for key, value in facts.items():
        section = section.replace(f"@@IPHONE_{key}@@", escape(value))
    assert not re.search(r"@@[A-Z_]+@@", section)
    original_page = without_block((base / "index.html").read_text(), BEGIN, END)
    original_css = without_block((base / "style.css").read_text(), CSS_BEGIN, CSS_END)
    assert original_page.count("</main>") == 1
    page = original_page.replace("</main>", section + "</main>", 1)
    css = original_css + CSS_BEGIN + block((ROOT / "site/style.css").read_text(), CSS_BEGIN, CSS_END) + CSS_END + "\n"
    assert without_block(page, BEGIN, END) == original_page, "Mac page changed"
    assert without_block(css, CSS_BEGIN, CSS_END) == original_css, "Mac styles changed"
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="folio-iphone-site-", dir=out.parent) as temporary:
        stage = Path(temporary) / "site"
        shutil.copytree(base, stage)
        for name in ASSETS:
            source = ROOT / "site/media" / name
            assert source.is_file() and source.stat().st_size > 0, f"Missing iPhone media: {name}"
            shutil.copyfile(source, stage / "media" / name)
        (stage / "index.html").write_text(page)
        (stage / "style.css").write_text(css)
        (stage / "iphone-facts.json").write_text(json.dumps(perf, ensure_ascii=False, indent=2) + "\n")
        video = builder.probe(stage / "media/iphone-tour.mp4")
        stream = next(s for s in video["streams"] if s["codec_type"] == "video")
        assert stream["codec_name"] == "h264" and stream["pix_fmt"] == "yuv420p"
        assert float(video["format"]["duration"]) > 1
        assert (stage / "media/iphone-tour.vtt").read_text().count("-->") >= 3
        builder.validate(stage)
        manifest["iphone"] = {"recorded_version": facts["SHOT_VERSION"], "measured_version": perf["version"],
                              "method": "windowless Simulator screenshot tour; not continuous recording",
                              "mac_page_sha256": hashlib.sha256(original_page.encode()).hexdigest(),
                              "mac_css_sha256": hashlib.sha256(original_css.encode()).hexdigest()}
        manifest["files"] = [{"path": str(p.relative_to(stage)), "sha256": sha(p), "bytes": p.stat().st_size}
                             for p in sorted(stage.rglob("*")) if p.is_file() and p.name != "site-manifest.json"]
        (stage / "site-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        builder.validate_file_set(stage, manifest)
        previous = builder.replace_generated_site(stage, out)
        builder.validate_file_set(out, manifest)
    print(f"Built product site with iPhone section: {out}")
    print(f"Mac release preserved: {release['version']} ({release['build']}); Mac section and style bytes unchanged")
    print(f'Allowlist: {len(manifest["files"])} public files; iPhone tour {video["format"]["duration"]} seconds')
    if previous:
        print(f"Previous generated output preserved: {previous}")

if __name__ == "__main__":
    main()
