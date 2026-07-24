#!/usr/bin/env python3
"""
Create unconstrained quality-target AV1 archives from QuickRecorder masters.

This companion to archive_av1.py intentionally does not set -b:v, -maxrate, or
2-pass rate control. SVT-AV1 gets a CRF target and can spend bits only where the
content needs them, which is closer to the "dynamic compression" behavior we
want to test against Bandicam-style lecture captures.
"""

from __future__ import annotations

import argparse
import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path


AUDIO_CHOICES = ("copy", "aac-mono-48k", "aac-mono-64k")
STRICT_VALIDATION_EXIT_CODE = 3


class CliError(RuntimeError):
    """Expected user-facing command error."""


class ValidationError(CliError):
    """Archive was written, but strict validation failed."""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Archive a QuickRecorder master to AV1 with libsvtav1 CRF mode, "
            "without target/max video bitrate constraints."
        )
    )
    parser.add_argument("input", type=Path, help="Input QuickRecorder master video")
    parser.add_argument(
        "--crf",
        type=crf_value,
        default=42,
        help="SVT-AV1 CRF quality, 0-63 where lower is higher quality (default: 42)",
    )
    parser.add_argument(
        "--audio",
        choices=AUDIO_CHOICES,
        default="copy",
        help="Audio handling (default: copy)",
    )
    parser.add_argument(
        "--preset",
        type=svt_preset,
        default=8,
        help="SVT-AV1 preset, 0-13 where larger is faster (default: 8)",
    )
    parser.add_argument(
        "--gop",
        type=positive_int,
        default=270,
        help="Maximum keyframe interval in frames (default: 270)",
    )
    output_group = parser.add_mutually_exclusive_group()
    output_group.add_argument("--output", type=Path, help="Explicit output MP4 path")
    output_group.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for the default output filename",
    )
    parser.add_argument(
        "--metrics-dir",
        type=Path,
        help="Optional directory for ffprobe JSON, packet CSV, window CSVs, and summary JSON",
    )
    parser.add_argument(
        "--timestamp-mode",
        choices=metrics_module().TIMESTAMP_MODE_CHOICES,
        default=metrics_module().DEFAULT_TIMESTAMP_MODE,
        help=(
            "Timestamp strategy (default: legacy-passthrough). "
            "Use vfr-clean for the leading DTS-repair candidate."
        ),
    )
    parser.add_argument(
        "--strict-timestamps",
        action="store_true",
        help=(
            "Fail with exit code 3 unless encode logs, ffprobe warnings, "
            "packet/frame timestamps, duration, resolution, and audio policy pass."
        ),
    )
    parser.add_argument("--force", action="store_true", help="Overwrite output if it exists")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the ffmpeg command without encoding or writing metrics",
    )
    return parser.parse_args(argv)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def crf_value(value: str) -> int:
    parsed = int(value)
    if parsed < 0 or parsed > 63:
        raise argparse.ArgumentTypeError("must be between 0 and 63")
    return parsed


def svt_preset(value: str) -> int:
    parsed = int(value)
    if parsed < 0 or parsed > 13:
        raise argparse.ArgumentTypeError("must be between 0 and 13")
    return parsed


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        helpers = metrics_module()
        ffmpeg = require_tool("ffmpeg")
        ffprobe = require_tool("ffprobe")
        require_ffmpeg_capabilities(ffmpeg)

        input_path = args.input.expanduser().resolve()
        if not input_path.is_file():
            raise CliError(f"input file does not exist: {input_path}")

        output_path = resolve_output_path(input_path, args)
        if output_path.exists() and not args.force and not args.dry_run:
            raise CliError(f"output already exists; use --force: {output_path}")

        metrics_dir = helpers.resolve_metrics_dir(output_path, args.metrics_dir, args.strict_timestamps)
        command = build_command(ffmpeg, input_path, output_path, args)
        if args.dry_run:
            print_dry_run_crf(helpers, ffmpeg, input_path, output_path, args, command)
            if metrics_dir:
                print(f"# metrics would be written under {metrics_dir}")
            return 0

        output_path.parent.mkdir(parents=True, exist_ok=True)
        encode_log = run_encode_crf(helpers, ffmpeg, input_path, output_path, args, metrics_dir)
        if not output_path.is_file():
            raise CliError(f"ffmpeg finished but output was not created: {output_path}")

        if metrics_dir:
            metrics_dir.mkdir(parents=True, exist_ok=True)
            helpers.write_metrics(ffprobe, output_path, metrics_dir, input_path=input_path)

        if args.strict_timestamps:
            assert metrics_dir is not None
            validation = helpers.validate_archive(
                ffmpeg,
                ffprobe,
                input_path,
                output_path,
                metrics_dir,
                args,
                encode_log,
            )
            if validation["status"] != "pass":
                raise ValidationError(
                    "strict timestamp validation failed; see "
                    f"{validation['validation_path']}"
                )

        print(f"Wrote {output_path}")
        return 0
    except ValidationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return STRICT_VALIDATION_EXIT_CODE
    except CliError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise CliError(f"{name} was not found on PATH")
    return path


def require_ffmpeg_capabilities(ffmpeg: str) -> None:
    encoders = subprocess.run(
        [ffmpeg, "-hide_banner", "-encoders"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    if "libsvtav1" not in encoders:
        raise CliError("ffmpeg does not include the libsvtav1 encoder")
    if "\n A" not in encoders or " aac " not in encoders:
        raise CliError("ffmpeg does not include an AAC audio encoder")

    help_text = subprocess.run(
        [ffmpeg, "-hide_banner", "-h", "encoder=libsvtav1"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout
    if "-crf" not in help_text:
        raise CliError("ffmpeg libsvtav1 encoder does not expose -crf")


def resolve_output_path(input_path: Path, args: argparse.Namespace) -> Path:
    if args.output:
        return args.output.expanduser().resolve()

    output_dir = args.output_dir.expanduser().resolve() if args.output_dir else input_path.parent
    helpers = metrics_module()
    timestamp_suffix = (
        "" if args.timestamp_mode == helpers.DEFAULT_TIMESTAMP_MODE else f"-ts-{args.timestamp_mode}"
    )
    filename = (
        f"{input_path.stem}.av1-crf{args.crf}-preset{args.preset}-"
        f"{args.audio}{timestamp_suffix}.mp4"
    )
    return output_dir / filename


def build_command(
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
) -> list[str]:
    helpers = metrics_module()
    return (
        [ffmpeg, "-hide_banner", "-nostdin"]
        + helpers.timestamp_input_options(args.timestamp_mode)
        + ["-i", str(input_path)]
        + ["-map", "0:v:0", "-map", "0:a:0?"]
        + video_options(args)
        + audio_options(args.audio)
        + helpers.remux_options(args)
        + [str(output_path)]
    )


def video_options(args: argparse.Namespace) -> list[str]:
    helpers = metrics_module()
    return [
        "-c:v",
        "libsvtav1",
        "-preset",
        str(args.preset),
        "-crf",
        str(args.crf),
        "-g",
        str(args.gop),
        "-pix_fmt",
        "yuv420p",
    ] + helpers.timestamp_video_options(args.timestamp_mode)


def audio_options(mode: str) -> list[str]:
    if mode == "copy":
        return ["-c:a", "copy"]
    if mode == "aac-mono-48k":
        return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "48k"]
    if mode == "aac-mono-64k":
        return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "64k"]
    raise CliError(f"unsupported audio mode: {mode}")


def with_overwrite_flag(command: list[str], force: bool) -> list[str]:
    copy = command[:]
    copy.insert(3, "-y" if force else "-n")
    return copy


def print_dry_run_crf(
    helpers,
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    command: list[str],
) -> None:
    if args.timestamp_mode == "preclean-vfr":
        clean_path = output_path.parent / f".{output_path.stem}.preclean-source.mp4"
        clean = helpers.preclean_source_command(ffmpeg, input_path, clean_path)
        clean.insert(3, "-y")
        print(shlex_join(clean))
        encoded = build_command(ffmpeg, clean_path, output_path, args)
        print(shlex_join(with_overwrite_flag(encoded, args.force)))
        return
    if args.timestamp_mode == "remux-clean":
        encoded_path = output_path.parent / f".{output_path.stem}.encoded-before-remux.mp4"
        encoded = build_command(ffmpeg, input_path, encoded_path, args)
        print(shlex_join(with_overwrite_flag(encoded, True)))
        remux = helpers.remux_clean_command(ffmpeg, encoded_path, output_path)
        remux.insert(3, "-y" if args.force else "-n")
        print(shlex_join(remux))
        return
    print(shlex_join(with_overwrite_flag(command, args.force)))


def run_encode_crf(
    helpers,
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    metrics_dir: Path | None,
) -> dict:
    logs: list[dict] = []
    if args.timestamp_mode == "preclean-vfr":
        import tempfile

        with tempfile.TemporaryDirectory(prefix="archive-av1-crf-preclean-") as tmp:
            clean_path = Path(tmp) / "preclean-source.mp4"
            clean_command = helpers.preclean_source_command(ffmpeg, input_path, clean_path)
            clean_command.insert(3, "-y")
            logs.append(helpers.run_command(clean_command, metrics_dir, output_path.stem, "preclean"))
            command = build_command(ffmpeg, clean_path, output_path, args)
            logs.append(helpers.run_command(with_overwrite_flag(command, args.force), metrics_dir, output_path.stem, "encode"))
    elif args.timestamp_mode == "remux-clean":
        import tempfile

        with tempfile.TemporaryDirectory(prefix="archive-av1-crf-remux-") as tmp:
            encoded_path = Path(tmp) / "encoded-before-remux.mp4"
            command = build_command(ffmpeg, input_path, encoded_path, args)
            logs.append(helpers.run_command(with_overwrite_flag(command, True), metrics_dir, output_path.stem, "encode"))
            remux_command = helpers.remux_clean_command(ffmpeg, encoded_path, output_path)
            remux_command.insert(3, "-y" if args.force else "-n")
            logs.append(helpers.run_command(remux_command, metrics_dir, output_path.stem, "remux"))
    else:
        command = build_command(ffmpeg, input_path, output_path, args)
        logs.append(helpers.run_command(with_overwrite_flag(command, args.force), metrics_dir, output_path.stem, "encode"))
    return helpers.summarize_command_logs(logs)


def run_command(command: list[str]) -> None:
    print("$ " + shlex_join(command), flush=True)
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as exc:
        raise CliError(f"command failed with exit code {exc.returncode}") from exc


def metrics_module():
    module_path = Path(__file__).with_name("archive_av1.py")
    spec = importlib.util.spec_from_file_location("archive_av1_metrics", module_path)
    if spec is None or spec.loader is None:
        raise CliError(f"failed to load metrics module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    original_dont_write_bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = original_dont_write_bytecode
    return module


def shlex_join(command: list[str]) -> str:
    import shlex

    return shlex.join(command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
