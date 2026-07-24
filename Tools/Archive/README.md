# Archive Tools

These scripts provide reproducible AV1 archive and FFmpeg runtime packaging
workflows for developers.

- `archive_av1_crf.py`: quality-driven SVT-AV1 archive encoding;
- `archive_av1.py`: bitrate-constrained archive encoding;
- `run_timestamp_matrix.py`: timestamp-mode comparison and validation;
- `package_ffmpeg_runtime.py`: package a local FFmpeg/FFprobe runtime.

Run each script with `--help` for its current options. Generated recordings,
metrics, binaries, and local paths are not committed to the repository.
