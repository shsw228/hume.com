---
title: ブログを Astro + AstroPaper で作り直した
description: 記事と実装のリポジトリを分けて、GitHub Pages に置き直した。
pubDate: 2026-05-27
tags: [Astro, AstroPaper, GitHub Pages]
draft: false
---

ブログを作り直した。前は Hugo を適当に立てて GitHub Pages に置いていたが、なんとなく触りづらくて放置していた。

きっかけは [r7kamura.com の構成記事](https://r7kamura.com/articles/2023-05-26-site-architecture-2023) を読み返したこと。記事と実装のリポジトリを分けて運用しているのを見て、自分もそうしたくなった。

## 構成

リポジトリは2つに分けた。

- `shsw228/hume.com` — 記事の Markdown だけ
- `shsw228/hume-press` — Astro のソース

記事を追加するときは `hume.com` を触り、見た目を直すときは `hume-press` を触る。気持ちが切り替わって書きやすい。

実装側は Astro 6 + [AstroPaper](https://astro-paper.pages.dev/) を被せた。Tailwind、ダークモード、タグ、アーカイブ、全文検索 (Pagefind)、動的 OG 画像生成までほぼ全部入っている。今回は素直にこれに乗ることにした。

## クロスリポジトリのビルド

GitHub Pages はリポジトリごとに配信できる。今回は `hume.com` リポジトリの Pages に配信して、URL を `https://shsw228.github.io/hume.com/` にしたかったので、配信のための Actions も `hume.com` 側に置いた。

ただし実装コードは `hume-press` 側にしかない。なので Actions のジョブで両方をチェックアウトしている。

```yaml
- uses: actions/checkout@v4
  with:
    path: hume.com

- uses: actions/checkout@v4
  with:
    repository: shsw228/hume-press
    path: hume-press
```

Astro 側の content collection は外部ディレクトリを参照するように loader の base を変えてある。

```ts
const BLOG_PATH = process.env.ARTICLES_DIR ?? "../hume.com/articles";
```

ローカルで2つを兄弟ディレクトリに並べていれば、同じパスで dev server も動く。CI とローカルで構成を揃えたかったので、submodule や API fetch ではなくこの方式を選んだ。

逆方向、つまり実装側を直したときに記事側のビルドを走らせたいケースは `repository_dispatch` で繋いだ。`hume-press` の workflow が `hume.com` にイベントを投げる。

## 旧記事との互換

Hugo の頃の frontmatter は `pubDate` を使っていたが、AstroPaper の標準スキーマは `pubDatetime`。記事を全部直すのは面倒だったので、content collection 側で preprocess を挟んで吸収した。

```ts
z.preprocess((raw) => {
  if (raw?.pubDate && !raw.pubDatetime) raw.pubDatetime = raw.pubDate;
  if (raw?.updatedDate && !raw.modDatetime) raw.modDatetime = raw.updatedDate;
  return raw;
}, z.object({ ... }))
```

新しく書く記事は普通に `pubDatetime` を使えばよく、古いやつは触らないで済む。

## ハマったこと

- **base path**: GitHub Pages はリポジトリ名のサブパスで配信するので、`base: '/hume.com/'` を Astro に教える必要がある。これを忘れると CSS と内部リンクが全部 404 になった。
- **astro check が通らない**: AstroPaper の依存を入れると vite が 8 系に上がる。Astro 6 は vite 7 を期待しているので、`vite@^7.3.2` で固定するまで型エラーで落ちていた。
- **dev でも draft が見えない**: AstroPaper の `postFilter` はデフォルトで draft 記事を常に弾く。レビュー前のローカル確認をしたかったので、`import.meta.env.DEV` のときだけ全部見えるように一行足した。

## 今のところ

「気が向いたら書く」場所のハードルが下がった気がしている。Hugo の頃よりも自分で書いた箇所が少ないのに、いじりたくなったら触れる余地は残してある。しばらくこの構成で寝かせてみる。
