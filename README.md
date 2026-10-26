# PhotoVault

A native macOS app that backs up the photos and videos from your iPhone's camera roll to a folder on your Mac, as untouched originals, and lets you browse the backup in a Photos-style gallery.

## Status

Step 4 of 4: auto-backup.

- [x] Detect an iPhone plugged in over USB (ImageCaptureCore)
- [x] List every photo and video with name, date, size and type
- [x] Incremental backup into `~/Pictures/IphoneBackup`
- [x] Gallery for the backup folder (grouped by day, cached thumbnails, full-screen viewer, video, Live Photos)
- [x] Auto-backup on connect, with a notification when it finishes
- [ ] Packaging as a .app

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

## Auto-backup

When the iPhone is connected, unlocked and trusted, and its camera roll has been read, PhotoVault starts the incremental backup by itself, once per connection, and posts a notification when it finishes (item count, or how many failed). Turn it off with the checkbox on the device screen; the choice is remembered. Under `swift run` the notification is sent via `osascript` and may appear as "Script Editor"; from a packaged .app it uses the normal notification centre.

## Gallery

The **Gallery** tab shows everything in the backup folder, newest first, grouped by day. It reads the folder directly, so it works without the phone connected.

- Thumbnails are cached in memory and in `.photovault/thumbs/`; the slider in the toolbar changes their size.
- Click a photo or video to open it full window. Left/right arrows move between items, Esc closes. HEIC opens like any other photo.
- A video saved next to a photo with the same name is treated as that photo's Live Photo clip: it is hidden from the grid and plays from the LIVE button in the viewer.
- The gallery only reads your original files; the only thing it writes is the thumbnail cache.
