# テスト

通常の CI 検証は、リポジトリに含まれる自作 fixture だけで次の一コマンドを実行する。

```sh
mise run ci
```

これは整形チェック、画面fixtureを含む `crystal spec`、ビルド、自作カートリッジを使うCLIの900フレーム実行、SDL2 dummyビデオドライバの起動を実行する。`mise run build` はCLIを `bin/swanium-crystal` に生成する。SDL2の最小確認はGUIセッションで `mise run sdl-smoke`、画面・入力・60 Hz提示の確認は `mise run video-demo` を使う。

PPU specは単色2bpp、Color / Crystalのplanar・packed 4bpp、スプライト、パレット、RGB444→RGBA8888変換を検証する。さらに、自作パターンの129,024バイトのRGBA画像を `spec/fixtures/video_test_pattern.rgba.zlib.base64` の圧縮済み期待画像と完全比較する。1バイトでも異なればCIを失敗させ、最初の差分位置を報告する。期待画像は仕様変更をレビューした場合だけ更新する。

公開テスト ROM はリポジトリに含めず、通常の CI もこれを読み込まない。公開 ROM の opt-in 検証は、ローカルで必要な環境変数を設定して `mise run public-roms` を実行する。現在は `WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run public-roms` に対応し、実行サイクル数と状態ハッシュを固定して検証する。公開 ROM の検証を追加する場合も、`public-roms` の依存タスクとして追加し、`ci` へは追加しない。

macOS の市販ゲーム互換性は、利用者が合法的に保持する ROM をローカルで `./bin/swanium-crystal --rom PATH` と明示指定して手動確認する。画面を使わない起動・長時間実行の確認には `--headless-frames COUNT` を併用する。タイトルごとに起動、入力、映像、音声、セーブ、一定時間の連続実行を確認し、結果と既知の制限だけを `docs/compatibility.md` に記録する。市販 ROM、そのハッシュ、セーブデータ、スクリーンショットをリポジトリまたは CI に置かない。

## 音声と状態保存

`spec/core/apu_spec.cr` は24 kHzの生成間隔、スイープ、ノイズ、命令駆動との一致を検証し、自作波形1フレーム分のPCMをSHA-256で固定しています。`spec/core/save_state_spec.cr` はCPU、タイミング、RAM、ポート、PPU、APUを保存して復元し、再保存した全バイトが一致することを確認します。

手動確認では `mise run video-demo` を起動し、F1の `AUDIO` 行でキュー遅延と `DROP` が増えないこと、Spaceによる停止・再開で異音が出ないことを確認します。
