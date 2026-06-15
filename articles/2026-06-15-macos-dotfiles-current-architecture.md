---
title: chezmoi + yashiki + sketchybar で組む macOS dotfiles
description: 個人 / 会社 PC を同じソースで運用する dotfiles の現状を、chezmoi の構成・タイル WM とバーの連携・notch まわりの工夫を中心にまとめた。
pubDate: 2026-06-15
tags: [macOS, dotfiles, chezmoi, sketchybar]
draft: false
---

macOS の dotfiles を chezmoi で管理している。ここ最近で固まってきた構成について、自分用の備忘録も兼ねて書き残しておく。

設計の方針はざっくり三つ:

- 個人 PC と会社 PC を同じソースで回す
- タイル WM とバーをイベント駆動で連動させる
- 新マシンでも `chezmoi apply` 一発で常駐物まで起き上がる

以下、それぞれの実装と、書きながら気になった細かい挙動について。

## 構成の全体像

リポジトリは ghq 配下に置いていて、レイアウトはこんな感じ:

```
dotfiles/
├── .chezmoiroot                 # → "chezmoi" を指す
└── chezmoi/
    ├── .chezmoi.toml.tmpl       # プロファイル分岐 (個人 / 会社)
    ├── Brewfile
    ├── Brewfile.personal.example # テンプレ。実体 Brewfile.personal は .gitignore
    ├── run_once_*.sh.tmpl       # 初回だけ走るブートストラップ
    ├── run_onchange_*.sh.tmpl   # ソース変更時に再実行
    ├── run_11_manage-homebrew-unmanaged.sh.tmpl
    ├── dot_config/...
    └── dot_zshrc, dot_zshenv, dot_zprofile
```

リポジトリ直下に `.chezmoiroot` を置いて、その中身で `chezmoi` を指している。chezmoi がソースとして読むのは `chezmoi/` 配下だけになるので、`README.md` や `.github/` をリポジトリのトップに普通に並べられて見通しがいい。

デスクトップ側は yashiki (タイル WM) + sketchybar (Lua で組んだバー) + JankyBorders (フォーカス枠) の三本立て。これらを `run_onchange_*` 経由でインストールから常駐起動までまとめてやる構成にしている。

![yashiki でタイル配置したウィンドウと sketchybar の見た目](https://i.imgur.com/sqcUAj5.png)

## chezmoi の運用

chezmoi 自体の使い方で工夫している点をまとめる。

### sourceDir を ghq 配下に固定する

chezmoi はデフォルトだと `~/.local/share/chezmoi` にソースを置きにいくが、自分の場合は ghq で取ってきたリポジトリをそのままソースとして使いたい。`chezmoi/.chezmoi.toml.tmpl` の冒頭でこう書き換えている:

```toml
{{- if not (env "CHEZMOI_CI") -}}
{{-   $ghqRoot := env "GHQ_ROOT" -}}
{{-   if and (eq $ghqRoot "") (lookPath "ghq") -}}
{{-     $ghqRoot = output "ghq" "root" | trim -}}
{{-   end -}}
{{-   if ne $ghqRoot "" }}
sourceDir = "{{ $ghqRoot }}/github.com/shsw228/dotfiles"
{{   end -}}
{{- end -}}
```

`ghq root` の出力を読んで sourceDir に流し込む形。これで `chezmoi init` の後はソースが `~/Developer/ghq/.../dotfiles` 固定になり、デフォルト位置と二重管理になる事故が起きない。CI では `CHEZMOI_CI=1` を見て分岐ごとスキップしている。

### 個人 / 会社プロファイルの分岐

`.chezmoi.toml.tmpl` の後半で `is_personal_pc` を判定して、git の identity を出し分ける。

```toml
{{- $isPersonalPC = promptBoolOnce . "is_personal_pc" "このPCは個人用ですか？" true -}}

[data.profile]
is_personal_pc = {{ $isPersonalPC }}

{{- if $isPersonalPC }}
[data.git]
name = "hume"
email = "..."
{{ else }}
[data.git]
name = {{ $gitName | quote }}
email = {{ $gitEmail | quote }}
{{- end }}
```

非対話な環境（`CHEZMOI_IS_PERSONAL_PC` や `GIT_NAME` / `GIT_EMAIL` を env で渡しているケース）でも通るよう、まず env を確認してから `promptBoolOnce` / `promptStringOnce` に落ちる。`promptOnce` 系は `chezmoi init` のときに一度だけ訊いて値を永続化してくれるので、以降の apply で毎回ブロックされない。これは大事で、CI でも使いやすい。

### Brewfile.personal はローカル専用にする

discord、kicad、altserver みたいに会社 PC では入れたくないものは `Brewfile.personal` に分けている。ただ、このリストはマシンごとに違うし、そもそも個人の趣味なのでリポジトリには残したくない。なので運用はこうしてある:

- `Brewfile.personal.example` だけ git にコミットしておく
- 実体の `Brewfile.personal` は `.gitignore` で除外、各マシンでローカルに作る
- インストールスクリプトは `Brewfile.personal` が **存在すれば** 結合する

```sh
# run_onchange_10_install-homebrew-packages.sh.tmpl 抜粋
cat >"$tmp_brewfile" <<'EOF_BREWFILE'
{{ include "Brewfile" }}
EOF_BREWFILE

source_dir="{{ .chezmoi.sourceDir }}"
personal_brewfile="$source_dir/Brewfile.personal"
if [ "{{ if dig "profile" "is_personal_pc" true . }}1{{ else }}0{{ end }}" = "1" ] \
   && [ "${CHEZMOI_CI:-0}" != "1" ] \
   && [ -f "$personal_brewfile" ]; then
  cat "$personal_brewfile" >>"$tmp_brewfile"
fi
```

新マシンに入ったら `cp chezmoi/Brewfile.personal.example chezmoi/Brewfile.personal` で実体を作り、必要に応じて中身を編集する。会社 PC や `Brewfile.personal` を置いていないマシンでは `Brewfile` だけが効くので、何もしなくても何も起きない。

### Homebrew 6.0 の tap trust 対応

Homebrew 5.1.15 以降、third-party tap はそのままでは `brew bundle` で使えなくなった。明示的に `brew trust` しないと load を拒否される。新マシンの初回 apply や CI でいきなりコケるので、Brewfile から `tap "..."` を抜き出して先に `tap → trust` を回すようにしている:

```sh
if "$brew_cmd" trust --help >/dev/null 2>&1; then
  awk -F'"' '/^[[:space:]]*tap[[:space:]]+"/ {print $2}' "$tmp_brewfile" |
  while IFS= read -r tap_name; do
    case "$tap_name" in
      homebrew/*) continue ;;
    esac
    if ! "$brew_cmd" tap | grep -qx "$tap_name"; then
      "$brew_cmd" tap "$tap_name"
    fi
    "$brew_cmd" trust "$tap_name" >/dev/null 2>&1 || true
  done
fi

"$brew_cmd" bundle --file="$tmp_brewfile"
```

`brew trust --help` で機能の有無を確認してから走らせる形なので、`trust` がまだ無い古めの Homebrew でも普通に通る。

### unmanaged パッケージの対話レビュー

Brewfile に書いていないけど手元には入っている、というパッケージは時間が経つと地味に溜まる。これを apply のタイミングで対話的に整理できるようにしているのが `run_11_manage-homebrew-unmanaged.sh.tmpl`。

それぞれの unmanaged 項目について、こんな三択が出る:

- `[d] uninstall` — `brew uninstall` する
- `[l] move to Brewfile.personal` — `Brewfile.personal` に追記する
- `[s] skip` — 何もしない（次回また訊かれる）

依存だけのパッケージ（`brew leaves` に出ないもの）は自動でスキップ、`Brewfile.personal` で既に管理されているものも除外、というフィルタを噛ませてあるので、本当に判断が必要なものだけが残る。Brewfile を真として強制的に sync するスタンスではなく、ずれを毎回確認しつつ収束させる、というやり方を選んでいる。

## デスクトップ環境 (yashiki + sketchybar)

ウィンドウマネージャは [`typester/yashiki`](https://github.com/typester/yashiki)、メニューバーは [`FelixKratz/SketchyBar`](https://github.com/FelixKratz/SketchyBar) を SbarLua 経由で Lua から組んでいる。両者は完全に別プロセスとして動くので、ワークスペースの状態などを同期させる仕組みは自前で用意する必要がある。

### yashiki のタグベース構成

yashiki の workspace は bitmask のタグ。`tag-view` で表示、`window-move-to-tag` で移動、`window-toggle-tag` で複数所属させる、という API になっていて、AeroSpace 風のキーバインドはほぼそのまま再現できる。app-id ベースで初期所属タグや出力先も指定できる:

```sh
# Browser → tag 1
yashiki rule-add --app-id com.google.Chrome tags 1
# Terminal → tag 2
yashiki rule-add --app-id com.mitchellh.ghostty tags 2
# Music → tag 10、外部モニタがあれば本体側に置く
yashiki rule-add --app-id com.apple.Music tags 512
yashiki rule-add --app-id com.apple.Music output "Built-in"
```

System Settings の補助 popup みたいな小さい window が勝手に tile されるとうざいので、`--window-level other` と `--close-button none` で ignore ルールを入れている。これだけで System Settings 系の事故はほぼ無くなった。

### sketchybar を Lua で書く

SketchyBar 自体は `sketchybarrc` をシェルとして読むが、自分は SbarLua 経由で Lua から組み立てている。`init.lua` はこれだけ:

```lua
local sbar = require("sketchybar")
sbar.begin_config()
require("bar")
require("default")
require("items")
sbar.hotload(true)
sbar.end_config()
sbar.event_loop()
```

`items/*.lua` がウィジェット（battery, wifi, audio, system, media, yashiki tag indicator …）をそれぞれ担当する。シェルだとどうしても文字列の組み立てで複雑になりがちだが、Lua にすると後述する display 判定や notch_spacer の幅計算をそのままコードで書けるのが助かる。

### yashiki ↔ sketchybar の連動

yashiki が JSON で吐く state stream を bridge スクリプトで購読し、sketchybar の `--trigger` イベントに変換する形にしている。両プロセスが互いを直接知らないまま状態を共有できる。

#### state stream ブリッジ

`sketchybar/plugins/yashiki_bridge.sh` を常駐させて、`yashiki subscribe --snapshot --filter tags,focus,window,mode` を購読する。受け取ったイベントに応じて sketchybar 側でカスタムイベントを叩く:

```
yashiki_workspace_change  OUTPUT_{id}_ACTIVE_TAGS=...
                          OUTPUT_{id}_OCCUPIED_TAGS=...
                          OUTPUT_{id}_TAG_APPS_{1..10}=app1,app2,...
yashiki_focus_change      FLOAT=true|false
yashiki_mode_change       MODE=resize
```

`OUTPUT_{id}_TAG_APPS_n` は出力ごと・タグごとに「いま開いてるアプリの bundle id 一覧」を CSV で渡す。受け側の `items/yashiki.lua` では `icons.lua` の `app[bundle_id] → SF Symbols glyph` テーブルでアイコンに変換する:

```lua
icons.app = {
  ["com.google.Chrome"]     = "􀆪",
  ["com.mitchellh.ghostty"] = "􀩼",
  ["com.apple.dt.Xcode"]    = "󰣦",
  ["com.openai.codex"]      = "􀇻",
  default                   = "􀀁",
}
```

bundle id ベースでマップしておくと、Chrome / Helium / Arc みたいに同系統のブラウザを別エントリにできるし、未知のアプリも `default` に落ちるだけで死なない。ここはアプリを増やすたびに増やしていけば良い。

#### focus に応じた border 切替

[FelixKratz/JankyBorders](https://github.com/FelixKratz/JankyBorders) は yashiki から `exec --track` で起動している。`--track` 付きなので、yashiki が落ちると borders も一緒に止まる。

bridge では `yashiki_focus_change` の `FLOAT` 引数を見て、floating window のときだけ border をオレンジに振る:

```sh
update_borders() {
  local floating="$1"
  if [ "$floating" = "true" ]; then
    "$BORDERS" active_color=0xfff5a97f ...
  else
    "$BORDERS" active_color=0xffe1e3e4 ...
  fi
}
```

タイルされていない window が色で区別できるので、`alt-h/j/k/l` でフォーカス移動しようとして「あれ、効かない」と一瞬迷うことが無くなる。

#### ディスプレイ抜き差しでの自動 reload

per-display のウィジェット構成（後述）を動的に組んでいる関係で、ディスプレイの抜き差し後は items を一回作り直さないと整合しない。これを自動でやるために、`display_watcher.sh` を `init.lua` から起動して yashiki の display イベントを購読している:

```sh
"$YASHIKI" subscribe --filter display | while IFS= read -r line; do
  type=$(echo "$line" | jq -r '.type')
  case "$type" in
    display_added|display_removed)
      pkill -9 sketchybar
      exit 0
      ;;
  esac
done
```

`pkill -9` で sketchybar 自体を落とすと、`brew services` で動いている launchd の `KeepAlive` が即座に再起動してくれる。再起動した init.lua は新しい display 構成を見て items を組み直す、という流れ。`display_updated` は解像度や位置変更のたびにも飛んでくるので、誤再起動を避けて拾わない。

### macOS 固有の制約への対応

macOS だからこそ必要だった、画面まわりの細かい対応をいくつか。

#### notch の物理幅を機種から決め打つ

MacBook Pro 14"/16" や M2 以降の Air は画面上中央に notch がある。普通に items を中央配置すると notch を跨いで分断されるので、`items/notch_spacer.lua` で `system_profiler` の Model Identifier から notch 幅を返し、中央に透明スペーサーを置いて左右に items を振り分けている:

```lua
local function detect_notch_width()
  -- system_profiler SPHardwareDataType の Model Identifier
  if model:match("^MacBookPro18,[34]")
    or model:match("^Mac1[456]") then
    return 220   -- 14"/16" 系 + M2 以降の notch 機
  end
  return 0
end
```

#### 中央配置を本当に中央にする balance

date と clock を中央エリアに並べているのだが、自然幅が等しくないので（例: `9:09` と `11:34` で違う）、notch_spacer の中心が display 中心からずれる。これを補正するのが `notch_balance.lua` で、`date` と `clock` の実描画幅を `sketchybar --query` で取って、左右の差ぶんだけ透明アイテムを足す。clock の幅は分単位で変わるので、30 秒ごとの routine で再計算している。

#### per-display ウィジェット切り替え

外部モニタには CPU/RAM までフル情報を出したいが、Built-in 側はバッテリーと notch 制約があるので情報量を絞りたい。`displays.lua` で `yashiki list-outputs` を読み、`builtin_index` / `external_indices` を判別したうえで、items 側で `associated_display` を切り替える:

```lua
local ext = displays.external_indices[1]
if ext then
  sbar.add("bracket", "right_bracket_external", {
    "media", "system", "audio", "input_source", "wifi", "battery",
  }, { background = styles.bracket_bg, associated_display = ext })
end
if displays.builtin_index then
  -- MacBook 側: CPU/RAM 抜き、audio/media は minimum item
  sbar.add("bracket", "right_bracket_builtin", {
    "media_simple", "audio_simple", "input_source", "wifi", "battery",
  }, { background = styles.bracket_bg, associated_display = displays.builtin_index })
end
```

`media` / `audio` には minimum 版 (`_simple`) を別アイテムとして用意してあって、Built-in 側はそちらが使われる。

### 視覚の整合

#### styles.lua で背景定義を集約する

bracket や popup の背景定義が散らかってきたので、`styles.lua` を共有モジュールに切り出した:

```lua
M.glass = {
  blur_radius = 10,
  background = {
    color = 0x6a282a36,
    border_color = 0x48ffffff,
    border_width = 1,
    corner_radius = 8,
  },
}

M.bracket_bg = {
  color = 0x99000000,
  corner_radius = 8,
  height = 28,
  border_width = 0,
}
```

色味や blur 量を変えたくなったらここを触るだけで、bracket と popup の両方に伝播する。

#### Liquid Glass 風 popup と blur_radius の指定箇所

SketchyBar の `blur_radius` は **`background` のプロパティではない**。item / bracket のトップレベル、popup の場合は `popup.blur_radius` に直接置く必要がある。`popup.background.blur_radius` でも、`background.blur_radius` でもない。間違えた場所に書くと `[!] Background: Invalid property 'blur_radius'` とだけ言われて他は普通に動くので、なんで効かないんだろうと一瞬考えることになる。

正しくはこう:

```lua
popup = {
  align = "center",
  blur_radius = styles.glass.blur_radius,
  background = styles.glass.background,
  y_offset = 6,
},
```

これで yashiki の resize mode (`alt-r`) で出るチートシート popup などが、Liquid Glass 寄りの半透明ダーク + うすい白ボーダーで描かれるようになる。

#### bar margin と outer-gap を 4px グリッドで揃える

`bar.margin` は画面端から sketchybar 描画領域までの距離、`bar.padding_left/right` は描画領域の中で items が始まる位置。両方を指定すると bracket の可視端は `margin + padding` 分だけ画面端から離れるので、yashiki の `outer-gap` で揃えたウィンドウ端とは一致しなくなる。

ぴったり揃えたいなら `padding_left/right = 0` にして margin だけで位置を決め、items 間のスペースは個別アイテムの `padding_*` に任せる:

```lua
sbar.bar({
  height        = 32,
  margin        = 12,   -- 画面端からの距離 = yashiki outer-gap 左右と同じ値
  y_offset      = 8,    -- 上端からの距離
  corner_radius = 10,
  notch_width   = 220,
  padding_left  = 0,    -- 加算しない。margin だけで揃える
  padding_right = 0,
})
```

実測すると bracket の右端と window の右端が同じ x 座標に並ぶ。`y_offset = 8`、yashiki `outer-gap top = 48`（= 8 + 32 + 8）と、すべて 4px の倍数にまとめておくと、上下左右の余白の感じも揃って気持ちよくなる。

## 常駐プロセスの起動まで chezmoi で完結させる

新マシンで `chezmoi apply` を打ったあと、login items の登録や sketchybar の起動まで手で操作したくない。OS 標準の仕組み（launchd / login item / brew services）を `run_onchange_*` 経由で冪等に叩く形で組んでいる。

### login items と brew services の冪等な登録

`run_onchange_30_configure-login-items.sh.tmpl` で AppleScript と `brew services` を順番に呼ぶ:

```sh
osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "System Events"
  if not (exists login item "Raycast") then
    make new login item at end with properties \
      {name:"Raycast", path:"/Applications/Raycast.app", hidden:false}
  end if
  if not (exists login item "Yashiki") then
    make new login item at end with properties \
      {name:"Yashiki", path:"/Applications/Yashiki.app", hidden:true}
  end if
end tell
APPLESCRIPT

# sketchybar は formula なので brew services 経由で常駐
if "$brew_cmd" list --formula sketchybar >/dev/null 2>&1; then
  if ! "$brew_cmd" services list |
       awk '$1 == "sketchybar" {print $2}' | grep -qx "started"; then
    "$brew_cmd" services start sketchybar >/dev/null 2>&1 || true
  fi
fi
```

AppleScript は `if not (exists login item "...")` で既に登録済みなら何もしないようにしてあるし、sketchybar 側も `brew services list` を見て既に started なら触らない。何回叩いても問題ない。

### SSH agent socket を GUI まで届ける

1Password の SSH agent は CLI から `SSH_AUTH_SOCK=~/.1password-agent.sock` で見える。ただ Fork みたいな libssh2 系の GUI クライアントは launchd の env を読みにいくので、シェル側の env だけ仕込んでもそこまで届かない。

これを解決するために、`run_onchange_50_set-ssh-auth-sock.sh.tmpl` で LaunchAgent plist を `~/Library/LaunchAgents/com.shsw228.ssh-auth-sock.plist` に置き、`launchctl setenv SSH_AUTH_SOCK ~/.1password-agent.sock` を仕込んでいる:

```xml
<key>ProgramArguments</key>
<array>
  <string>/bin/launchctl</string>
  <string>setenv</string>
  <string>SSH_AUTH_SOCK</string>
  <string>${HOME}/.1password-agent.sock</string>
</array>
<key>RunAtLoad</key>
<true/>
```

これで再起動後も GUI 経由の git push / pull がそのまま 1Password の Touch ID を通る。一度仕込んでしまえばあとは何もしなくていい。

## まとめ

今回取り上げた工夫:

- `.chezmoiroot` + ghq 配下を sourceDir に固定して「リポジトリは ghq」「ソースは `chezmoi/`」を両立
- `Brewfile` + ローカル専用の `Brewfile.personal`（テンプレを `.example` で残す）で PC ごとの差を吸収
- Homebrew 6.0 の tap trust を bootstrap で先回り
- yashiki + sketchybar を JSON state stream + `sketchybar --trigger` で疎結合に連携
- ディスプレイ抜き差し検知 → `pkill -9` + launchd の `KeepAlive` で auto reload
- 機種判定 + 動的幅計算で notch を確実に避ける
- `styles.lua` で bracket / popup の glass 風背景を一元化
- `bar.padding = 0` + `margin = outer-gap` で window とバーを 4px グリッドに揃える
- LaunchAgent plist で `SSH_AUTH_SOCK` を GUI まで届ける

特に最後の「常駐プロセスのインストール・起動まで `chezmoi apply` で完結させる」は、新マシンや work / personal を行き来するときの手数がほぼ無くなって、入れてよかったと思っているところ。
