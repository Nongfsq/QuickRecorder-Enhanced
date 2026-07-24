#!/usr/bin/env python3
"""
Create reproducible AV1 archive files from QuickRecorder HEVC masters.

The script intentionally keeps capture decisions out of QuickRecorder: it calls
local ffmpeg/ffprobe, preserves source resolution and timestamps, and can write
packet/window metrics for Bandicam-style comparison.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import statistics
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable


BITRATE_CHOICES = ("240k", "350k", "500k")
AUDIO_CHOICES = ("copy", "aac-mono-48k", "aac-mono-64k")
TIMESTAMP_MODE_CHOICES = (
    "legacy-passthrough",
    "vfr-clean",
    "passthrough-timescale",
    "preclean-vfr",
    "remux-clean",
    "cfr-15",
)
DEFAULT_TIMESTAMP_MODE = "legacy-passthrough"
TINY_PACKET_BYTES = 80
STRICT_VALIDATION_EXIT_CODE = 3
TIMESTAMP_WARNING_PATTERNS = (
    "Non-monotonic DTS",
    "non monotonically increasing dts",
    "invalid DTS",
    "timestamps are unset",
    "Queue input is backward in time",
    "Packets poorly interleaved",
    "failed to avoid negative timestamp",
)


class CliError(RuntimeError):
    """Expected user-facing command error."""


class ValidationError(CliError):
    """Archive was written, but strict validation failed."""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Archive a clear QuickRecorder master to AV1 with libsvtav1 while "
            "preserving resolution and variable frame timing."
        )
    )
    parser.add_argument("input", type=Path, help="Input QuickRecorder master video")
    parser.add_argument(
        "--bitrate",
        choices=BITRATE_CHOICES,
        default="350k",
        help="Target AV1 video bitrate (default: 350k)",
    )
    parser.add_argument(
        "--passes",
        type=int,
        choices=(1, 2),
        default=2,
        help="Use 1-pass or 2-pass encoding (default: 2)",
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
        choices=TIMESTAMP_MODE_CHOICES,
        default=DEFAULT_TIMESTAMP_MODE,
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
        help="Print ffmpeg commands without encoding or writing metrics",
    )
    return parser.parse_args(argv)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def svt_preset(value: str) -> int:
    parsed = int(value)
    if parsed < 0 or parsed > 13:
        raise argparse.ArgumentTypeError("must be between 0 and 13")
    return parsed


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        ffmpeg = require_tool("ffmpeg")
        ffprobe = require_tool("ffprobe")
        require_ffmpeg_capabilities(ffmpeg)

        input_path = args.input.expanduser().resolve()
        if not input_path.is_file():
            raise CliError(f"input file does not exist: {input_path}")

        output_path = resolve_output_path(input_path, args)
        if output_path.exists() and not args.force and not args.dry_run:
            raise CliError(f"output already exists; use --force: {output_path}")

        metrics_dir = resolve_metrics_dir(output_path, args.metrics_dir, args.strict_timestamps)
        commands = build_commands(ffmpeg, input_path, output_path, args, dry_run=args.dry_run)
        if args.dry_run:
            print_dry_run(ffmpeg, input_path, output_path, args, commands, metrics_dir, args.force)
            return 0

        output_path.parent.mkdir(parents=True, exist_ok=True)
        encode_log = run_encode(ffmpeg, input_path, commands, output_path, args.force, args, metrics_dir)

        if metrics_dir:
            metrics_dir.mkdir(parents=True, exist_ok=True)
            write_metrics(ffprobe, output_path, metrics_dir, input_path=input_path)

        if args.strict_timestamps:
            assert metrics_dir is not None
            validation = validate_archive(
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


def resolve_output_path(input_path: Path, args: argparse.Namespace) -> Path:
    if args.output:
        return args.output.expanduser().resolve()

    output_dir = args.output_dir.expanduser().resolve() if args.output_dir else input_path.parent
    timestamp_suffix = (
        "" if args.timestamp_mode == DEFAULT_TIMESTAMP_MODE else f"-ts-{args.timestamp_mode}"
    )
    filename = (
        f"{input_path.stem}.av1-{args.bitrate}-{args.passes}pass-"
        f"{args.audio}{timestamp_suffix}.mp4"
    )
    return output_dir / filename


def resolve_metrics_dir(
    output_path: Path,
    metrics_dir: Path | None,
    strict_timestamps: bool,
) -> Path | None:
    if metrics_dir:
        return metrics_dir.expanduser().resolve()
    if strict_timestamps:
        return output_path.with_suffix("").with_name(f"{output_path.stem}.metrics")
    return None


def build_commands(
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    dry_run: bool = False,
) -> list[list[str]]:
    passlog = str((output_path.parent / f".{output_path.stem}.passlog").resolve()) if dry_run else None
    if args.passes == 2:
        return build_two_pass_commands(
            ffmpeg,
            input_path,
            output_path,
            args,
            passlog_placeholder=passlog,
        )
    return [build_one_pass_command(ffmpeg, input_path, output_path, args)]


def timestamp_input_options(timestamp_mode: str) -> list[str]:
    if timestamp_mode in ("vfr-clean", "preclean-vfr"):
        return ["-fflags", "+genpts"]
    return []


def input_options(args: argparse.Namespace) -> list[str]:
    return timestamp_input_options(args.timestamp_mode)


def video_options(args: argparse.Namespace) -> list[str]:
    options = [
        "-c:v",
        "libsvtav1",
        "-preset",
        str(args.preset),
        "-b:v",
        args.bitrate,
        "-g",
        str(args.gop),
        "-pix_fmt",
        "yuv420p",
    ]
    return options + timestamp_video_options(args.timestamp_mode)


def timestamp_video_options(timestamp_mode: str) -> list[str]:
    if timestamp_mode == "cfr-15":
        return ["-fps_mode", "cfr", "-r", "15"]
    if timestamp_mode == "legacy-passthrough":
        return ["-fps_mode", "passthrough"]
    if timestamp_mode == "passthrough-timescale":
        return [
            "-fps_mode",
            "passthrough",
            "-enc_time_base:v",
            "demux",
            "-video_track_timescale",
            "60000",
            "-avoid_negative_ts",
            "make_zero",
        ]
    if timestamp_mode in ("vfr-clean", "preclean-vfr", "remux-clean"):
        return [
            "-fps_mode",
            "vfr",
            "-enc_time_base:v",
            "demux",
            "-video_track_timescale",
            "60000",
            "-avoid_negative_ts",
            "make_zero",
        ]
    raise CliError(f"unsupported timestamp mode: {timestamp_mode}")


def remux_options(args: argparse.Namespace) -> list[str]:
    options: list[str] = []
    if args.timestamp_mode in (
        "vfr-clean",
        "passthrough-timescale",
        "preclean-vfr",
        "remux-clean",
        "cfr-15",
    ):
        options += ["-max_interleave_delta", "0"]
    return options + ["-movflags", "+faststart"]


def preclean_source_command(ffmpeg: str, input_path: Path, clean_path: Path) -> list[str]:
    return [
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-i",
        str(input_path),
        "-map",
        "0",
        "-c",
        "copy",
        "-avoid_negative_ts",
        "make_zero",
        "-max_interleave_delta",
        "0",
        "-movflags",
        "+faststart",
        str(clean_path),
    ]


def remux_clean_command(ffmpeg: str, encoded_path: Path, output_path: Path) -> list[str]:
    return [
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-i",
        str(encoded_path),
        "-map",
        "0",
        "-c",
        "copy",
        "-avoid_negative_ts",
        "make_zero",
        "-max_interleave_delta",
        "0",
        "-movflags",
        "+faststart",
        str(output_path),
    ]


def audio_options(mode: str) -> list[str]:
    if mode == "copy":
        return ["-c:a", "copy"]
    if mode == "aac-mono-48k":
        return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "48k"]
    if mode == "aac-mono-64k":
        return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "64k"]
    raise CliError(f"unsupported audio mode: {mode}")


def base_input(ffmpeg: str, input_path: Path, args: argparse.Namespace) -> list[str]:
    return [ffmpeg, "-hide_banner", "-nostdin"] + input_options(args) + ["-i", str(input_path)]


def build_one_pass_command(
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
) -> list[str]:
    return (
        base_input(ffmpeg, input_path, args)
        + ["-map", "0:v:0", "-map", "0:a:0?"]
        + video_options(args)
        + audio_options(args.audio)
        + remux_options(args)
        + [str(output_path)]
    )


def build_two_pass_commands(
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    passlog_placeholder: str | None = None,
) -> list[list[str]]:
    passlog = passlog_placeholder or "svtav1-pass"
    first = (
        base_input(ffmpeg, input_path, args)
        + ["-map", "0:v:0"]
        + video_options(args)
        + ["-pass", "1", "-passlogfile", passlog, "-an", "-f", "null", "/dev/null"]
    )
    second = (
        base_input(ffmpeg, input_path, args)
        + ["-map", "0:v:0", "-map", "0:a:0?"]
        + video_options(args)
        + ["-pass", "2", "-passlogfile", passlog]
        + audio_options(args.audio)
        + remux_options(args)
        + [str(output_path)]
    )
    return [first, second]


def run_encode(
    ffmpeg: str,
    input_path: Path,
    commands: list[list[str]],
    output_path: Path,
    force: bool,
    args: argparse.Namespace,
    metrics_dir: Path | None,
) -> dict:
    logs: list[dict] = []
    if args.timestamp_mode == "preclean-vfr":
        with tempfile.TemporaryDirectory(prefix="archive-av1-preclean-") as tmp:
            clean_path = Path(tmp) / "preclean-source.mp4"
            clean_command = preclean_source_command(ffmpeg, input_path, clean_path)
            clean_command.insert(3, "-y")
            logs.append(run_command(clean_command, metrics_dir, output_path.stem, "preclean"))
            commands = build_commands(ffmpeg, clean_path, output_path, args)
            logs.extend(run_encode_commands(commands, output_path, force, metrics_dir))
    elif args.timestamp_mode == "remux-clean":
        with tempfile.TemporaryDirectory(prefix="archive-av1-remux-") as tmp:
            encoded_path = Path(tmp) / "encoded-before-remux.mp4"
            encode_commands = build_commands(ffmpeg, input_path, encoded_path, args)
            logs.extend(run_encode_commands(encode_commands, encoded_path, True, metrics_dir))
            remux_command = remux_clean_command(ffmpeg, encoded_path, output_path)
            remux_command.insert(3, "-y" if force else "-n")
            logs.append(run_command(remux_command, metrics_dir, output_path.stem, "remux"))
    else:
        logs.extend(run_encode_commands(commands, output_path, force, metrics_dir))

    if not output_path.is_file():
        raise CliError(f"ffmpeg finished but output was not created: {output_path}")
    return summarize_command_logs(logs)


def run_encode_commands(
    commands: list[list[str]],
    output_path: Path,
    force: bool,
    metrics_dir: Path | None,
) -> list[dict]:
    logs: list[dict] = []
    if len(commands) == 1:
        command = commands[0][:]
        command.insert(3, "-y" if force else "-n")
        logs.append(run_command(command, metrics_dir, output_path.stem, "encode"))
        if not output_path.is_file():
            raise CliError(f"ffmpeg finished but output was not created: {output_path}")
        return logs

    with tempfile.TemporaryDirectory(prefix="archive-av1-pass-") as tmp:
        passlog = str(Path(tmp) / "svtav1-pass")
        first, second = rebuild_passlog_commands(commands, passlog)
        first.insert(3, "-y")
        second.insert(3, "-y" if force else "-n")
        logs.append(run_command(first, metrics_dir, output_path.stem, "encode-pass1"))
        logs.append(run_command(second, metrics_dir, output_path.stem, "encode-pass2"))

    if not output_path.is_file():
        raise CliError(f"ffmpeg finished but output was not created: {output_path}")
    return logs


def rebuild_passlog_commands(commands: list[list[str]], passlog: str) -> tuple[list[str], list[str]]:
    rebuilt: list[list[str]] = []
    for command in commands:
        copy = command[:]
        idx = copy.index("-passlogfile")
        copy[idx + 1] = passlog
        rebuilt.append(copy)
    return rebuilt[0], rebuilt[1]


def run_command(
    command: list[str],
    metrics_dir: Path | None = None,
    stem: str | None = None,
    label: str = "command",
) -> dict:
    print("$ " + shlex_join(command), flush=True)
    stdout_chunks: list[str] = []
    stderr_chunks: list[str] = []
    process = subprocess.Popen(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        stdout, stderr = process.communicate()
    except KeyboardInterrupt:
        process.kill()
        process.wait()
        raise

    if stdout:
        print(stdout, end="")
        stdout_chunks.append(stdout)
    if stderr:
        print(stderr, end="", file=sys.stderr)
        stderr_chunks.append(stderr)

    stdout_text = "".join(stdout_chunks)
    stderr_text = "".join(stderr_chunks)
    log_info = write_command_logs(command, metrics_dir, stem, label, stdout_text, stderr_text, process.returncode)
    if process.returncode != 0:
        raise CliError(f"command failed with exit code {process.returncode}")
    return log_info


def write_command_logs(
    command: list[str],
    metrics_dir: Path | None,
    stem: str | None,
    label: str,
    stdout_text: str,
    stderr_text: str,
    return_code: int,
) -> dict:
    timestamp_warnings = find_timestamp_warnings(stderr_text)
    info = {
        "label": label,
        "command": command,
        "return_code": return_code,
        "stdout_path": "",
        "stderr_path": "",
        "command_path": "",
        "timestamp_warning_count": len(timestamp_warnings),
        "non_monotonic_dts_count": count_pattern(stderr_text, "Non-monotonic DTS"),
        "first_timestamp_warnings": timestamp_warnings[:20],
    }
    if metrics_dir is None or stem is None:
        return info

    metrics_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{stem}.{label}"
    command_path = metrics_dir / f"{prefix}.ffmpeg-command.txt"
    stdout_path = metrics_dir / f"{prefix}.stdout.log"
    stderr_path = metrics_dir / f"{prefix}.stderr.log"
    command_path.write_text(shlex_join(command) + "\n")
    stdout_path.write_text(stdout_text)
    stderr_path.write_text(stderr_text)
    info.update(
        {
            "stdout_path": str(stdout_path),
            "stderr_path": str(stderr_path),
            "command_path": str(command_path),
        }
    )
    return info


def summarize_command_logs(logs: list[dict]) -> dict:
    warnings: list[str] = []
    for log in logs:
        warnings.extend(log.get("first_timestamp_warnings", []))
    return {
        "commands": logs,
        "return_code": 0,
        "timestamp_warning_count": sum(int(log.get("timestamp_warning_count", 0)) for log in logs),
        "non_monotonic_dts_count": sum(int(log.get("non_monotonic_dts_count", 0)) for log in logs),
        "first_timestamp_warnings": warnings[:20],
    }


def find_timestamp_warnings(text: str) -> list[str]:
    warnings = []
    for line in text.splitlines():
        lower_line = line.lower()
        if any(pattern.lower() in lower_line for pattern in TIMESTAMP_WARNING_PATTERNS):
            warnings.append(line)
    return warnings


def count_pattern(text: str, pattern: str) -> int:
    return sum(1 for line in text.splitlines() if pattern.lower() in line.lower())


def print_dry_run(
    ffmpeg: str,
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    commands: list[list[str]],
    metrics_dir: Path | None,
    force: bool,
) -> None:
    dry_commands: list[list[str]] = []
    if args.timestamp_mode == "preclean-vfr":
        clean_path = output_path.parent / f".{output_path.stem}.preclean-source.mp4"
        clean = preclean_source_command(ffmpeg, input_path, clean_path)
        clean.insert(3, "-y")
        dry_commands.append(clean)
        dry_commands.extend(build_commands(ffmpeg, clean_path, output_path, args, dry_run=True))
    elif args.timestamp_mode == "remux-clean":
        encoded_path = output_path.parent / f".{output_path.stem}.encoded-before-remux.mp4"
        dry_commands.extend(build_commands(ffmpeg, input_path, encoded_path, args, dry_run=True))
        remux = remux_clean_command(ffmpeg, encoded_path, output_path)
        remux.insert(3, "-y" if force else "-n")
        dry_commands.append(remux)
    else:
        dry_commands = commands

    for index, command in enumerate(dry_commands):
        copy = command[:]
        if "-y" not in copy[1:5] and "-n" not in copy[1:5]:
            copy.insert(3, "-y" if force or (len(dry_commands) >= 2 and index == 0) else "-n")
        print(shlex_join(copy))
    if metrics_dir:
        print(f"# metrics would be written under {metrics_dir.expanduser()}")


def write_metrics(
    ffprobe: str,
    video_path: Path,
    metrics_dir: Path,
    input_path: Path | None = None,
) -> None:
    stem = video_path.stem
    probe_path = metrics_dir / f"{stem}.probe.json"
    packet_path = metrics_dir / f"{stem}.video-packets.csv"
    one_second_path = metrics_dir / f"{stem}.1s-video-bitrate.csv"
    five_second_path = metrics_dir / f"{stem}.5s-video-bitrate.csv"
    frame_interval_path = metrics_dir / f"{stem}.frame-intervals.csv"
    summary_path = metrics_dir / f"{stem}.summary.json"

    probe = run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(video_path),
        ]
    )
    probe_path.write_text(json.dumps(probe, indent=2, sort_keys=True) + "\n")

    packets = write_packet_csv(ffprobe, video_path, packet_path)
    frames = write_frame_interval_csv(ffprobe, video_path, frame_interval_path)
    duration = probe_duration(probe) or infer_duration(packets)

    write_window_csv(packets, duration, 1.0, one_second_path)
    write_window_csv(packets, duration, 5.0, five_second_path)
    summary = build_summary(probe, packets, frames, duration)
    if input_path:
        source_probe = probe_media(ffprobe, input_path)
        summary["source_alignment"] = build_source_alignment_summary(
            source_probe,
            probe,
            input_path,
            video_path,
        )
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

    print(f"Wrote metrics under {metrics_dir}")


def probe_media(ffprobe: str, video_path: Path) -> dict:
    return run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(video_path),
        ]
    )


def build_source_alignment_summary(
    source_probe: dict,
    output_probe: dict,
    source_path: Path,
    output_path: Path,
) -> dict:
    source_video = first_video_stream(source_probe)
    output_video = first_video_stream(output_probe)
    source_audio = first_audio_stream(source_probe)
    output_audio = first_audio_stream(output_probe)
    source_duration = probe_duration(source_probe) or 0.0
    output_duration = probe_duration(output_probe) or 0.0
    return {
        "source_path": str(source_path),
        "output_path": str(output_path),
        "format_duration_delta_s": round(output_duration - source_duration, 6),
        "video_duration_delta_s": round(
            stream_duration(output_video) - stream_duration(source_video),
            6,
        ),
        "audio_duration_delta_s": round(
            stream_duration(output_audio) - stream_duration(source_audio),
            6,
        ),
        "video_frame_count_delta": frame_count(output_video) - frame_count(source_video),
    }


def run_json(command: list[str]) -> dict:
    result = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(result.stdout)


def write_packet_csv(ffprobe: str, video_path: Path, output_path: Path) -> list[dict[str, float | int | str]]:
    command = [
        ffprobe,
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_packets",
        "-show_entries",
        "packet=pts_time,dts_time,duration_time,size,flags",
        "-of",
        "csv=p=0",
        str(video_path),
    ]
    packets: list[dict[str, float | int | str]] = []
    with output_path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["index", "pts_time", "dts_time", "duration_time", "size", "flags"])
        for index, row in enumerate(read_csv_rows(command)):
            if len(row) < 5:
                continue
            pts = parse_float(row[0])
            dts = parse_float(row[1])
            timestamp = pts if pts is not None else dts
            size = parse_int(row[3])
            if timestamp is None or size is None:
                continue
            packet = {
                "index": len(packets),
                "pts_time": timestamp,
                "dts_time": dts if dts is not None else "",
                "duration_time": parse_float(row[2]) or 0.0,
                "size": size,
                "flags": row[4],
            }
            packets.append(packet)
            writer.writerow(
                [
                    packet["index"],
                    packet["pts_time"],
                    packet["dts_time"],
                    packet["duration_time"],
                    packet["size"],
                    packet["flags"],
                ]
            )
    return packets


def write_frame_interval_csv(ffprobe: str, video_path: Path, output_path: Path) -> list[dict[str, float]]:
    data = run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_frames",
            "-show_entries",
            "frame=best_effort_timestamp_time,pts_time,pkt_duration_time,pkt_size,pict_type",
            "-print_format",
            "json",
            str(video_path),
        ]
    )
    return write_frames_from_probe_json(data, output_path)


def write_frames_from_probe_json(data: dict, output_path: Path) -> list[dict[str, float]]:
    frames: list[dict[str, float]] = []
    previous: float | None = None
    with output_path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["frame_index", "timestamp", "interval_s", "duration_s", "pkt_size", "pict_type"])
        for raw_frame in data.get("frames", []):
            timestamp = parse_float(raw_frame.get("best_effort_timestamp_time"))
            if timestamp is None:
                timestamp = parse_float(raw_frame.get("pts_time"))
            if timestamp is None:
                continue
            interval = timestamp - previous if previous is not None else 0.0
            previous = timestamp
            frame = {
                "timestamp": timestamp,
                "interval_s": max(0.0, interval),
                "duration_s": parse_float(raw_frame.get("pkt_duration_time")) or 0.0,
                "pkt_size": parse_float(raw_frame.get("pkt_size")) or 0.0,
            }
            frames.append(frame)
            writer.writerow(
                [
                    len(frames) - 1,
                    frame["timestamp"],
                    frame["interval_s"],
                    frame["duration_s"],
                    frame["pkt_size"],
                    raw_frame.get("pict_type", ""),
                ]
            )
    return frames


def validate_archive(
    ffmpeg: str,
    ffprobe: str,
    input_path: Path,
    output_path: Path,
    metrics_dir: Path,
    args: argparse.Namespace,
    encode_log: dict,
) -> dict:
    stem = output_path.stem
    source_probe = probe_media(ffprobe, input_path)
    output_probe = probe_media(ffprobe, output_path) if output_path.is_file() else {}
    source_video = first_video_stream(source_probe)
    output_video = first_video_stream(output_probe)
    source_audio = first_audio_stream(source_probe)
    output_audio = first_audio_stream(output_probe)
    source_frame_stats = timestamp_frame_stats(ffprobe, input_path, "v:0")
    output_frame_stats = timestamp_frame_stats(ffprobe, output_path, "v:0") if output_path.is_file() else empty_timestamp_stats()
    source_video_packet_stats = timestamp_packet_stats(ffprobe, input_path, "v:0")
    output_video_packet_stats = timestamp_packet_stats(ffprobe, output_path, "v:0") if output_path.is_file() else empty_timestamp_stats()
    source_audio_packet_stats = timestamp_packet_stats(ffprobe, input_path, "a:0") if source_audio else empty_timestamp_stats()
    output_audio_packet_stats = timestamp_packet_stats(ffprobe, output_path, "a:0") if output_audio else empty_timestamp_stats()

    source_warning_path = metrics_dir / f"{stem}.source.ffprobe-warning.log"
    output_warning_path = metrics_dir / f"{stem}.output.ffprobe-warning.log"
    source_warnings = run_warning_probe(ffprobe, input_path, source_warning_path)
    output_warnings = run_warning_probe(ffprobe, output_path, output_warning_path)
    decode_log = run_decode_smoke(ffmpeg, output_path, metrics_dir, stem, has_audio=bool(output_audio))

    source_format_duration = probe_duration(source_probe) or 0.0
    output_format_duration = probe_duration(output_probe) or 0.0
    source_video_duration = stream_duration(source_video)
    output_video_duration = stream_duration(output_video)
    source_audio_duration = stream_duration(source_audio)
    output_audio_duration = stream_duration(output_audio)
    source_av_gap = source_audio_duration - source_video_duration if source_audio else 0.0
    output_av_gap = output_audio_duration - output_video_duration if output_audio else 0.0
    source_min_interval = source_frame_stats.get("min_positive_delta_s") or 0.0
    output_micro_interval_count = count_micro_intervals(
        ffprobe,
        output_path,
        "v:0",
        source_min_interval,
    )

    alignment = {
        "video_frame_count_delta": output_frame_stats["count"] - source_frame_stats["count"],
        "video_frame_count_delta_ratio": ratio(
            abs(output_frame_stats["count"] - source_frame_stats["count"]),
            max(1, source_frame_stats["count"]),
        ),
        "video_duration_delta_s": round(output_video_duration - source_video_duration, 6),
        "audio_duration_delta_s": round(output_audio_duration - source_audio_duration, 6),
        "format_duration_delta_s": round(output_format_duration - source_format_duration, 6),
        "av_end_gap_delta_s": round(output_av_gap - source_av_gap, 6),
        "start_time_delta_s": round(
            stream_start_time(output_video) - stream_start_time(source_video),
            6,
        ),
        "introduced_micro_interval_count": output_micro_interval_count,
    }

    issues = build_validation_issues(
        input_path,
        output_path,
        args,
        source_probe,
        output_probe,
        encode_log,
        source_warnings,
        output_warnings,
        decode_log,
        output_video_packet_stats,
        output_audio_packet_stats,
        output_frame_stats,
        alignment,
    )
    replacement_blocked = replacement_blocked_reasons(input_path, output_path, issues)
    status = "pass" if not issues else "fail"
    validation_path = metrics_dir / f"{stem}.timestamp-validation.json"
    replacement_path = metrics_dir / f"{stem}.replacement-plan.json"
    validation = {
        "schema_version": 1,
        "strict_timestamps": True,
        "status": status,
        "replacement_eligible": status == "pass" and not replacement_blocked,
        "source_path": str(input_path),
        "output_path": str(output_path),
        "archive_settings": archive_settings(args),
        "encode_log": encode_log,
        "probe_contract": {
            "source_format_duration_s": source_format_duration,
            "output_format_duration_s": output_format_duration,
            "video_codec": output_video.get("codec_name"),
            "resolution_matches_source": resolution_matches(source_video, output_video),
            "pixel_format": output_video.get("pix_fmt"),
            "audio_policy_pass": audio_policy_pass(args.audio, source_audio, output_audio),
            "source_ffprobe_warning_count": len(source_warnings),
            "ffprobe_warning_count": len(output_warnings),
            "decode_smoke_pass": decode_log.get("return_code") == 0,
        },
        "timestamp_checks": {
            "source_video_packets": source_video_packet_stats,
            "video_packets": output_video_packet_stats,
            "audio_packets": output_audio_packet_stats,
            "source_video_frames": source_frame_stats,
            "video_frames": output_frame_stats,
            "source_audio_packets": source_audio_packet_stats,
        },
        "source_alignment": alignment,
        "replacement_gate": {
            "pass": status == "pass" and not replacement_blocked,
            "blocked_reasons": replacement_blocked,
        },
        "issues": issues,
    }
    validation["validation_path"] = str(validation_path)
    validation_path.write_text(json.dumps(validation, indent=2, sort_keys=True) + "\n")
    replacement_path.write_text(
        json.dumps(validation["replacement_gate"], indent=2, sort_keys=True) + "\n"
    )
    return validation


def archive_settings(args: argparse.Namespace) -> dict:
    settings = {
        "script": Path(sys.argv[0]).name,
        "preset": getattr(args, "preset", None),
        "gop": getattr(args, "gop", None),
        "audio_mode": getattr(args, "audio", None),
        "timestamp_mode": getattr(args, "timestamp_mode", None),
    }
    if hasattr(args, "bitrate"):
        settings["bitrate"] = args.bitrate
        settings["passes"] = args.passes
    if hasattr(args, "crf"):
        settings["crf"] = args.crf
    return settings


def run_warning_probe(ffprobe: str, video_path: Path, output_path: Path) -> list[str]:
    result = subprocess.run(
        [ffprobe, "-v", "warning", str(video_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    text = (result.stdout or "") + (result.stderr or "")
    output_path.write_text(text)
    return [line for line in text.splitlines() if line.strip()]


def run_decode_smoke(
    ffmpeg: str,
    output_path: Path,
    metrics_dir: Path,
    stem: str,
    has_audio: bool,
) -> dict:
    command = [
        ffmpeg,
        "-v",
        "error",
        "-nostdin",
        "-i",
        str(output_path),
        "-map",
        "0:v:0",
    ]
    if has_audio:
        command += ["-map", "0:a:0?"]
    command += ["-f", "null", "-"]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    path = metrics_dir / f"{stem}.decode-smoke.stderr.log"
    path.write_text(result.stderr or "")
    return {
        "path": str(path),
        "return_code": result.returncode,
        "stderr_lines": [line for line in (result.stderr or "").splitlines() if line.strip()][:20],
    }


def timestamp_packet_stats(ffprobe: str, video_path: Path, stream: str) -> dict:
    command = [
        ffprobe,
        "-v",
        "error",
        "-select_streams",
        stream,
        "-show_packets",
        "-show_entries",
        "packet=pts_time,dts_time,duration_time",
        "-of",
        "csv=p=0",
        str(video_path),
    ]
    stats = empty_timestamp_stats()
    previous_pts: float | None = None
    previous_dts: float | None = None
    for index, row in enumerate(read_csv_rows(command)):
        stats["count"] += 1
        pts = parse_float(row[0]) if len(row) > 0 else None
        dts = parse_float(row[1]) if len(row) > 1 else None
        duration = parse_float(row[2]) if len(row) > 2 else None
        update_timestamp_axis(stats, "pts", index, previous_pts, pts)
        update_timestamp_axis(stats, "dts", index, previous_dts, dts)
        if pts is not None:
            previous_pts = pts
        if dts is not None:
            previous_dts = dts
        if duration is None:
            stats["missing_duration_count"] += 1
        elif duration <= 0:
            stats["non_positive_duration_count"] += 1
    return finish_timestamp_stats(stats)


def timestamp_frame_stats(ffprobe: str, video_path: Path, stream: str) -> dict:
    data = run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            stream,
            "-show_frames",
            "-show_entries",
            "frame=best_effort_timestamp_time,pts_time,pkt_duration_time",
            "-print_format",
            "json",
            str(video_path),
        ]
    )
    stats = empty_timestamp_stats()
    previous: float | None = None
    for index, frame in enumerate(data.get("frames", [])):
        stats["count"] += 1
        timestamp = parse_float(frame.get("best_effort_timestamp_time"))
        if timestamp is None:
            timestamp = parse_float(frame.get("pts_time"))
        update_timestamp_axis(stats, "pts", index, previous, timestamp)
        if timestamp is not None:
            previous = timestamp
        duration = parse_float(frame.get("pkt_duration_time"))
        if duration is None:
            stats["missing_duration_count"] += 1
        elif duration <= 0:
            stats["non_positive_duration_count"] += 1
    stats["missing_dts_count"] = 0
    stats["duplicate_dts_count"] = 0
    stats["non_monotonic_dts_count"] = 0
    return finish_timestamp_stats(stats)


def empty_timestamp_stats() -> dict:
    return {
        "count": 0,
        "missing_pts_count": 0,
        "missing_dts_count": 0,
        "missing_duration_count": 0,
        "non_positive_duration_count": 0,
        "non_monotonic_pts_count": 0,
        "non_monotonic_dts_count": 0,
        "duplicate_pts_count": 0,
        "duplicate_dts_count": 0,
        "negative_interval_count": 0,
        "zero_interval_count": 0,
        "negative_pts_count": 0,
        "negative_dts_count": 0,
        "min_positive_delta_s": None,
        "max_gap_s": 0.0,
        "first_bad_indices": [],
    }


def update_timestamp_axis(
    stats: dict,
    axis: str,
    index: int,
    previous: float | None,
    current: float | None,
) -> None:
    missing_key = f"missing_{axis}_count"
    duplicate_key = f"duplicate_{axis}_count"
    non_monotonic_key = f"non_monotonic_{axis}_count"
    negative_key = f"negative_{axis}_count"
    if current is None:
        stats[missing_key] += 1
        add_bad_index(stats, index)
        return
    if current < 0:
        stats[negative_key] += 1
        add_bad_index(stats, index)
    if previous is None:
        return
    delta = current - previous
    if delta < 0:
        stats[non_monotonic_key] += 1
        stats["negative_interval_count"] += 1
        add_bad_index(stats, index)
    elif delta == 0:
        stats[duplicate_key] += 1
        stats["zero_interval_count"] += 1
        add_bad_index(stats, index)
    else:
        if stats["min_positive_delta_s"] is None or delta < stats["min_positive_delta_s"]:
            stats["min_positive_delta_s"] = delta
        if delta > stats["max_gap_s"]:
            stats["max_gap_s"] = delta


def add_bad_index(stats: dict, index: int) -> None:
    if len(stats["first_bad_indices"]) < 20:
        stats["first_bad_indices"].append(index)


def finish_timestamp_stats(stats: dict) -> dict:
    if stats["min_positive_delta_s"] is not None:
        stats["min_positive_delta_s"] = round(float(stats["min_positive_delta_s"]), 9)
    stats["max_gap_s"] = round(float(stats["max_gap_s"]), 9)
    return stats


def count_micro_intervals(
    ffprobe: str,
    video_path: Path,
    stream: str,
    source_min_interval: float,
) -> int:
    if source_min_interval <= 0:
        return 0
    threshold = max(0.001, 0.25 * source_min_interval)
    data = run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            stream,
            "-show_frames",
            "-show_entries",
            "frame=best_effort_timestamp_time,pts_time",
            "-print_format",
            "json",
            str(video_path),
        ]
    )
    previous: float | None = None
    count = 0
    for frame in data.get("frames", []):
        timestamp = parse_float(frame.get("best_effort_timestamp_time"))
        if timestamp is None:
            timestamp = parse_float(frame.get("pts_time"))
        if timestamp is None:
            continue
        if previous is not None:
            delta = timestamp - previous
            if 0 < delta < threshold:
                count += 1
        previous = timestamp
    return count


def build_validation_issues(
    input_path: Path,
    output_path: Path,
    args: argparse.Namespace,
    source_probe: dict,
    output_probe: dict,
    encode_log: dict,
    source_warnings: list[str],
    output_warnings: list[str],
    decode_log: dict,
    output_video_packet_stats: dict,
    output_audio_packet_stats: dict,
    output_frame_stats: dict,
    alignment: dict,
) -> list[str]:
    issues: list[str] = []
    source_video = first_video_stream(source_probe)
    output_video = first_video_stream(output_probe)
    source_audio = first_audio_stream(source_probe)
    output_audio = first_audio_stream(output_probe)

    if not output_path.is_file() or output_path.stat().st_size <= 0:
        issues.append("output file is missing or empty")
    if encode_log.get("timestamp_warning_count", 0) != 0:
        issues.append("ffmpeg encode log contains timestamp warnings")
    if output_warnings:
        issues.append("ffprobe -v warning emitted output warnings")
    if decode_log.get("return_code") != 0:
        issues.append("full decode smoke failed")
    if output_video.get("codec_name") != "av1":
        issues.append("output video codec is not AV1")
    if output_video.get("pix_fmt") != "yuv420p":
        issues.append("output pixel format is not yuv420p")
    if not resolution_matches(source_video, output_video):
        issues.append("output resolution does not match source")
    if not audio_policy_pass(args.audio, source_audio, output_audio):
        issues.append("audio policy failed")
    check_timestamp_stats("video packet", output_video_packet_stats, issues, require_dts=True)
    if output_audio:
        check_timestamp_stats("audio packet", output_audio_packet_stats, issues, require_dts=True)
    check_timestamp_stats("video frame", output_frame_stats, issues, require_dts=False)
    if alignment["video_frame_count_delta"] != 0:
        issues.append("video frame count changed")
    if abs(alignment["video_duration_delta_s"]) > video_duration_tolerance(source_probe):
        issues.append("video duration delta exceeds tolerance")
    if abs(alignment["audio_duration_delta_s"]) > 0.5:
        issues.append("audio duration delta exceeds tolerance")
    if abs(alignment["format_duration_delta_s"]) > max(1.0, 0.001 * (probe_duration(source_probe) or 0.0)):
        issues.append("format duration delta exceeds tolerance")
    if abs(alignment["av_end_gap_delta_s"]) > 0.5:
        issues.append("audio/video end-gap delta exceeds tolerance")
    if abs(alignment["start_time_delta_s"]) > 0.1:
        issues.append("video start-time delta exceeds tolerance")
    if alignment["introduced_micro_interval_count"] != 0:
        issues.append("output introduced micro frame intervals")
    return issues


def check_timestamp_stats(label: str, stats: dict, issues: list[str], require_dts: bool) -> None:
    if stats["count"] <= 0:
        issues.append(f"{label} timestamps are missing")
        return
    for key in ("missing_pts_count", "non_monotonic_pts_count", "duplicate_pts_count"):
        if stats.get(key, 0) != 0:
            issues.append(f"{label} {key} is nonzero")
    if require_dts:
        for key in ("missing_dts_count", "non_monotonic_dts_count", "duplicate_dts_count", "negative_dts_count"):
            if stats.get(key, 0) != 0:
                issues.append(f"{label} {key} is nonzero")
    if stats.get("negative_pts_count", 0) != 0:
        issues.append(f"{label} negative_pts_count is nonzero")
    if "packet" in label:
        if stats.get("missing_duration_count", 0) != 0:
            issues.append(f"{label} missing_duration_count is nonzero")
        if stats.get("non_positive_duration_count", 0) != 0:
            issues.append(f"{label} non_positive_duration_count is nonzero")


def video_duration_tolerance(source_probe: dict) -> float:
    stream = first_video_stream(source_probe)
    avg_interval = 0.0
    frames = frame_count(stream)
    duration = stream_duration(stream)
    if frames > 0 and duration > 0:
        avg_interval = duration / frames
    return max(0.25, 4 * avg_interval)


def resolution_matches(source_video: dict, output_video: dict) -> bool:
    return (
        source_video.get("width") == output_video.get("width")
        and source_video.get("height") == output_video.get("height")
    )


def audio_policy_pass(mode: str, source_audio: dict, output_audio: dict) -> bool:
    if not source_audio:
        return not output_audio
    if not output_audio:
        return False
    if mode == "copy":
        return (
            source_audio.get("codec_name") == output_audio.get("codec_name")
            and source_audio.get("channels") == output_audio.get("channels")
            and source_audio.get("sample_rate") == output_audio.get("sample_rate")
        )
    if mode in ("aac-mono-48k", "aac-mono-64k"):
        return (
            output_audio.get("codec_name") == "aac"
            and parse_int(output_audio.get("channels")) == 1
            and output_audio.get("sample_rate") == "48000"
        )
    return False


def replacement_blocked_reasons(input_path: Path, output_path: Path, issues: list[str]) -> list[str]:
    reasons = list(issues)
    if issues:
        reasons.append("strict timestamp validation did not pass")
    if input_path.is_symlink():
        reasons.append("source is a symlink")
    if input_path.suffix.lower() not in (".mp4", ".mov"):
        reasons.append("source is not an MP4/MOV file")
    if output_path.is_file() and input_path.is_file():
        required_savings = max(1024 * 1024, int(input_path.stat().st_size * 0.05))
        if input_path.stat().st_size - output_path.stat().st_size < required_savings:
            reasons.append("output is not smaller than source by the replacement threshold")
    return reasons


def read_csv_rows(command: list[str]) -> Iterable[list[str]]:
    process = subprocess.Popen(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    reader = csv.reader(process.stdout)
    for row in reader:
        yield row
    stderr = process.stderr.read() if process.stderr else ""
    returncode = process.wait()
    if returncode != 0:
        raise CliError(f"ffprobe failed with exit code {returncode}: {stderr.strip()}")


def write_window_csv(
    packets: list[dict[str, float | int | str]],
    duration: float,
    window_seconds: float,
    output_path: Path,
) -> None:
    bytes_by_window: dict[int, int] = defaultdict(int)
    for packet in packets:
        timestamp = float(packet["pts_time"])
        index = max(0, int(math.floor(timestamp / window_seconds)))
        bytes_by_window[index] += int(packet["size"])

    window_count = max(1, int(math.ceil(duration / window_seconds)))
    with output_path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["window_start_s", "window_end_s", "video_bytes", "video_kbps"])
        for index in range(window_count):
            video_bytes = bytes_by_window.get(index, 0)
            writer.writerow(
                [
                    round(index * window_seconds, 6),
                    round((index + 1) * window_seconds, 6),
                    video_bytes,
                    round((video_bytes * 8) / window_seconds / 1000, 6),
                ]
            )


def build_summary(
    probe: dict,
    packets: list[dict[str, float | int | str]],
    frames: list[dict[str, float]],
    duration: float,
) -> dict:
    packet_sizes = [int(packet["size"]) for packet in packets]
    frame_intervals = [frame["interval_s"] for frame in frames[1:] if frame["interval_s"] > 0]
    one_second_bitrates = window_bitrates(packets, duration, 1.0)
    five_second_bitrates = window_bitrates(packets, duration, 5.0)
    return {
        "file": probe.get("format", {}).get("filename"),
        "duration_s": duration,
        "video_codec": first_video_stream(probe).get("codec_name"),
        "width": first_video_stream(probe).get("width"),
        "height": first_video_stream(probe).get("height"),
        "packet_count": len(packet_sizes),
        "packet_size_bytes": describe_numbers(packet_sizes),
        "tiny_packet_threshold_bytes": TINY_PACKET_BYTES,
        "tiny_packet_ratio": ratio(
            sum(1 for size in packet_sizes if size <= TINY_PACKET_BYTES),
            len(packet_sizes),
        ),
        "one_second_video_kbps": describe_numbers(one_second_bitrates),
        "five_second_video_kbps": describe_numbers(five_second_bitrates),
        "frame_count": len(frames),
        "frame_interval_s": describe_numbers(frame_intervals),
        "vfr_signal": {
            "unique_intervals_rounded_ms": len({round(value * 1000) for value in frame_intervals}),
            "max_minus_min_interval_s": (
                max(frame_intervals) - min(frame_intervals) if frame_intervals else 0.0
            ),
            "looks_variable": looks_variable_frame_rate(frame_intervals),
        },
    }


def first_video_stream(probe: dict) -> dict:
    for stream in probe.get("streams", []):
        if stream.get("codec_type") == "video":
            return stream
    return {}


def first_audio_stream(probe: dict) -> dict:
    for stream in probe.get("streams", []):
        if stream.get("codec_type") == "audio":
            return stream
    return {}


def probe_duration(probe: dict) -> float | None:
    duration = parse_float(probe.get("format", {}).get("duration"))
    return duration if duration and duration > 0 else None


def stream_duration(stream: dict) -> float:
    return parse_float(stream.get("duration")) or 0.0


def stream_start_time(stream: dict) -> float:
    return parse_float(stream.get("start_time")) or 0.0


def frame_count(stream: dict) -> int:
    return parse_int(stream.get("nb_frames")) or 0


def infer_duration(packets: list[dict[str, float | int | str]]) -> float:
    if not packets:
        return 0.0
    return max(float(packet["pts_time"]) + float(packet["duration_time"]) for packet in packets)


def window_bitrates(
    packets: list[dict[str, float | int | str]],
    duration: float,
    window_seconds: float,
) -> list[float]:
    bytes_by_window: dict[int, int] = defaultdict(int)
    for packet in packets:
        index = max(0, int(math.floor(float(packet["pts_time"]) / window_seconds)))
        bytes_by_window[index] += int(packet["size"])
    window_count = max(1, int(math.ceil(duration / window_seconds)))
    return [
        (bytes_by_window.get(index, 0) * 8) / window_seconds / 1000
        for index in range(window_count)
    ]


def describe_numbers(values: list[int] | list[float]) -> dict:
    if not values:
        return {"count": 0}
    numeric = [float(value) for value in values]
    return {
        "count": len(numeric),
        "min": round(min(numeric), 6),
        "median": round(statistics.median(numeric), 6),
        "mean": round(statistics.fmean(numeric), 6),
        "max": round(max(numeric), 6),
    }


def looks_variable_frame_rate(intervals: list[float]) -> bool:
    if len(intervals) < 3:
        return False
    rounded_ms = {round(value * 1000) for value in intervals}
    return len(rounded_ms) > 2 or (max(intervals) - min(intervals)) > 0.002


def ratio(numerator: int, denominator: int) -> float:
    if denominator == 0:
        return 0.0
    return round(numerator / denominator, 6)


def parse_float(value: object) -> float | None:
    try:
        if value in (None, "", "N/A"):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_int(value: object) -> int | None:
    try:
        if value in (None, "", "N/A"):
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def shlex_join(command: list[str]) -> str:
    import shlex

    return shlex.join(command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
