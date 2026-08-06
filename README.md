# Swanium Crystal

WonderSwan 系ハードウェアを Crystal で再実装する、ヘッドレステスト可能なエミュレータプロジェクトです。CPUの最小実行系と、Mono / Color / Crystalの映像・入力基盤まで実装しています。

```sh
mise run setup
mise run ci
mise run build
./bin/swanium-crystal --version
```

SDL2 の導入確認には、デスクトップ環境で `mise run sdl-smoke` を実行します。実 ROM、BIOS、商用ゲームデータは扱いません。詳細は [開発計画](docs/development-plan.md)、[設計](docs/architecture.md)、[テスト](docs/testing.md)、[開発規約](docs/development.md)、[ライセンス方針](docs/licensing.md) を参照してください。

画面と入力の自作検証プログラムは次のコマンドで起動し、Escapeまたはウィンドウを閉じると終了します。

```sh
mise run video-demo
```

固定3倍（672×432）、60 Hz上限で表示します。矢印キーがX方向パッド、WASDがY方向パッド、Z/XがA/B、ReturnがStartです。SDL2対応ゲームパッドでは方向パッド、A/B、Startを利用できます。
