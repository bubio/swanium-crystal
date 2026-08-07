# Swanium Crystal

WonderSwan 系ハードウェアを Crystal で再実装する、ヘッドレステスト可能なエミュレータプロジェクトです。CPU、Mono / Color / Crystal映像・入力、音声、セーブステート、デバッグ基盤まで実装しています。

```sh
mise run setup
mise run ci
mise run build
./bin/swanium-crystal --version
```

`mise run build` は最適化済みのリリースビルドを生成します。遅い場合は、以前の通常ビルドではなくこのコマンドを実行してから起動してください。

SDL2 の導入確認には、デスクトップ環境で `mise run sdl-smoke` を実行します。通常 CI は自作 fixture だけを使います。公開テスト ROM はローカルで `WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run public-roms` として opt-in 検証でき、ROM 本体はリポジトリや CI に含めません。詳細は [開発計画](docs/development-plan.md)、[設計](docs/architecture.md)、[テスト](docs/testing.md)、[開発規約](docs/development.md)、[ライセンス方針](docs/licensing.md) を参照してください。

利用者が合法的に用意した `.ws` / `.wsc` は、明示指定で起動できます。ROM は収集・配布せず、SRAM セーブは macOS の `Application Support/swanium-crystal/saves` に ROM ファイル名ごとに保存します。

```sh
./bin/swanium-crystal --rom /path/to/game.wsc
```

Escape で終了します。矢印キーがX方向パッド、WASDがY方向パッド、Z/XがA/B、ReturnがStartです。F5/F9はROMごとのステート保存・復元です。`--headless-frames COUNT` を付けると画面を開かずに起動後の実行を確認できます。

画面と入力の自作検証プログラムは次のコマンドで起動し、Escapeまたはウィンドウを閉じると終了します。

```sh
mise run video-demo
```

固定3倍（672×432）、60 Hz上限で表示します。矢印キーがX方向パッド、WASDがY方向パッド、Z/XがA/B、ReturnがStartです。SDL2対応ゲームパッドでは方向パッド、A/B、Startを利用できます。

デモでは約440 Hzの音声も再生します。F1でデバッグ表示、Spaceで一時停止・再開、Nで1命令実行、1/2/3で背景1・背景2・スプライト表示を切り替えます。Page Up / Page Downはメモリ表示位置、F5 / F9は0番スロットの保存・復元です。デバッグ表示にはSDL音声キューの推定遅延とアンダーラン回数も表示します。
