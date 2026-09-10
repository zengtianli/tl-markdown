#!/usr/bin/env python3
"""Caption reviewed, real Folio clips. Never launch the app or recreate its UI.

Use /opt/homebrew/bin/python3 (Pillow), after reviewing the source frames and
filling a cut plan. All source material stays in the private recording run.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FFMPEG, FFPROBE = "/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/ffprobe"
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"
WIDTH, VIEW, HEADER, FOOTER = 1280, 832, 64, 160
CHAPTERS = {"open": "01 / 打开与阅读", "edit": "02 / 查找与替换", "save": "03 / 自动保存与重开"}


def run(*args):
    subprocess.run(args, check=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probe(path):
    return json.loads(subprocess.check_output([FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True))


def timestamp(seconds):
    ms = round(seconds * 1000)
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02}.{ms % 1000:03}"


def caption(path, height, lines):
    im = Image.new("RGB", (WIDTH, height), "#f7f4ee")
    draw = ImageDraw.Draw(im)
    for text, position, size, color in lines:
        font = ImageFont.truetype(FONT, size)
        assert draw.textbbox(position, text, font=font)[2] <= WIDTH - 26, "Caption exceeds safe width"
        draw.text(position, text, font=font, fill=color)
    im.save(path)


def concat(parts, target, listing):
    listing.write_text("".join("file '" + str(p).replace("'", "'\\''") + "'\n" for p in parts))
    run(FFMPEG, "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
        "-c", "copy", "-map_metadata", "-1", "-movflags", "+faststart", str(target))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True, help="Existing isolated recording run")
    parser.add_argument("--plan", type=Path, required=True, help="Reviewed cuts, hashes and actual observations")
    args = parser.parse_args()
    directory = args.run.resolve()
    plan = json.loads(args.plan.read_text())
    assert plan.get("raw_frames_reviewed") is True, "Review the real source frames before rendering"
    assert plan.get("recorded_at") and plan.get("environment") and plan.get("private_data_review"), "Supply actual recording evidence"
    assert set(plan["scenes"]) == set(CHAPTERS), "All three distinct flows are required"
    release = json.loads((ROOT / "build/release/release.json").read_text())
    stamp = json.loads((directory / "Folio.app/Contents/Resources/FolioBuild.json").read_text())
    for key in ("version", "build", "source_sha256"):
        assert stamp[key] == release[key], f"Recording and release differ: {key}"
    assert sha(ROOT / "build/release" / release["filename"]) == release["sha256"], "Release archive changed"
    out = ROOT / "docs/demo/media"
    overview = out / "folio-editor.png"
    overview_before = sha(overview) if overview.exists() else None
    work = directory / "media-work"
    stage = work / "stage"
    stage.mkdir(parents=True, exist_ok=True)
    entries, chapter_parts, tutorial_cues, offset = {}, [], [], 0.0
    for name, chapter in CHAPTERS.items():
        scene = plan["scenes"][name]
        assert Path(scene["raw_file"]).name == scene["raw_file"], "Raw inputs must be basenames under run/raw"
        raw = directory / "raw" / scene["raw_file"]
        assert sha(raw) == scene["raw_sha256"], f"Unreviewed or changed source: {name}"
        info = probe(raw)
        video = next(s for s in info["streams"] if s["codec_type"] == "video")
        assert not any(s["codec_type"] == "audio" for s in info["streams"]), "Audio requires a separate reviewed edit plan"
        geometry = [video["width"], video["height"]]
        assert geometry == scene["geometry"], "Source geometry differs from reviewed crop plan"
        duration = float(info["format"]["duration"])
        full = scene.get("full_window_xywh") or [0, 0, *geometry]
        assert scene["segments"] and scene["independent_result"], f"Missing reviewed flow/results: {name}"
        retained = sum(part["out"] - part["in"] for part in scene["segments"])
        removed = duration - retained
        parts, cues, cuts, elapsed, previous = [], [], [], 0.0, 0.0
        for index, part in enumerate(scene["segments"]):
            start, end = part["in"], part["out"]
            assert previous <= start < end <= duration, "Cuts must remain chronological and within raw footage"
            previous = end
            crop = part.get("crop_xywh") or full
            x, y, width, height = crop
            assert x >= 0 and y >= 0 and width > 0 and height > 0 and x + width <= geometry[0] and y + height <= geometry[1]
            mode = "真实窗口" if crop == full else "局部放大"
            prefix = work / f"{name}-{index}"
            header, footer = prefix.with_suffix(".header.png"), prefix.with_suffix(".footer.png")
            caption(header, HEADER, [
                (f"Folio  {chapter}", (28, 18), 25, "#8f4a38"),
                (f"{mode} · 原速" + (" · 已剪去等待" if removed > .1 else ""), (795, 23), 19, "#78695f"),
            ])
            caption(footer, FOOTER, [(part["title"], (30, 25), 35, "#523e31"), (part["subtitle"], (30, 94), 23, "#78695f")])
            target = prefix.with_suffix(".mp4")
            filters = (f"[0:v]crop={width}:{height}:{x}:{y}:exact=1,setpts=PTS-STARTPTS,"
                       f"scale={WIDTH}:{VIEW}:force_original_aspect_ratio=decrease:force_divisible_by=2,"
                       f"pad={WIDTH}:{VIEW}:(ow-iw)/2:(oh-ih)/2:white,setsar=1,fps=30[v];"
                       "[1:v][v][2:v]vstack=inputs=3[out]")
            run(FFMPEG, "-y", "-v", "error", "-ss", str(start), "-i", str(raw),
                "-loop", "1", "-framerate", "30", "-i", str(header), "-loop", "1", "-framerate", "30", "-i", str(footer),
                "-filter_complex", filters, "-map", "[out]", "-an", "-t", str(end - start),
                "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-profile:v", "high",
                "-map_metadata", "-1", "-movflags", "+faststart", str(target))
            actual = float(probe(target)["format"]["duration"])
            text = part["title"] + "\n" + part["subtitle"]
            cues.append(f"{timestamp(elapsed)} --> {timestamp(elapsed + actual)}\n{text}")
            tutorial_cues.append(f"{timestamp(offset + elapsed)} --> {timestamp(offset + elapsed + actual)}\n{chapter}\n{text}")
            cuts.append({"source_start": start, "source_end": end, "output_start": round(elapsed, 3),
                         "output_end": round(elapsed + actual, 3), "crop_xywh": crop, "view": mode, "speed": 1,
                         "title": part["title"], "subtitle": part["subtitle"]})
            elapsed += actual
            parts.append(target)
        target = stage / f"{name}.mp4"
        concat(parts, target, work / f"{name}-concat.txt")
        assert 0 <= scene["poster_seconds"] < elapsed, "Poster must come from the final real clip"
        run(FFMPEG, "-y", "-v", "error", "-ss", str(scene["poster_seconds"]), "-i", str(target),
            "-frames:v", "1", "-q:v", "2", str(stage / f"{name}.jpg"))
        (stage / f"{name}.vtt").write_text("WEBVTT\n\n" + "\n\n".join(cues) + "\n")
        chapter_parts.append(target)
        entries[name] = {"raw_file": scene["raw_file"], "raw_sha256": sha(raw), "raw_duration": duration,
                         "raw_geometry": geometry, "cuts": cuts, "removed_seconds": round(removed, 3),
                         "independent_result": scene["independent_result"], "poster_seconds": scene["poster_seconds"]}
        offset += elapsed
    concat(chapter_parts, stage / "tutorial.mp4", work / "tutorial-concat.txt")
    (stage / "tutorial.vtt").write_text("WEBVTT\n\n" + "\n\n".join(tutorial_cues) + "\n")
    checks = {}
    for name in (*CHAPTERS, "tutorial"):
        target = stage / f"{name}.mp4"
        result = subprocess.run([FFMPEG, "-hide_banner", "-v", "info", "-i", str(target),
                                 "-vf", f"crop={WIDTH}:{VIEW}:0:{HEADER},blackdetect=d=0.2:pic_th=0.98:pix_th=0.10", "-an", "-f", "null", "-"], capture_output=True, text=True)
        assert result.returncode == 0 and "black_start:" not in result.stderr, f"Decode/black-frame check failed: {name}"
        (work / f"{name}-decode.log").write_text(result.stderr)
        info = probe(target)
        v = next(s for s in info["streams"] if s["codec_type"] == "video")
        assert v["codec_name"] == "h264" and v["pix_fmt"] == "yuv420p"
        checks[name] = {"decode": "passed", "black_frames": "none >=0.2s at 98% in product-image area",
                        "duration": float(info["format"]["duration"]), "bytes": target.stat().st_size, "sha256": sha(target)}
    capture = {"product": "Folio", "app_version": release["version"], "app_build": release["build"],
               "release_sha256": release["sha256"], "release_source_sha256": release["source_sha256"],
               "recorded_at": plan["recorded_at"], "environment": plan["environment"], "source": "real-app-window", "synthetic_input": True,
               "scenes": list(CHAPTERS), "clips": entries, "checks": checks, "isolation": plan["isolation"],
               "not_covered": plan["not_covered"], "private_data_review": plan["private_data_review"],
               "editing": {"caption_bands_outside_product_image": True, "local_zoom_labelled": True, "retained_speed": 1,
                           "removed_waits_labelled": True, "tutorial_is_three_separate_chapters": True, "audio": "原片无音轨，成片静音"},
               "notes": "虚构样例文档；三个分章实录。保留画面原速，局部放大与剪去等待均已标注。修改通过查找替换完成。",
               "final_visual_review": "pending-main-thread"}
    serialized = json.dumps(capture, ensure_ascii=False, indent=2) + "\n"
    assert "/Users/" not in serialized, "Do not publish private source paths in media metadata"
    (stage / "capture.json").write_text(serialized)
    out.mkdir(parents=True, exist_ok=True)
    for path in stage.iterdir():
        if path.is_file():
            shutil.copyfile(path, out / path.name)
    assert (sha(overview) if overview.exists() else None) == overview_before, "Keep the main thread's screenshot unchanged"
    print(json.dumps(checks, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
