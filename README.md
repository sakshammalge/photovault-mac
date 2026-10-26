# PhotoVault

A native macOS app that backs up the photos and videos from your iPhone's camera roll to a folder on your Mac, as untouched originals, and lets you browse the backup in a Photos-style gallery.

## Status

Step 2 of 4: incremental backup.

- [x] Detect an iPhone plugged in over USB (ImageCaptureCore)
- [x] List every photo and video with name, date, size and type
- [x] Incremental backup into `~/Pictures/IphoneBackup`
- [ ] Gallery UI for the backup folder
- [ ] Auto-backup on connect, packaging as a .app

## Run it

Requires macOS 13+ and Xcode (or the Xcode command line tools).

```sh
swift run
```

Or open `Package.swift` in Xcode and press Run.

Then plug in your iPhone, unlock it, and tap **Trust** if asked. The first time, macOS may ask for permission to access connected devices.

The app asks the phone for original files (`mediaPresentation = .originalAssets`), so HEIC stays HEIC and nothing gets converted. Photos whose originals live only in iCloud ("Optimize iPhone Storage") aren't on the phone and won't show up.

## How the backup works

- Press **Back Up N New Items**. Only items not already in the backup are copied, oldest first.
- Files go into `~/Pictures/IphoneBackup/YEAR/MONTH/`, keeping the phone's file names and capture dates. Live Photo videos and edit files (`.AAE`) are copied next to their photo.
- Each file is downloaded into `.photovault/incoming/` first and only moved into place once its size matches the phone's. Nothing is ever overwritten; a name clash gets a ` (2)` suffix.
- What has been backed up is recorded in `.photovault/index.json`, so a stopped or failed backup picks up where it left off. Files you already copied into the folder with the same name and size are recognised and not downloaded again.
- Nothing on the phone is changed or deleted.
