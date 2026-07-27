# Archive Tools

These scripts provide local AV1 archive workflows and FFmpeg runtime snapshots
for developers. The runtime packager accepts explicitly selected local binaries
and dependencies; it is not yet a reproducible public-release toolchain.

- `archive_av1_crf.py`: quality-driven SVT-AV1 archive encoding;
- `archive_av1.py`: bitrate-constrained archive encoding;
- `run_timestamp_matrix.py`: timestamp-mode comparison and validation;
- `package_ffmpeg_runtime.py`: package a local FFmpeg/FFprobe runtime.

Run each script with `--help` for its current options. Generated recordings,
metrics, binaries, and local paths are not committed to the repository.
Generated manifests can contain local provenance and must not be published
without the release checks in `../../docs/architecture/target-architecture.md`.
