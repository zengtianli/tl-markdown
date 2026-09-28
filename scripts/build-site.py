#!/usr/bin/env python3
"""Build Folio's allowlisted product site from an actual binary release and real media."""
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENES = (
    ("open", "打开，就是好读的一页", "打开 Markdown，阅读表格与图表，再用标题大纲定位段落。"),
    ("edit", "找到文字，一次替换", "查找“进行中”，全部替换为“已经完成”；切回排版查看结果。"),
    ("save", "保存后，下次接着写", "确认底栏已保存，重新打开同一文件，刚才的修改仍在。"),
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probe(path):
    return json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True))


def check_media(media, release):
    required = ["folio-editor.png", "capture.json"] + [f"{name}.{suffix}" for name, _, _ in SCENES for suffix in ("mp4", "jpg", "vtt")]
    missing = [name for name in required if not (media / name).is_file()]
    if missing:
        raise ValueError("Missing real media: " + ", ".join(missing))
    capture = json.loads((media / "capture.json").read_text())
    assert capture["source"] == "real-app-window" and capture["synthetic_input"] is True, "Media must use an actual app window and synthetic input"
    if str(capture["app_version"]) == release["version"] and str(capture["app_build"]) == release["build"]:
        assert capture.get("release_source_sha256") == release["source_sha256"] and capture.get("release_sha256") == release["sha256"], "Recording must bind the actual released build and archive"
    else:
        # A later release may reuse the recording only when the manifest names that exact release
        # (source fingerprint and archive hash), states why the recorded scenes still hold, and cites
        # the UI tests that passed on it. The page then labels the recording version, not the release.
        reuse = (capture.get("reused_for") or {}).get(f"{release['version']} ({release['build']})") or {}
        assert reuse.get("release_source_sha256") == release["source_sha256"] and reuse.get("release_sha256") == release["sha256"], "Recording and release versions differ"
        assert reuse.get("reason") and reuse.get("tests"), "Reused recording needs a reason and the UI tests run on this release"
    assert set(capture["scenes"]) == {name for name, _, _ in SCENES}, "Recording scene coverage is incomplete"
    assert capture.get("environment") and capture.get("recorded_at"), "Recording environment and date are required"
    raw = (media / "folio-editor.png").read_bytes()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">I", raw[16:20])[0] >= 1000, "Use a full-resolution actual screenshot (PNG, width >= 1000)"
    for name, _, _ in SCENES:
        video = probe(media / f"{name}.mp4")
        streams = [s for s in video["streams"] if s["codec_type"] == "video"]
        assert streams and streams[0]["codec_name"] == "h264" and streams[0].get("pix_fmt") == "yuv420p", f"{name}: use browser-compatible H.264 / yuv420p"
        assert capture["checks"][name]["sha256"] == sha(media / f"{name}.mp4"), f"{name}: video differs from the reviewed media manifest"
        assert float(video["format"]["duration"]) > 1, f"{name}: invalid duration"
        assert probe(media / f"{name}.jpg")["streams"][0]["codec_type"] == "video", f"{name}: unreadable poster"
        subtitles = (media / f"{name}.vtt").read_text(encoding="utf-8-sig")
        assert subtitles.startswith("WEBVTT") and "-->" in subtitles, f"{name}: no real timed subtitles"
    if (media / "tutorial.mp4").is_file():
        assert sha(media / "tutorial.mp4") == capture["checks"]["tutorial"]["sha256"], "Tutorial differs from reviewed media"
        assert (media / "tutorial.vtt").read_text().startswith("WEBVTT"), "Tutorial requires its timed subtitles"
        required += ["tutorial.mp4", "tutorial.vtt"]
    return required, capture


def lightweight(release, preview):
    """Page numbers come only from perf/lightweight.json, measured on this exact release."""
    path = ROOT / "perf/lightweight.json"
    data = json.loads(path.read_text())
    expected = f"{release['version']} ({release['build']})"
    if data.get("version") != expected or data["size"].get("download_bytes") != release["bytes"]:
        if not preview:
            raise SystemExit(f"Site not built: perf/lightweight.json measures {data.get('version')}, release is {expected}; re-measure first")
    idle, launch = data["idle"], next(item for item in data["speed_gui"] if item["key"] == "launch")
    installed = data["size"]["installed_bytes"] / 1e6  # decimal MB, same as Finder and the download button
    # measure.py's legacy *_mb fields are MiB; public MB uses decimal bytes.
    memory = (idle["footprint_bytes"] / 1e6 if idle.get("footprint_bytes") is not None
              else idle["footprint_mb"] * 2**20 / 1e6)
    main_memory = (idle["main_footprint_bytes"] / 1e6 if idle.get("main_footprint_bytes") is not None
                   else idle["main_footprint_mb"] * 2**20 / 1e6)
    runs = len(idle.get("runs") or [])
    idle_summary = f"{runs} 轮空闲测量取中位" if runs > 1 else "本次空闲测量 1 轮"
    note = (f"实测 Folio {release['version']}（构建 {release['build']}，即本页下载包）· {data['device']} · {data['measured_at']} · "
            f"打开 137 KB 合成 Markdown（标题、表格、代码、公式）。内存为 phys_footprint（活动监视器「内存」列同口径），"
            f"主进程 {main_memory:.1f} MB 加 WebKit 渲染、GPU、网络 3 个辅助进程合计，页面 MB 均为十进制（字节 ÷ 10⁶）。静置 {idle['settle_s']} 秒后测 {idle['window_s']} 秒；"
            f"CPU 为这段时间各进程 CPU 时间 ÷ 墙钟；{idle_summary}。内存在 CPU 窗口结束后另采 3 次，各次同一时刻合计取峰值；启动为 open -g -j 后台隐藏启动到编辑窗口读入文档，{launch['runs']} 次中位。"
            "应用以隐藏窗口测量，窗口上屏时渲染进程会略高；测量时本机同时运行其他任务。")
    for key, label in (("memory_note", "内存条件"), ("cpu_note", "CPU 条件")):
        if idle.get(key):
            recorded_note = idle[key]
            if key == "memory_note" and "MiB" in idle.get("units", ""):
                recorded_note = re.sub(r"\bMB\b", "MiB", recorded_note)
            note += f" {label}：{recorded_note}"
    return {"LW_INSTALLED": f"{installed:.1f} MB", "LW_MEMORY": f"{memory:.1f} MB",
            "LW_CPU": f"{idle['cpu_pct']:.2f}%", "LW_LAUNCH": f"{launch['median_ms'] / 1000:.2f} 秒",
            "LW_LAUNCH_RUNS": str(launch["runs"]), "LW_NOTE": escape(note)}


def document_page(title, content):
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(title)} · Folio</title><link rel="icon" href="images/icon.png"><link rel="stylesheet" href="style.css"></head><body><header class="topbar wrap"><a class="brand" href="index.html"><img src="images/icon.png" width="42" height="42" alt=""><span>Folio</span></a><a class="text-link" href="index.html">返回产品主页 ↗</a></header><main class="document-page wrap"><p class="eyebrow">Folio</p><h1>{escape(title)}</h1>{content}</main></body></html>'''


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []
    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ("href", "src", "poster") and value:
                self.urls.append(value)


def validate(root):
    for page in root.glob("*.html"):
        text = page.read_text()
        assert not re.search(r"@@[A-Z_]+@@", text), "Unresolved site template token"
        assert not any(word in text for word in ("/Users/", "localhost:", "127.0.0.1:", "SK_OPENAI")), "Private or development data entered a public page"
        links = Links()
        links.feed(text)
        for url in links.urls:
            parsed = urlsplit(url)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            local = (page.parent / unquote(parsed.path)).resolve()
            assert local.is_relative_to(root.resolve()) and local.is_file(), f"Broken local link: {page.name}: {url}"


def validate_file_set(root, manifest):
    expected = {item["path"] for item in manifest["files"]} | {"site-manifest.json"}
    paths = list(root.rglob("*"))
    assert not any(path.is_symlink() for path in paths), "Generated site must not contain symlinks"
    actual = {str(path.relative_to(root)) for path in paths if path.is_file()}
    assert actual == expected, f"Generated files differ from allowlist: extra={sorted(actual - expected)}, missing={sorted(expected - actual)}"


def replace_generated_site(stage, out):
    """Install a complete generation; preserve the previous output for recovery."""
    previous = None
    if out.exists():
        assert out.is_dir(), "Site output must be a directory"
        if any(out.iterdir()):
            marker = out / "site-manifest.json"
            assert marker.is_file() and json.loads(marker.read_text()).get("product") == "Folio", "Refusing to replace a non-generated directory"
        previous = Path(tempfile.mkdtemp(prefix=f".{out.name}-previous-", dir=out.parent))
        try:
            out.rename(previous)
        except BaseException:
            previous.rmdir()  # Still the empty directory reserved above.
            raise
    try:
        stage.rename(out)
    except BaseException:
        if previous is not None:
            previous.rename(out)
        raise
    return previous


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, default=ROOT / "build/release/release.json")
    parser.add_argument("--media", type=Path, default=ROOT / "docs/demo/media")
    parser.add_argument("--out", type=Path, default=ROOT / "build/site")
    parser.add_argument("--preview", action="store_true", help="Explicit incomplete internal preview; never publish this output")
    args = parser.parse_args()
    release = json.loads(args.release.read_text())
    archive = args.release.parent / release["filename"]
    assert archive.is_file() and sha(archive) == release["sha256"], "Release ZIP is missing or its hash changed"
    assert release["signature"] == "adhoc" and release["notarized"] is False, "Update installation copy for a different signing status"
    assert release["architectures"] == ["arm64"], "Update device copy before adding other architectures"
    media_files, capture, media_error = [], {}, ""
    try:
        media_files, capture = check_media(args.media, release)
    except (AssertionError, ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        if not args.preview:
            raise SystemExit(f"Site not built: {error}")
        media_error = str(error)
    assert not args.out.is_symlink(), "Site output must not be a symlink"
    out = args.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="folio-site-", dir=out.parent) as temporary:
        stage = Path(temporary) / "site"
        stage.mkdir()
        for directory in ("images", "downloads", "media"):
            (stage / directory).mkdir()
        shutil.copyfile(ROOT / "icon/AppIcon.png", stage / "images/icon.png")
        shutil.copyfile(ROOT / "site/style.css", stage / "style.css")
        shutil.copyfile(archive, stage / "downloads" / release["filename"])
        shutil.copyfile(args.release, stage / "release.json")
        (stage / "downloads/SHA256SUMS.txt").write_text(f"{release['sha256']}  {release['filename']}\n")
        if media_files:
            for name in media_files:
                if name != "capture.json":
                    shutil.copyfile(args.media / name, stage / "media" / name)
            public_capture = {key: capture[key] for key in ("app_version", "app_build", "release_sha256", "release_source_sha256", "recorded_at", "environment", "source", "synthetic_input", "scenes", "clips", "checks", "editing", "not_covered")}
            public_capture["notes"] = capture.get("notes", "")
            (stage / "media/capture.json").write_text(json.dumps(public_capture, ensure_ascii=False, indent=2) + "\n")
            hero = '<img src="media/folio-editor.png" alt="Folio 真实主编辑窗口：本地文档、最近文件、排版好的标题与表格" width="1440" height="1000" fetchpriority="high">'
        else:
            hero = '<div class="pending-media">内部预览：此处等待最终版本的真实窗口截图</div>'
        videos = []
        for index, (name, title, description) in enumerate(SCENES, 1):
            if media_files:
                stream = next(s for s in probe(args.media / f"{name}.mp4")["streams"] if s["codec_type"] == "video")
                size = f'width="{stream["width"]}" height="{stream["height"]}" style="aspect-ratio:{stream["width"]}/{stream["height"]}"'
                player = f'<video {size} controls playsinline preload="metadata" poster="media/{name}.jpg"><source src="media/{name}.mp4" type="video/mp4"><track kind="captions" src="media/{name}.vtt" srclang="zh" label="中文">浏览器不支持视频时，请下载观看。</video>'
            else:
                player = '<div class="pending-media">内部预览：等待真实操作片段</div>'
            download = f'<a class="text-link" href="media/{name}.mp4" download>下载这段视频 ↓</a>' if media_files else ''
            videos.append(f'<article class="demo-card">{player}<div class="demo-copy"><span class="step-label">0{index} /</span><h3>{title}</h3><p>{description}</p>{download}</div></article>')
        reused = (capture.get("reused_for") or {}).get(f"{release['version']} ({release['build']})") if media_files else None
        capture_note = ((f"录制版本 {capture['app_version']}（{capture['app_build']}）；{capture['environment']}。{capture.get('notes', '')}"
                         + (f"{release['version']}（{release['build']}）沿用这段录像：{reused['reason']}" if reused else ""))
                        if media_files else "内部预览尚无实机媒体；不得据此发布或声称演示完成。")
        # The hero screenshot comes from the same recording session; a reused
        # recording is labelled with its own version so the caption never implies
        # the current release was photographed.
        hero_caption = "Folio 主编辑器 · 真实窗口 · 虚构样例文档"
        if reused:
            hero_caption += f" · 截图录于 {capture['app_version']}（构建 {capture['app_build']}）"
            if reused.get("hero_note"):
                hero_caption += f"，{reused['hero_note']}"
        values = {"VERSION": escape(release["version"]), "BUILD": escape(release["build"]),
                  "MIN_MACOS": escape(release["minimum_macos"]), "CHIP": "Apple 芯片 Mac",
                  "SIZE": f"{release['bytes'] / 1e6:.1f} MB", "DOWNLOAD_URL": escape(release["download_url"], quote=True),
                  "HERO": hero, "HERO_CAPTION": escape(hero_caption), "VIDEOS": "\n".join(videos), "CAPTURE_NOTE": escape(capture_note),
                  "TUTORIAL": '<p><a class="text-link" href="media/tutorial.mp4" download>下载三段完整演示 ↓</a></p>' if "tutorial.mp4" in media_files else '',
                  **lightweight(release, args.preview),
                  "PREVIEW_NOTICE": '<div class="preview-notice">内部预览 · 实机素材或最终验收尚未完成 · 不可发布</div>' if args.preview else ''}
        page = (ROOT / "site/index.html").read_text()
        for key, value in values.items():
            page = page.replace(f"@@{key}@@", value)
        (stage / "index.html").write_text(page)
        privacy = '''<p>Folio 是本地 Markdown 编辑器。无需注册账号，也不内置文档上传、广告或分析追踪服务。</p><h2>文件与恢复记录</h2><p>文档保存在你选择的位置。最近文件、设置和恢复草稿位于本机 <code>~/Library/Application Support/TLMarkdown/</code>。清空最近记录不会删除原文件；卸载应用前，请先把需要的未命名草稿另存为。</p><h2>什么时候会连接网络？</h2><p>文档中含有网络图片时，编辑器可能访问该图片的原站点，原站点可能收到 IP 地址等通常的网络请求信息。点击外部链接或产品帮助链接，会由系统浏览器打开相应网站。Folio 不代管这些网站的数据政策。</p><p>将文档存入 iCloud 或其他同步文件夹时，同步由对应的服务负责；Folio 没有另建一份云端文档库。</p><h2>这份产品网站</h2><p>本网站经 Cloudflare 提供服务，并加载 Cloudflare Web Analytics，用于统计网页访问与页面性能。统计发生在网站页面，不读取 Folio 应用中的本地文档。详见 <a href="https://developers.cloudflare.com/web-analytics/about/">Cloudflare Web Analytics 官方说明</a>。</p><p>视频由本站提供，访问服务器可能保留常规访问日志。维护者联系方式见 <a href="https://github.com/zengtianli">GitHub 个人主页</a>。</p>'''
        (stage / "privacy.html").write_text(document_page("隐私说明", privacy))
        change = f'''<p>当前下载：Folio {values['VERSION']}，构建 {values['BUILD']}，{values['CHIP']}，macOS {values['MIN_MACOS']} 及以上。</p><h2>1.2.0：全部笔记，由 Folio 自己索引</h2><ul><li>设置新增「索引文件夹」与「更新索引」：索引由 Folio 在本机维护，只读取笔记、不修改内容；没有配置时不扫描，建立和搜索都不联网。</li><li>侧栏「搜索」改读 Folio 自己的索引，任何用户添加文件夹后即可使用；点命中行打开文档并跳到该行。</li><li>菜单「文件 → 生成目录图谱…」：为一个文件夹生成离线 <code>知识图谱.html</code>，不覆盖非 Folio 生成的同名文件。</li><li>应用包内附带 <code>folio</code> 命令（index / search / files / stats / graph），与界面共用引擎，只依赖系统 SQLite。</li></ul><h2>1.1.0：侧栏搜索</h2><ul><li>侧栏新增「搜索」（⌘⇧F），跨笔记检索并跳到命中行。</li></ul><h2>1.0.1：更轻、更安静</h2><ul><li>外部修改检测改由系统文件事件通知，空闲时不再每 2 秒轮询；网络卷等无法监听的位置才退回轮询。</li><li>公式（KaTeX）与代码着色改为文档里用到时才加载，编辑器主脚本 1.44 MB → 0.74 MB；去掉重复打包的 KaTeX 和不会用到的字体格式。</li><li>输入时只重算块级结构：编辑器组件基准（无头浏览器）中，1.1 MB 文档单次按键中位 59.9 → 50.9 毫秒。</li><li>文件被移走或删除后再出现时重新比对内容，内容回到原样即解除冲突提示，自动保存不再被卡住。</li><li>安装包 4.4 MB → 2.7 MB（解压后 9.3 MB → 6.7 MB）。</li></ul><h2>这个版本可以做什么</h2><ul><li>在主编辑区阅读并编辑 Markdown，直接显示表格、公式与图表。</li><li>支持源码切换、标题大纲、最近文件、搜索替换及图片插入。</li><li>自动保存已命名文件，并在外部修改冲突时保留本地草稿。</li><li>从应用“帮助”菜单进入产品主页与使用指南。</li></ul><h2>分发说明</h2><p>当前提供直接下载的 ZIP，尚未经过 Apple 公证。首次打开方法见<a href="index.html#first-open">安装指南</a>。应用代码没有在本页开放下载。</p><p><a href="downloads/SHA256SUMS.txt">查看此安装包的 SHA-256</a>。</p>'''
        (stage / "changelog.html").write_text(document_page("版本记录", change))
        validate(stage)
        files = [{"path": str(path.relative_to(stage)), "sha256": sha(path), "bytes": path.stat().st_size}
                 for path in sorted(stage.rglob("*")) if path.is_file()]
        manifest = {"schema_version": 1, "product": "Folio", "preview": args.preview,
                    "version": release["version"], "build": release["build"], "files": files}
        (stage / "site-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        # Overlay copies retain obsolete downloads. Replace the entire generated
        # directory only after the new stage passes; keep old output outside it.
        validate_file_set(stage, manifest)
        previous = replace_generated_site(stage, out)
        validate_file_set(out, manifest)
    print(f"Built {'INTERNAL PREVIEW' if args.preview else 'product site'}: {out}")
    print(f"Allowlist: {len(files)} public files; manifest excludes itself to avoid a recursive hash.")
    if previous is not None:
        print(f"Previous generated output preserved: {previous}")
    if media_error:
        print(media_error)


if __name__ == "__main__":
    main()
