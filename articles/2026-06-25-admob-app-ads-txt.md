---
title: app-ads.txt を Cloudflare Pages の pages.dev で通す
description: AdMob の app-ads.txt 警告を、独自ドメインなし・Cloudflare Pages の *.pages.dev サブドメインだけで解消した。引っかかった箇所を残しておく。
pubDate: 2026-06-25
tags: [iOS, AdMob, Cloudflare]
draft: false
---

AdMob を入れている iOS アプリ Totteco で、管理画面に「app-ads.txt が見つかりません」の警告が出ていた。独自ドメインは持っておらず、アプリ紹介サイトは Cloudflare Pages の `totteco.pages.dev` に置いている。この `*.pages.dev` だけで app-ads.txt を通せるのか、というのが今回の話。結論は通せた。引っかかった箇所を残しておく。

## app-ads.txt はどこを見られるか

[app-ads.txt](https://support.google.com/admob/answer/9363762) は広告枠の正規の販売者を宣言して不正在庫を防ぐ仕組みで、設置しないと配信・収益が制限されることがある。

クローラがファイルを探す起点は、**公開中の App Store リスティングに載っているデベロッパー Web サイト URL** のドメイン。そのドメインの**ルート直下**（`https://example.com/app-ads.txt`）を見に行く。サブパスやランダムなサブドメインは見ない。

ここで疑問になるのが、`totteco.pages.dev` のような共有サブドメインを「ルートドメイン」として扱ってくれるのか、という点。

## pages.dev は Public Suffix List に載っている

IAB の app-ads.txt 仕様では、ルートドメインの判定に [Public Suffix List](https://publicsuffix.org/)（PSL）を使う。`pages.dev` は Cloudflare が PSL に登録しているので、**`totteco.pages.dev` 自体が登録可能ドメイン（eTLD+1）として扱われる**。

仕様上、複数パートの公開サフィックスでは「公開サフィックスの直前のサブドメイン 1 つ」をルートとしてクロールする。`pages.dev` が公開サフィックスなので、デベロッパー URL が `https://totteco.pages.dev` なら、クローラは:

```
https://totteco.pages.dev/app-ads.txt
```

を見に来る。つまり独自ドメインを買わなくても、`*.pages.dev` のルートに置けば成立する。`www.` / `m.` はクローラの探索対象から除外される点だけ注意（`totteco.` は該当しないので問題ない）。

## Astro なら public/ に置くだけ

サイトは Astro。`public/` 配下はビルドで `dist/` のルートにそのままコピーされるので、置き場所は次の 1 箇所:

```
web/public/app-ads.txt
```

中身は AdMob 管理画面の「アプリ → app-ads.txt」に出るコピペ用の行。1 ネットワーク（AdMob のみ）ならこれだけ:

```
google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
```

- `pub-XXXX...` は自分のパブリッシャー ID。`Info.plist` の `GADApplicationIdentifier`（`ca-app-pub-XXXX~YYYY`）の `~` の前の数字部分がそれにあたる
- `f08c47fec0942fa0` は Google の認証局 ID（固定値）
- メディエーションや他ネットワークを使っているなら、各社の行も追記する

## SPA フォールバックに飲まれていないか確認する

ハマりやすいのがこれ。サイトが SPA 的なフォールバック（存在しないパスを index.html で返す）を持っていると、`/app-ads.txt` がテキストではなく HTML を返してしまい、クローラは「app-ads.txt ではない」と判断して失敗する。

静的アセットは普通フォールバックより優先されるので、置けば直る話ではあるが、**配信結果は必ず実際の HTTP レスポンスで確認する**のが確実。`Content-Type: text/plain` で中身が返ればOK:

```sh
$ curl -sIL https://totteco.pages.dev/app-ads.txt | grep -i content-type
content-type: text/plain; charset=utf-8

$ curl -sL https://totteco.pages.dev/app-ads.txt
google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
```

ブラウザで開いて中身が見えても、`Content-Type` が `text/html` だと弾かれることがあるので、ヘッダまで見ておく。

## クロールは即時ではない

ファイルが正しく配信されていても、AdMob 側のクロールはすぐには走らない。確認したのは次の条件:

- App Store Connect のマーケティング URL が `https://totteco.pages.dev` になっている
- AdMob のアプリが、その App Store のアプリ ID と**リンク済み**である（手動作成アプリのままだとストアの URL を辿れない）
- アプリが**公開済み**である（未公開だと参照する公開ストアページが無く、クロール先が定まらない）

この 3 つが揃っていれば、あとは待ち。管理画面から再クロールをリクエストできるが、反映は最大 24 時間〜数日かかる。今回は条件を満たした状態で待ったらステータスが「承認済み」に変わった。

## まとめ

- `*.pages.dev` は PSL に載っているので、独自ドメインなしでも app-ads.txt を通せる
- Astro なら `public/app-ads.txt` を置くだけ、配信は `Content-Type: text/plain` で確認する
- クロールはストアのデベロッパー URL 起点。リンク済み・公開済みを揃えて待つ
