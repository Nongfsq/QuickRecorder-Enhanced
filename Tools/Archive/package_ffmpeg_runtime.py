#!/usr/bin/env python3
"""
Create a self-contained FFmpegRuntime folder for QuickRecorder.

The package layout is:

  FFmpegRuntime/
    bin/ffmpeg
    bin/ffprobe
    lib/*.dylib
    licenses/*
    manifest.json
    SHA256SUMS

This script rewrites non-system dylib references to relative load paths so the
runtime can be copied into the app bundle or Application Support.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SYSTEM_PREFIXES = (
    "/System/Library/",
    "/usr/lib/",
)

LICENSE_GLOBS = (
    "LICENSE*",
    "COPYING*",
    "NOTICE*",
    "AUTHORS*",
    "README*",
)


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode != 0:
        raise RuntimeError(
            "command failed with exit code {}: {}\nstdout:\n{}\nstderr:\n{}".format(
                result.returncode, " ".join(args), result.stdout, result.stderr
            )
        )
    return result


def resolve_tool(path_or_name: str) -> Path:
    if "/" in path_or_name:
        path = Path(path_or_name)
    else:
        found = shutil.which(path_or_name)
        if not found:
            raise RuntimeError(f"unable to find {path_or_name}")
        path = Path(found)
    if not path.exists() or not os.access(path, os.X_OK):
        raise RuntimeError(f"not executable: {path}")
    return path


def otool_deps(path: Path) -> list[str]:
    result = run(["otool", "-L", str(path)])
    deps: list[str] = []
    for line in result.stdout.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        dep = line.split(" (", 1)[0]
        deps.append(dep)
    return deps


def is_external_dependency(dep: str) -> bool:
    return dep.startswith("/") and not dep.startswith(SYSTEM_PREFIXES)


def collect_dependencies(seeds: list[Path]) -> dict[str, Path]:
    by_name: dict[str, Path] = {}
    seen_originals: set[Path] = set()
    queue = list(seeds)

    while queue:
        current = queue.pop(0)
        if current in seen_originals:
            continue
        seen_originals.add(current)

        for dep in otool_deps(current):
            if not is_external_dependency(dep):
                continue
            dep_path = Path(dep)
            if not dep_path.exists():
                raise RuntimeError(f"dependency does not exist: {dep}")
            name = dep_path.name
            real = dep_path.resolve()
            if name in by_name and by_name[name].resolve() != real:
                raise RuntimeError(f"duplicate dylib basename with different paths: {name}")
            if name not in by_name:
                by_name[name] = dep_path
                queue.append(dep_path)

    return by_name


def copy_executable(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    dest.chmod(dest.stat().st_mode | 0o755)


def patch_load_paths(copied: Path, original: Path, *, in_bin: bool) -> None:
    if copied.suffix == ".dylib":
        run(["install_name_tool", "-id", f"@rpath/{copied.name}", str(copied)])

    for dep in otool_deps(original):
        if not is_external_dependency(dep):
            continue
        dep_name = Path(dep).name
        if in_bin:
            new_ref = f"@executable_path/../lib/{dep_name}"
        else:
            new_ref = f"@loader_path/{dep_name}"
        run(["install_name_tool", "-change", dep, new_ref, str(copied)])


def cellar_root(path: Path) -> Path | None:
    real = path.resolve()
    parts = real.parts
    for idx, part in enumerate(parts):
        if part == "Cellar" and idx + 2 < len(parts):
            return Path(*parts[: idx + 3])
    return None


def copy_licenses(package: Path, source_files: list[Path], ffmpeg_license_text: str) -> list[dict[str, str]]:
    licenses_dir = package / "licenses"
    licenses_dir.mkdir(parents=True, exist_ok=True)

    roots: dict[str, Path] = {}
    for source in source_files:
        root = cellar_root(source)
        if root is None:
            continue
        key = f"{root.parent.name}-{root.name}"
        roots[key] = root

    copied: list[dict[str, str]] = []
    summary_lines = [
        "# Third-Party Runtime Licenses",
        "",
        "This FFmpegRuntime package was generated from the local pinned Homebrew",
        "formula versions listed below. Keep these notices with any app bundle or",
        "download artifact that includes the runtime.",
        "",
        "## FFmpeg License Output",
        "",
        "```text",
        ffmpeg_license_text.strip(),
        "```",
        "",
        "## Copied Notice Files",
        "",
    ]

    for key, root in sorted(roots.items()):
        target_dir = licenses_dir / key
        target_dir.mkdir(parents=True, exist_ok=True)
        summary_lines.append(f"### {key}")
        matched: list[Path] = []
        for pattern in LICENSE_GLOBS:
            matched.extend(sorted(root.glob(pattern)))
        if not matched:
            summary_lines.append("")
            summary_lines.append("No top-level notice files found.")
            summary_lines.append("")
            continue
        for src in matched:
            if not src.is_file():
                continue
            dest = target_dir / src.name
            shutil.copy2(src, dest)
            rel = dest.relative_to(package)
            copied.append({"component": key, "path": str(rel)})
            summary_lines.append(f"- `{rel}`")
        summary_lines.append("")

    (licenses_dir / "THIRD_PARTY_LICENSES.md").write_text(
        "\n".join(summary_lines) + "\n", encoding="utf-8"
    )
    copied.append({"component": "summary", "path": "licenses/THIRD_PARTY_LICENSES.md"})
    return copied


def write_runtime_readme(package: Path, package_version: str) -> None:
    readme = f"""# QuickRecorder FFmpegRuntime

This folder is the app-bundled FFmpeg runtime used by the AV1 archive feature.

Generate or refresh it from the repository root:

```bash
python3 Tools/Archive/package_ffmpeg_runtime.py \\
  --ffmpeg /opt/homebrew/bin/ffmpeg \\
  --ffprobe /opt/homebrew/bin/ffprobe \\
  --output QuickRecorder/Resources/FFmpegRuntime \\
  --force
```

Expected layout:

```text
bin/ffmpeg
bin/ffprobe
lib/*.dylib
licenses/*
manifest.json
SHA256SUMS
```

The generated runtime rewrites non-system dylib load paths to relative paths,
ad-hoc signs copied binaries, records provenance in `manifest.json`, and
validates checksums, `libsvtav1`, AAC, and CRF mode.

Current package version: `{package_version}`.

The current local package is generated from FFmpeg 8.1.1 on Apple Silicon. It
is arm64 and GPL-enabled. Public distribution must keep the included notices
and satisfy the applicable license/source-offer obligations.
"""
    (package / "README.md").write_text(readme, encoding="utf-8")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def relative_files(package: Path) -> list[Path]:
    files = [p for p in package.rglob("*") if p.is_file()]
    return sorted(p.relative_to(package) for p in files)


def write_checksums(package: Path) -> list[dict[str, str]]:
    checksum_path = package / "SHA256SUMS"
    if checksum_path.exists():
        checksum_path.unlink()

    entries: list[dict[str, str]] = []
    for rel in relative_files(package):
        digest = sha256(package / rel)
        entries.append({"path": str(rel), "sha256": digest})

    checksum_path.write_text(
        "".join(f"{entry['sha256']}  {entry['path']}\n" for entry in entries),
        encoding="utf-8",
    )
    return entries


def fail_if_absolute_homebrew_refs(package: Path) -> None:
    offenders: list[str] = []
    for binary in list((package / "bin").glob("*")) + list((package / "lib").glob("*.dylib")):
        if not binary.is_file():
            continue
        for dep in otool_deps(binary):
            if dep.startswith("/opt/homebrew") or dep.startswith("/usr/local"):
                offenders.append(f"{binary.relative_to(package)} -> {dep}")
    if offenders:
        raise RuntimeError("absolute Homebrew load paths remain:\n" + "\n".join(offenders))


def ad_hoc_sign_runtime(package: Path) -> None:
    for binary in list((package / "lib").glob("*.dylib")) + list((package / "bin").glob("*")):
        if not binary.is_file():
            continue
        run(["/usr/bin/codesign", "--force", "--sign", "-", str(binary)])


def validate_runtime(package: Path) -> None:
    ffmpeg = package / "bin" / "ffmpeg"
    ffprobe = package / "bin" / "ffprobe"
    run([str(ffmpeg), "-hide_banner", "-version"])
    run([str(ffprobe), "-hide_banner", "-version"])
    encoders = run([str(ffmpeg), "-hide_banner", "-encoders"])
    encoder_text = encoders.stdout + encoders.stderr
    if "libsvtav1" not in encoder_text:
        raise RuntimeError("packaged ffmpeg does not expose libsvtav1")
    if " aac " not in encoder_text and "aac_at" not in encoder_text:
        raise RuntimeError("packaged ffmpeg does not expose AAC")
    svt_help = run([str(ffmpeg), "-hide_banner", "-h", "encoder=libsvtav1"])
    if "-crf" not in (svt_help.stdout + svt_help.stderr):
        raise RuntimeError("packaged libsvtav1 does not expose CRF mode")
    fail_if_absolute_homebrew_refs(package)


def build_runtime(args: argparse.Namespace) -> None:
    ffmpeg = resolve_tool(args.ffmpeg)
    ffprobe = resolve_tool(args.ffprobe)
    dest = Path(args.output).resolve()
    if dest.exists() and not args.force:
        raise RuntimeError(f"output exists; use --force: {dest}")

    deps = collect_dependencies([ffmpeg, ffprobe])
    ffmpeg_version = run([str(ffmpeg), "-hide_banner", "-version"]).stdout
    ffmpeg_license = run([str(ffmpeg), "-L"]).stdout

    with tempfile.TemporaryDirectory(prefix="quickrecorder-ffmpeg-runtime-") as tmp:
        package = Path(tmp) / "FFmpegRuntime"
        (package / "bin").mkdir(parents=True)
        (package / "lib").mkdir(parents=True)

        copy_executable(ffmpeg, package / "bin" / "ffmpeg")
        copy_executable(ffprobe, package / "bin" / "ffprobe")
        for name, src in sorted(deps.items()):
            copy_executable(src, package / "lib" / name)

        patch_load_paths(package / "bin" / "ffmpeg", ffmpeg, in_bin=True)
        patch_load_paths(package / "bin" / "ffprobe", ffprobe, in_bin=True)
        for name, src in sorted(deps.items()):
            patch_load_paths(package / "lib" / name, src, in_bin=False)
        ad_hoc_sign_runtime(package)

        sources = [ffmpeg, ffprobe] + list(deps.values())
        license_files = copy_licenses(package, sources, ffmpeg_license)
        write_runtime_readme(package, args.package_version)

        manifest = {
            "schemaVersion": 1,
            "type": "pinned-ffmpeg-runtime",
            "packageVersion": args.package_version,
            "generatedAt": args.generated_at,
            "platform": platform.platform(),
            "machine": platform.machine(),
            "source": {
                "ffmpeg": str(ffmpeg),
                "ffprobe": str(ffprobe),
            },
            "ffmpegVersion": ffmpeg_version.splitlines()[0] if ffmpeg_version else "",
            "license": {
                "effective": "GPL",
                "note": "Generated FFmpeg reports GPL due enabled GPL components; keep source/offers and notices with distributed artifacts.",
                "files": license_files,
            },
            "binaries": {
                "ffmpeg": "bin/ffmpeg",
                "ffprobe": "bin/ffprobe",
            },
            "dylibs": [f"lib/{name}" for name in sorted(deps)],
        }
        (package / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        (package / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        write_checksums(package)

        validate_runtime(package)

        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(package, dest, symlinks=False)

    print(f"wrote {dest}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Package a pinned FFmpegRuntime for QuickRecorder.")
    parser.add_argument("--ffmpeg", default="ffmpeg", help="Path to ffmpeg, default: PATH lookup")
    parser.add_argument("--ffprobe", default="ffprobe", help="Path to ffprobe, default: PATH lookup")
    parser.add_argument(
        "--output",
        default="QuickRecorder/Resources/FFmpegRuntime",
        help="Destination FFmpegRuntime directory",
    )
    parser.add_argument("--package-version", default="ffmpeg-8.1.1-homebrew-arm64-2026-06-17")
    parser.add_argument("--generated-at", default="2026-06-17T00:00:00Z")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    try:
        build_runtime(args)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
