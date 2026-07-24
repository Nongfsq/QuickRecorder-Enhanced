#!/usr/bin/env python3
"""
Run AV1 timestamp-mode experiments across one or more QuickRecorder masters.

This runner intentionally delegates encoding and validation to archive_av1_crf.py.
It exists so full-length timestamp repair experiments are reproducible and logs
land in deterministic per-source/per-mode directories.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


DEFAULT_TIMESTAMP_MODES = (
    "legacy-passthrough",
    "vfr-clean",
    "passthrough-timescale",
    "preclean-vfr",
    "remux-clean",
)


class CliError(RuntimeError):
    """Expected user-facing command error."""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run archive_av1_crf.py across timestamp modes for full-length samples."
    )
    parser.add_argument("inputs", nargs="+", type=Path, help="Input QuickRecorder master videos")
    parser.add_argument(
        "--timestamp-mode",
        action="append",
        choices=DEFAULT_TIMESTAMP_MODES + ("cfr-15",),
        help="Timestamp mode to test; repeatable. Defaults to all non-CFR modes.",
    )
    parser.add_argument("--crf", type=int, default=58, help="CRF to test (default: 58)")
    parser.add_argument(
        "--audio",
        choices=("copy", "aac-mono-48k", "aac-mono-64k"),
        default="aac-mono-64k",
        help="Audio mode to test (default: aac-mono-64k)",
    )
    parser.add_argument("--preset", type=int, default=8, help="SVT-AV1 preset (default: 8)")
    parser.add_argument("--gop", type=int, default=270, help="GOP length (default: 270)")
    parser.add_argument(
        "--output-root",
        type=Path,
        required=True,
        help="Root directory for timestamp experiment outputs",
    )
    parser.add_argument(
        "--no-strict",
        action="store_true",
        help="Do not pass --strict-timestamps to archive_av1_crf.py",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing outputs")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running them")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        script = Path(__file__).with_name("archive_av1_crf.py").resolve()
        if not script.is_file():
            raise CliError(f"archive script not found: {script}")
        modes = tuple(args.timestamp_mode or DEFAULT_TIMESTAMP_MODES)
        validation_failures = 0
        for input_path in [path.expanduser().resolve() for path in args.inputs]:
            if not input_path.is_file():
                raise CliError(f"input file does not exist: {input_path}")
            for mode in modes:
                command = build_command(script, input_path, args, mode)
                print("$ " + shlex_join(command), flush=True)
                if args.dry_run:
                    continue
                result = subprocess.run(command)
                if result.returncode == 3:
                    validation_failures += 1
                    continue
                if result.returncode != 0:
                    return result.returncode
        if validation_failures:
            print(f"timestamp matrix completed with {validation_failures} validation failure(s)", file=sys.stderr)
            return 3
        return 0
    except CliError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def build_command(script: Path, input_path: Path, args: argparse.Namespace, mode: str) -> list[str]:
    source_dir = safe_source_dir_name(input_path)
    output_dir = args.output_root.expanduser().resolve() / source_dir / mode / "outputs"
    metrics_dir = args.output_root.expanduser().resolve() / source_dir / mode / "metrics"
    command = [
        sys.executable,
        str(script),
        str(input_path),
        "--crf",
        str(args.crf),
        "--audio",
        args.audio,
        "--preset",
        str(args.preset),
        "--gop",
        str(args.gop),
        "--timestamp-mode",
        mode,
        "--output-dir",
        str(output_dir),
        "--metrics-dir",
        str(metrics_dir),
    ]
    if not args.no_strict:
        command.append("--strict-timestamps")
    if args.force:
        command.append("--force")
    return command


def safe_source_dir_name(path: Path) -> str:
    stem = "".join(ch if ch.isalnum() or ch in ("-", "_", ".") else "-" for ch in path.stem)
    return stem.strip("-") or "source"


def shlex_join(command: list[str]) -> str:
    import shlex

    return shlex.join(command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
