---
title: iOS 開発/本番環境の分離
description: Xcode の Build Configuration を使って、開発版と本番版を同一デバイスに共存させるための設定をまとめた。
pubDate: 2026-05-27
tags: [iOS, Xcode]
draft: true
---

開発中のビルドと App Store に出している本番ビルドを、同じ iPhone に同時にインストールできるようにしたい。Xcode の Build Configuration（Debug/Release）を軸に、何をどこで分離するかを整理する。

## 分離すべき項目

| 項目 | 理由 |
|------|------|
| Bundle ID | 共存のため必須。別アプリとして認識される |
| 表示名 | 見分けやすくする（例: `[D]AppName`） |
| App Group | データを分離する場合 |
| URL Scheme | ディープリンクの衝突を防ぐ |
| Info.plist | URL Scheme などを構成ごとに変える場合 |
| Entitlements | App Group などを構成ごとに変える場合 |

## 設定方法

### 1. プロジェクト設定で基本値を定義

Xcode > Project > Build Settings で、構成ごとに値を設定する。

```
// Debug
PRODUCT_BUNDLE_IDENTIFIER = com.example.app.dev

// Release
PRODUCT_BUNDLE_IDENTIFIER = com.example.app
```

### 2. ターゲット設定で継承

ターゲットの Build Settings では `$(inherited)` で継承する。

```
PRODUCT_BUNDLE_IDENTIFIER = $(inherited)
PRODUCT_NAME = D-$(TARGET_NAME)                       // Debug のみ
INFOPLIST_KEY_CFBundleDisplayName = [D]$(inherited)   // Debug のみ
```

### 3. 構成ごとのファイル

Info.plist や Entitlements を分ける場合、ファイル自体を構成ごとに用意する。

```
App/
├── Info.plist           # Release
├── Info.dev.plist       # Debug
├── App.entitlements     # Release
└── App.dev.entitlements # Debug
```

ターゲット Build Settings で構成ごとに切り替える。

```
// Debug
INFOPLIST_FILE = App/Info.dev.plist
CODE_SIGN_ENTITLEMENTS = App/App.dev.entitlements

// Release
INFOPLIST_FILE = App/Info.plist
CODE_SIGN_ENTITLEMENTS = App/App.entitlements
```

### 4. コード内での分岐

```swift
#if DEBUG
let urlScheme = "myapp-dev"
#else
let urlScheme = "myapp"
#endif
```

## App Extension の扱い

WidgetExtension などは親アプリと同様に分離する。

```
// Extension の Bundle ID
PRODUCT_BUNDLE_IDENTIFIER = $(inherited).WidgetExtension
// → Debug:   com.example.app.dev.WidgetExtension
// → Release: com.example.app.WidgetExtension
```

ただし Extension の `PRODUCT_NAME` は構成で変えない方が無難。Embed フェーズでの参照が複雑になる。

## xcconfig を使う場合

Build Settings に直書きするより保守しやすい。

```
// Config/Debug.xcconfig
PRODUCT_BUNDLE_IDENTIFIER = com.example.app.dev
APP_DISPLAY_NAME = [D]MyApp
APP_GROUP = group.com.example.dev

// Config/Release.xcconfig
PRODUCT_BUNDLE_IDENTIFIER = com.example.app
APP_DISPLAY_NAME = MyApp
APP_GROUP = group.com.example.app
```

Project > Info > Configurations で xcconfig を指定する。

## 注意点

- **PBXFileReference**: `project.pbxproj` 内のプロダクト参照名は変えない（Xcode が管理する領域）。
- **絶対パス**: `project.pbxproj` に絶対パスが混入しないよう注意。
- **App Group**: 分離するとデータは共有されない。同じデータを使いたいケースだけ意識的に揃える。
- **Push 通知**: Bundle ID ごとに証明書が必要。
- **App Store Connect**: 開発版は TestFlight 用、本番版はストア用として別管理になる。
