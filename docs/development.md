# 開発環境と規約

## 必要なもの

macOS または Linux で [mise](https://mise.jdx.dev/) を導入してから、次を実行する。

```sh
mise run setup
mise run ci
```

Crystal は mise が導入する。SDL2 は OS の開発ライブラリを使うため、macOS では `brew install sdl2`、Ubuntu では `sudo apt install libsdl2-dev` を一度だけ実行する。固定対象の LLVM は Crystal 1.18.2 公式配布物に同梱される版（15.0.7）、SDL2 は 2.32.70 であり、`mise.toml` の `vars` に記録する。

`mise run ci` は整形チェック、headless spec、ビルドを実行する。整形を適用する場合は `mise run format-fix` を使う。`mise run sdl-smoke` はデスクトップセッションで SDL2 のウィンドウ作成を確認する。CI とコアの spec はヘッドレスで実行できる。

公開CPUテストROMはリポジトリに含めない。ローカルでのみ `WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run wscputest` を実行できる。この診断は命令数、サイクル数、停止理由、最終レジスタを出力する。画面上の Pass/Fail を判定するオラクルは、PPUとタイルマップデコーダが揃う段階で追加する。

## コーディング規約

- `crystal tool format` の出力を正とする。
- ハードウェア境界の数値には `UInt8`、`UInt16`、`UInt32`、`UInt64` を明記する。
- コアは同期的であり、OS API、SDL2、時計、fiber に依存しない。
- 通常の問い合わせ失敗は `foo?` と `Nil`、設定不備・初期化失敗は意味のある `Exception` を使う。
- ホットパスでは一時的な `String`、配列、クロージャ、例外を作らない。

## ログとエラー

通常の実行は標準出力へ簡潔な状態を出力する。診断ログは将来 `debug` 層に集約し、コアから直接出力しない。SDL2 などの初期化に失敗した場合は、呼び出し元が原因を識別できる例外を送出する。
