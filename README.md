# hume.com

技術ブログ（`https://shsw228.github.io/hume.com/`）の記事原稿リポジトリ兼配信元。実装は [shsw228/hume-press](https://github.com/shsw228/hume-press) にある。

## 運用

- `articles/` に Markdown を配置する。ファイル名は `YYYY-MM-DD-slug.md`。
- `main` への push で `deploy.yml` が走り、hume-press を checkout してビルド、GitHub Pages へ配信する。
- 実装側（hume-press）の更新時は hume-press の `dispatch.yml` が `repository_dispatch` を本リポジトリに投げて再ビルドをキックする。

## frontmatter スキーマ

```yaml
---
title: 記事タイトル
description: 一覧やOGPに使う短い説明
pubDate: 2026-05-27
updatedDate: 2026-05-28   # 任意
tags: [Rust, 競プロ]
draft: false              # true のあいだは公開されない
---
```

## リポジトリ設定

- Settings → Pages → Source を **GitHub Actions** に設定する。

## 必要なシークレット

なし（`GITHUB_TOKEN` で配信完結）。実装側 hume-press が本リポジトリにディスパッチを投げる際の PAT は hume-press 側のシークレット。
