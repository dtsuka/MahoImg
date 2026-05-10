# MahoImg

MahoImg is a personal macOS desktop app for batch image conversion, resizing, padding, and drag-based cropping.

## Requirements

- macOS 14 or later
- Swift 6 toolchain / Xcode command line tools
- ImageMagick at `/opt/homebrew/bin/magick`

Check WebP support:

```sh
magick -version
```

The `Delegates` line should include `webp`.

## Development

```sh
swift run MahoImg
```

## Build App Bundle

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open dist/MahoImg.app
```

The app icon source is `Assets/AppIcon.png`; the generated macOS icon file is `Assets/AppIcon.icns`.

## Features

- Drop image files or folders into the window.
- Accept JPEG, PNG, WebP, HEIC/HEIF, TIFF, PSD, and PSB input files.
- Convert to JPEG, PNG, or WebP.
- Resize with none, fit, fill-crop, width, height, or exact size modes.
- Crop by dragging the preview rectangle and resizing from its corner handles.
- Add optional padding with a selected color.
- Save beside the original or into a selected folder.
- Add filename prefix/suffix.
- Avoid overwrites by default with numbered output names.
