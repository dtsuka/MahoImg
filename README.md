# MahoImg

MahoImg は、画像や PDF をまとめて変換するための macOS アプリです。JPEG、PNG、WebP への書き出し、リサイズ、トリミング、余白追加、ファイル名の接頭辞/接尾辞付けができます。

MahoImg is a macOS app for converting images and PDFs in batches. It can export to JPEG, PNG, or WebP, resize files, crop previews, add padding, and apply filename prefixes or suffixes.

## できること / What It Does

- JPEG、PNG、WebP、HEIC/HEIF、TIFF、PSD、PSB、PDF を読み込めます。
- JPEG、PNG、WebP に書き出せます。
- 複数ファイルやフォルダをまとめて追加できます。
- PDF はページを選んで 1 アイテムとして追加するか、全ページを個別アイテムとして追加できます。
- PSD/PSB は統合済みの静止画として書き出します。
- 画像を指定サイズに収める、幅だけ指定する、高さだけ指定する、強制的に幅高さを合わせる、といったリサイズができます。
- プレビュー上でトリミング範囲を調整できます。
- 余白と余白色を指定できます。
- 元ファイルと同じ場所、または選択したフォルダに保存できます。
- 同名ファイルがある場合は、標準では連番を付けて上書きを避けます。

- Imports JPEG, PNG, WebP, HEIC/HEIF, TIFF, PSD, PSB, and PDF files.
- Exports to JPEG, PNG, or WebP.
- Adds multiple files or folders at once.
- For PDFs, you can add one selectable-page item or add every page as a separate item.
- Exports PSD/PSB files as flattened still images.
- Supports several resize modes: fit inside a size, width only, height only, exact width and height, and more.
- Lets you adjust the crop area in the preview.
- Can add padding with a selected color.
- Saves next to the original file or into a selected folder.
- Avoids overwriting files by adding sequence numbers by default.

## 使い方 / How To Use

1. アプリを開きます。
2. 左上の `+` ボタン、またはウィンドウへのドラッグ&ドロップで画像やフォルダを追加します。
3. 右側のパネルで出力形式、品質、リサイズ、トリミング、余白、保存先、ファイル名を設定します。
4. PDF が複数ページの場合は、追加時に「ページを選んで追加」または「全ページを追加」を選びます。
5. `変換実行` を押します。
6. 失敗した場合は、左側のリストに赤字で理由が表示されます。

1. Open the app.
2. Add images or folders with the `+` button or by dropping them onto the window.
3. Use the right-side panel to choose output format, quality, resize, crop, padding, save location, and filename options.
4. For multi-page PDFs, choose either "add as one selectable-page item" or "add every page".
5. Press `変換実行` to run conversion.
6. If conversion fails, the reason appears in red in the left-side list.

## ImageMagick のインストール / Installing ImageMagick

WebP 書き出しなどの変換処理には ImageMagick が必要です。Homebrew を使っている場合は、ターミナルで次を実行してください。

ImageMagick is required for conversion tasks such as WebP export. If you use Homebrew, run the following command in Terminal.

```sh
brew install imagemagick
```

インストール後、次のコマンドで確認できます。

After installation, you can check it with:

```sh
magick -version
```

MahoImg は標準で Homebrew 版の `/opt/homebrew/bin/magick` を使用します。Homebrew が入っていない場合は、先に [Homebrew](https://brew.sh/) をインストールしてください。

MahoImg uses the Homebrew path `/opt/homebrew/bin/magick` by default. If Homebrew is not installed, install [Homebrew](https://brew.sh/) first.

## 注意点 / Notes

- WebP 書き出しには ImageMagick が必要です。
- 保存先フォルダが存在しない場合、変換は失敗します。保存先を選び直してください。
- PDF はアプリ内で一度画像化してから変換します。細かいベクター情報は出力画像の解像度に依存します。
- PSD/PSB はレイヤーごとではなく、統合済み画像として扱います。

- ImageMagick is required for WebP export.
- Conversion fails if the selected output folder does not exist. Choose the save folder again.
- PDFs are rasterized before conversion, so fine vector details depend on the output image resolution.
- PSD/PSB files are treated as flattened still images, not layer-by-layer animations.

---

## Developer Notes / 開発者向け情報

### Requirements

- macOS 14 or later
- Swift 6 toolchain / Xcode command line tools
- ImageMagick at `/opt/homebrew/bin/magick`

Check WebP support:

```sh
magick -version
```

The `Delegates` line should include `webp`.

### Development

```sh
swift run MahoImg
```

### Test

```sh
swift test
```

### Build App Bundle

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open dist/MahoImg.app
```

The app version is stored in `VERSION`. `scripts/build-app.sh` reads that file and writes it into `CFBundleShortVersionString`.

The app icon source is `Assets/AppIcon.png`; the generated macOS icon file is `Assets/AppIcon.icns`.
