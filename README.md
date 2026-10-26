# PhotoVault

A native macOS app that backs up the photos and videos from your iPhone's camera roll to a folder on your Mac, as untouched originals, and lets you browse the backup in a Photos-style gallery.

## Status

Step 1 of 4: connect to the iPhone over a cable and list its camera roll.

- [x] Detect an iPhone plugged in over USB (ImageCaptureCore)
- [x] List every photo and video with name, date, size and type
- [x] "Test download" one file and confirm its size matches the original on the phone
- [ ] Incremental backup into a dedicated folder
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
