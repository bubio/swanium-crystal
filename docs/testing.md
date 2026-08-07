# テスト

通常の検証は次の一コマンドで行う。

```sh
mise run ci
```

これは整形チェック、`crystal spec`、ビルドを実行する。`mise run build` はCLIを `bin/swanium-crystal` に生成する。SDL2の最小確認はGUIセッションで `mise run sdl-smoke`、画面・入力・60 Hz提示の確認は `mise run video-demo` を使う。

PPU specは単色2bpp、Color / Crystalのplanar・packed 4bpp、スプライト、パレット、RGB444→RGBA8888変換を検証する。さらに、自作パターンの129,024バイトのRGBA画像を `spec/fixtures/video_test_pattern.rgba.zlib.base64` の圧縮済み期待画像と完全比較する。1バイトでも異なればCIを失敗させ、最初の差分位置を報告する。期待画像は仕様変更をレビューした場合だけ更新する。

公開テスト ROM はリポジトリに含めない。将来の統合テストでは、環境変数で明示的に渡されたローカルパスだけを読み、実行サイクル数と状態ハッシュを固定して検証する。

## 音声と状態保存

`spec/core/apu_spec.cr` は24 kHzの生成間隔、スイープ、ノイズ、命令駆動との一致を検証し、自作波形1フレーム分のPCMをSHA-256で固定しています。`spec/core/save_state_spec.cr` はCPU、タイミング、RAM、ポート、PPU、APUを保存して復元し、再保存した全バイトが一致することを確認します。

手動確認では `mise run video-demo` を起動し、F1の `AUDIO` 行でキュー遅延と `DROP` が増えないこと、Spaceによる停止・再開で異音が出ないことを確認します。
