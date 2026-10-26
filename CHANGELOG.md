# Changelog

## 1.0.1 - 2026-10-26

- Fix the full-window viewer's arrow keys stepping from the item you clicked instead of the one currently shown (#17).
- README screenshot and a demo mode (`PHOTOVAULT_DEMO_FOLDER`) for taking screenshots without a phone or personal photos.

## 1.0.0 - 2026-10-26

First release.

- Detects an iPhone over USB (ImageCaptureCore) and lists every photo and video.
- Incremental backup of original files (HEIC stays HEIC) into `~/Pictures/{device name}`, one folder per iPhone, with size verification and no overwrites.
- Auto-backup when the phone is connected, with a notification when it finishes.
- Photos-style gallery: day groups (collapsible), cached thumbnails, full-window viewer, video and Live Photo playback.
- Favorites, search, map view and duplicate finder.
- Packaged as a universal `PhotoVault.app` (ad-hoc signed) with `.dmg` and `.zip` via `scripts/package.sh`.
