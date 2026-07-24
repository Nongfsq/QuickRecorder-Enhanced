# RNNoiseProcessor

Local Swift wrapper around Xiph RNNoise for QuickRecorder microphone cleanup.

- Upstream: `https://gitlab.xiph.org/xiph/rnnoise`
- Pinned commit: `70f1d256acd4b34a572f999a05c87bf00b67730d`
- Model SHA-256: `1b99898350e75656c77d068162fea402afe51eff15dc751989b1e9f53b98bf91`
- License: BSD 3-Clause; see `COPYING`

The runtime uses 48 kHz mono, 480-sample frames, and a fixed 80% processed /
20% dry mix selected from the lecture recording listening test.
