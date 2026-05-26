# hume.com

技術ブログの記事原稿リポジトリ。実装は [shsw228/hume-press](https://github.com/shsw228/hume-press) にある。

## 運用

- `articles/` に Markdown を配置する。ファイル名は `YYYY-MM-DD-slug.md`。
- `main` への push で実装リポジトリに `repository_dispatch` を投げ、ビルドとデプロイがトリガーされる。

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
