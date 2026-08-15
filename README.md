# Swanium Crystal

macOS 向け WonderSwan Crystal エミュレータです。WonderSwan / WonderSwan Color の ROM も後方互換として実行できます。実 BIOS と ROM は同梱せず、利用者が合法的に所有する `.ws` / `.wsc` ファイルだけを開きます。

Version 1.0.0 (build 1) は macOS 13.5 以降に対応します。CPU、映像・入力、音声、SRAM、セーブステート、デバッグ機能を備えます。正確な対応範囲と Rust 版 Swanium との差分は [機能対応表](docs/feature-compatibility.md) を参照してください。

## macOS で使う

リリースの `Swanium Crystal.app` を Applications などへ移動し、Finder から開きます。最初は ROM 未選択の画面が表示されるので、メニューバーの `Emulation` → `Open ROM…` から ROM を選びます。アドホック署名済みのローカルビルドは、そのまま Finder から起動できます。

キーボード操作は、矢印キーが X 方向パッド、WASD が Y 方向パッド、X/Z が A/B、Return が Start、Escape が終了です。F5/F9 は ROM ごとのステート保存・復元です。SDL2 対応ゲームパッドでは方向パッド、A/B、Start を使えます。

セーブ RAM は `~/Library/Application Support/swanium-crystal/saves` に、ROM 名ごとに保存されます。ROM、ハッシュ、セーブデータ、スクリーンショットはプロジェクトや CI へ送信しません。

## ビルドと検証

開発には [mise](https://mise.jdx.dev/) と Homebrew が必要です。次の手順は Crystal 1.18.2 と SDL2 を導入し、テスト済みの自己完結型 `.app` バンドルを作成します。

```sh
brew install mise sdl2 sdl3
mise run setup
mise run ci
mise run build
open "bin/Swanium Crystal.app"
```

バンドル内実行ファイルを使うと、ROM を直接指定したり、自動テスト用にヘッドレス起動したりできます。

```sh
"./bin/Swanium Crystal.app/Contents/MacOS/swanium-crystal" --version
"./bin/Swanium Crystal.app/Contents/MacOS/swanium-crystal" --rom /path/to/game.wsc
"./bin/Swanium Crystal.app/Contents/MacOS/swanium-crystal" --rom /path/to/game.wsc --headless-frames 900
```

`mise run ci` は整形チェック、ヘッドレス spec、自作カートリッジ fixture、SDL dummy video driver を使う起動確認を実行します。GUI の最小確認は `mise run sdl-smoke`、画面・入力・音声の手動確認は `mise run video-demo` です。公開テスト ROM を持っている場合だけ、`WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run public-roms` で追加検証できます。

## 開発資料

[開発計画](docs/development-plan.md)、[設計](docs/architecture.md)、[テスト](docs/testing.md)、[開発規約](docs/development.md)、[ライセンス方針](docs/licensing.md) を参照してください。

画面と入力の自作検証プログラムは次のコマンドで起動し、Escapeまたはウィンドウを閉じると終了します。

```sh
mise run video-demo
```

固定3倍（672×432）、60 Hz上限で表示します。矢印キーがX方向パッド、WASDがY方向パッド、Z/XがA/B、ReturnがStartです。SDL2対応ゲームパッドでは方向パッド、A/B、Startを利用できます。

デモでは約440 Hzの音声も再生します。F1でデバッグ表示、Spaceで一時停止・再開、Nで1命令実行、1/2/3で背景1・背景2・スプライト表示を切り替えます。Page Up / Page Downはメモリ表示位置、F5 / F9は0番スロットの保存・復元です。デバッグ表示にはSDL音声キューの推定遅延とアンダーラン回数も表示します。
