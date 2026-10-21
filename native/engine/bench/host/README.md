# Host tests (October 21, 2026, on the M6)

The scripts behind sections 10 to 16 of pubkit's `docs/research/simulator-engine-2026-10-21/README.md`. They run as
root on a Simulator host with the pool users `nmsim1` and `nmsim2` (`session.sh users 2`) and a golden phone in
`/Library/NoMacSim/golden/current` (`session.sh golden`). `head.sh` holds the shared functions (a session's start and
end, the account volume, builds, installs); each `*-body.sh` is appended to it (`cat head.sh x-body.sh > x.sh`).

- `core-loop.sh`, `e3b.sh`, `e3c-body.sh`: the account's build cache across sessions and users.
- `e3d-body.sh` (warm-up, with `prewarm/` and `prewarm-app/`), `e3e-body.sh` (the cache moved through R2; needs
  presigned URLs in `/tmp/presigned.env`, quoted).
- `iso-body.sh`, `iso2-body.sh`: one tenant against another, and the pf rules per pool user.
- `soak-body.sh`: 12 sessions back to back; `t9-body.sh` with `t9.py`: a noisy neighbour.
- `expo2-body.sh`, `expo3-body.sh` with `expo3.py` and `metro-reload.mjs`: Expo Go from Metro on the session's port.
- `longrun.py`: one engine on one phone for an hour; `fswatch.sh`: file events for a pool user.
- `read.py`, `ts.py`, `ips.py`: small readers for the engine's answers, timestamps and crash reports.
- `../live/`: the live view through a relay to a browser (`relay.mjs`, `page.html`, `measure.mjs`).
- `smalls-body.sh`: status bar, appearance, location, permissions, push, photos, clipboard, locale, recording.
- `safari-body.sh`, `golden-per-user-body.sh`: Safari's crash in goldens made by another user, and the per-user golden.
- `clone-body.sh`: phones cloned from a root-owned golden on a permanent per-user volume.
- `webread-body.sh` with `webread.py`: reading a web page (whole-screen and point reads, AXe for comparison).
- `pboard-body.sh`, `pbset-body.sh` with `paste.py`, `su-paste-body.sh`: the clipboard without a screen session.
- `ipad-body.sh` with `ipad.py`; `manifest.py`: a sync manifest's cost.
