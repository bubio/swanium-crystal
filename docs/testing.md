# テスト

通常の検証は次の一コマンドで行う。

```sh
mise run check
```

これは `crystal spec` と `crystal tool format --check` を実行する。`mise run build` は CLI を `bin/swanium` に生成する。SDL2 の最小確認は GUI セッションで `mise run sdl-smoke` を使う。

公開テスト ROM はリポジトリに含めない。将来の統合テストでは、環境変数で明示的に渡されたローカルパスだけを読み、実行サイクル数と状態ハッシュを固定して検証する。
