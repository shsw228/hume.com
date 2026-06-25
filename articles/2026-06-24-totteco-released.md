---
title: Totteco をリリースした
description: 透過素材をライブカメラに重ねて撮る iOS アプリ Totteco を公開した。作っていて引っかかった箇所をいくつか残しておく。
pubDate: 2026-06-24
tags: [iOS, SwiftUI, AVFoundation, CoreImage]
draft: false
---

iOS アプリ Totteco を公開した。

https://totteco.pages.dev/

透過 PNG をライブカメラに重ねて撮るカメラアプリで、素材は本体内で撮影 + 被写体抽出して作るか、他アプリから Share Extension で渡す。推しキャラ、ぬいぐるみ、離れた家族や猫を、いま目の前にある景色と一緒に撮りたい、という用途で組んだ。AR は持ち込まず透過 PNG の重畳合成だけで閉じている。

以下、作る中で引っかかった箇所をいくつか残しておく。

## RotationCoordinator は入れなかった

最初は素直に `AVCaptureDevice.RotationCoordinator` を入れて、プレビューと撮影 connection の `videoRotationAngle` を端末向きで動かしていた。これだと横持ち撮影時に降ってくる pixel そのものが landscape サイズになる。

問題はオーバーレイ配置。素材は SwiftUI の `OverlayAlignedContent`（aspectFit + alignment + rotation）で見た目を作っていて、撮影時はこの見た目を `CGAffineTransform` 1 個に翻訳して焼き込む。pixel サイズが向きで変わると、`PhotoCropSpec`（センサ画像から「プレビューが見せている領域」を切り出す仕様）も overlay transform も縦横で分岐する羽目になる。

なので RotationCoordinator は捨てた。`videoDataOutput` / `photoOutput` / `videoPreviewLayer` の各 connection を 90° に固定して、pixel は常に portrait で書き出す。横持ち時は EXIF Orientation だけ書き換える:

- 0°    → 1 (up)
- +90°  → 8 (left)
- -90°  → 6 (right)
- 180°  → 3 (down)

`overlayRotation` は別途 ViewState 側で端末向きを観測して合成側に渡し、overlay 焼き込みでだけ処理する。ビューアは EXIF を見て回してくれるので、保存写真も向きに沿って表示される。

ハマったのは `switchToDevice(_:)`。`beginConfiguration` → `removeInput` → `addInput` をやると、新しい connection はデフォルト 0° で生えてくる。`commitConfiguration` の前に 90° に戻し直さないと、レンズ切替の直後だけ横向き sample buffer / 撮影が数フレーム漏れる。

## プレビューを 2 経路に流す

「フィルタなしのライブ」と「フィルタ適用済のライブ」を切り替えたかったので、最初は `AVCaptureVideoPreviewLayer` を 2 つ session に attach した。これをやると session が一定確率でハングする。

そこで `AVCaptureVideoDataOutput` の sample buffer を broadcaster で複数 consumer に配信する作りにした。プレビュー側は `AVCaptureVideoPreviewLayer` を使わず、生バッファは `AVSampleBufferDisplayLayer` に、フィルタ付きは `CIContext` を通したレイヤに流す。

```
AVCaptureVideoDataOutput
  └─ DefaultSampleBufferBroadcaster
        ├─ SampleBufferPreview     (AVSampleBufferDisplayLayer)
        └─ FilteredPreviewLayer    (CIContext → MTKView 風)
```

副次的な利点として、フィルタ適用範囲（`PreviewMaskMode` の crop / mask）やプリセット切替が、配信されてくる同一の sample buffer の見せ方を変えるだけになる。

## 合成は Display P3 を貫く

`OverlayCompositionService` は `@MainActor struct`、CoreImage + Metal で組んでいる。`CIContext` は Metal device 指定で静的に 1 個。

ワーキングスペースは linear Display P3 で固定。出力 ICC はフォーマットで切り替える:

- HEIC: 8bit / Display P3（iPhone カメラのデフォルトと一致）
- JPEG: 8bit / sRGB（Android / 旧ビューア互換）
- TIFF: 16bit / Display P3（アーカイブ用）

`CIContext` の options に出力 colorSpace を入れるとフォーマットごとに context を分ける必要が出るので、出力は `createCGImage(_:from:format:colorSpace:)` の引数で都度切り替える方式にした。context は 1 個だけ持っていれば良い。

撮影は `maxPhotoQualityPrioritization = .speed`。Smart HDR / Deep Fusion / Night mode のマルチフレーム合成を意図的に抑制している。シャッターラグを縮めたかったのと、合成パイプラインを自前で完結させたかったので、撮影側に余計なフレーム合成を入れさせたくなかった。

## Store と ViewState を分ける

アーキテクチャは SVVS。MVVM の VM を二つに割って、業務状態（Store）と UI トランジエント（ViewState）を分けている。

分けた一番の動機は、シート開閉・スワイプ確定中の中間値・エラー表示みたいな「画面を閉じたら消えていい状態」が Store に染み出すのを止めたかったから。`isCapturing` / `errorMessage` / `activeSheet` は ViewState、`assets` / `capturedPhotos` / `selectedAssetID` は Store。View は ViewState だけ受け取って、Store には触らない。

パッケージは SwiftPM で 5 ターゲットに割って依存方向を強制している:

```
TottecoModels    (SwiftData モデル, DTO)
   └─ TottecoShared      (色定義, AppStorage キー, 共通 UI)
          └─ TottecoServices  (AVFoundation, CoreImage, VisionKit)
                 └─ TottecoFeatures  (Store / ViewState / 画面)
                        └─ TottecoCore      (公開は TottecoView だけ)
```

Share Extension は `TottecoModels` と `TottecoServices` だけ import し、UI レイヤには触らない。バイナリサイズと起動コストを抑えたい意図が主だが、結果として「本体だけで意味があるコードを Extension に持ち込まない」というレイヤリングのチェックポイントにもなった。

## 素材の取り込み

素材作成は VisionKit の `ImageAnalyzer` + `ImageAnalysisInteraction.subject(at:)`。背景タップで被写体マスクが取れるので、透過 PNG にして `FrameAsset` に保存する。

他アプリからの取り込みは Share Extension。`NSExtensionActivationSupportsImageWithMaxCount = 1` で 1 枚に限定して受ける。本体と Extension は App Group `group.com.shsw228.Totteco` を共有していて、`TottecoModelContainer.shared` を App Group コンテナで初期化しているので、Extension 側で `FrameAsset` を直接 insert すれば本体起動時にそのまま素材一覧に出る。

---

- 公式サイト: <https://totteco.pages.dev>
- App Store: <https://apps.apple.com/app/id6767696374>
