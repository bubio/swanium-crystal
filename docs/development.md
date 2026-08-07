# 開発環境と規約

## 必要なもの

最初の対応環境は macOS である。[mise](https://mise.jdx.dev/) を導入してから、次を実行する。

```sh
mise run setup
mise run ci
```

Crystal は mise が導入する。SDL2 は OS の開発ライブラリを使うため、macOS では `brew install sdl2` を一度だけ実行する。固定対象の LLVM は Crystal 1.18.2 公式配布物に同梱される版（15.0.7）、SDL2 は 2.32.70 であり、`mise.toml` の `vars` に記録する。Linux など他プラットフォームの導入手順は、macOS の市販ゲーム互換性を達成した後に追加する。

`mise run ci` は整形チェック、画面fixtureを含むheadless spec、最適化済みリリースビルド、自作カートリッジによるCLIの900フレーム統合テスト、SDL2 dummyビデオドライバの起動確認を実行する。整形を適用する場合は `mise run format-fix` を使う。`mise run build` は `--release --no-debug` の最適化済みmacOS実行ファイルを生成する。デバッガ作業だけは `mise run build-debug` を使う。音声はAPUの24 kHz出力を、SDL2が選択したホストレートへ状態を保った線形補間で変換し、50 msを下回る場合だけエミュレーションを先行させる。`mise run sdl-smoke` はデスクトップセッションでSDL2のウィンドウ作成を確認し、`mise run video-demo` は実際の映像と入力を確認する。CIとコアのspecはヘッドレスで実行できる。

`mise run ci` はリポジトリにある自作 fixture だけを使い、公開テスト ROM は一切読み込まない。公開 CPU テスト ROM はリポジトリに含めず、ローカルでのみ `WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run public-roms` を実行する。これは WSCpuTest v0.7.1 のソースに従い、Color 機として 8 フレーム待機し、A を 1 フレーム入力して `Test All` を選ぶ。以後 BG タイルマップ（WRAM `0x1000`）の `Ok!` / `Failed!` とテスト中フラグ（`0x0136`）を判定する。必要なら `WS_CPU_TEST_MAX_FRAMES`（既定 13500）で上限を変更できる。単独で WSCpuTest だけを診断したい場合は、従来どおり `mise run wscputest` も使える。

市販ゲームの ROM は配布・収集・ダウンロードしない。互換性確認では、利用者が合法的に用意したローカルファイルだけを `--rom PATH` で明示的に指定して使う。受け付ける拡張子は `.ws` / `.wsc` で、16バイトのカートリッジフッタと起動エントリを検査してから起動する。SRAM セーブはmacOSの専用設定ディレクトリにROMファイル名ごとに保存する。ROM 本体、ハッシュ、セーブデータ、スクリーンショットをリポジトリや CI に追加してはならない。

## コーディング規約

- `crystal tool format` の出力を正とする。
- ハードウェア境界の数値には `UInt8`、`UInt16`、`UInt32`、`UInt64` を明記する。
- コアは同期的であり、OS API、SDL2、時計、fiber に依存しない。
- 通常の問い合わせ失敗は `foo?` と `Nil`、設定不備・初期化失敗は意味のある `Exception` を使う。
- ホットパスでは一時的な `String`、配列、クロージャ、例外を作らない。

## ログとエラー

通常の実行は標準出力へ簡潔な状態を出力する。診断ログは将来 `debug` 層に集約し、コアから直接出力しない。SDL2 などの初期化に失敗した場合は、呼び出し元が原因を識別できる例外を送出する。
