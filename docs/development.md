# 開発環境と規約

## 必要なもの

対応環境は macOS と Linux である。[mise](https://mise.jdx.dev/) を導入してから、次を実行する。

```sh
mise run setup
mise run ci
```

Crystal は mise が導入する。macOS では SDL2-compat と SDL3 のOS開発ライブラリを使うため、`brew install sdl2 sdl3` を一度だけ実行する。Linux では SDL2、GTK3、GDK X11 の開発ライブラリが必要である。`mise run build-linux` は GTK3 が所有する単一ウィンドウの `GtkDrawingArea` を `SDL_CreateWindowFrom` で包み、SDL2 がゲーム画面へ直接描画する最適化済み実行ファイルを生成する。`mise run linux-native-probe` は最小構成で起動、リサイズ、描画、終了と renderer driver を検証し、`mise run linux-sdl-smoke` は製品コードの単一ウィンドウ、横・縦、倍率、filter、全画面、設定、仮想ゲームパッド、反復終了を検証する。`mise run linux-video-smoke` は self-contained な映像、入力 polling、dummy audio queue を 30 フレーム実行する。`mise run linux-rom-smoke` は生成 ROM、実音声、ステート保存と cartridge save、`mise run linux-keyboard-smoke` は注入キーの GTK→SDL 配送、`mise run linux-launcher-smoke` は ICCCM のウィンドウ終了を検証する。いずれも X11 または XWayland セッションが必要で、Wayland ネイティブは未対応である。SDL3、GTK3、GDK Wayland の開発ファイルとネイティブ Wayland セッションがある環境では、`mise run linux-native-wayland-probe` で GTK の `wl_display` / `wl_surface` を SDL3 と共有する独立試作を実行できる。これは製品の Wayland 対応を有効にするものではない。`mise run package-linux-deb`、`mise run package-linux-rpm`、`mise run package-linux-appimage` は各配布物を生成する（RPM は `rpmbuild`、AppImage は `LINUXDEPLOY` と ImageMagick を必要とする）。

`mise run ci` は整形チェック、画面fixtureを含むheadless spec、最適化済みリリース `.app` バンドル、自作カートリッジによるCLIの900フレーム統合テスト、SDL2 dummyビデオドライバの起動確認を実行する。整形を適用する場合は `mise run format-fix` を使う。GitHub Actions は `tools/build_macos_sdl.sh` で公式リリースの SDL3 3.4.12 と SDL2-compat 2.32.70 のソースtarballをSHA-256検証して取得し、macOS 13.5向けにビルドする。Homebrewのバイナリは使わない。`assets/macos/AppIcon.png` は配布用の1024pxアイコン原画で、`tools/build_macos_icon.sh` が bundle resource の `AppIcon.icns` を生成する。`tools/build_macos_app.sh` はアイコンとメニューのコンパイル、アプリバンドルの組立、依存 dylib の同梱、ad-hoc 署名を担当し、`tools/package_macos_app.sh` は完成した `.app` を配布 ZIP にするだけに限定する。`mise run build` は `bin/Swanium Crystal.app` に `--release --no-debug` の最適化済みmacOSアプリケーションバンドルを生成し、SDL2-compat、SDL3、OpenSSL を `Contents/Frameworks` へ同梱する。`mise run package-macos` はアーキテクチャ名付きの ZIP を `dist/` に生成する。デバッガ作業だけは `mise run build-debug` を使う。音声はAPUの24 kHz出力を、SDL2が選択したホストレートへ状態を保った線形補間で変換し、50 msを下回る場合だけエミュレーションを先行させる。`mise run sdl-smoke` はデスクトップセッションでバンドルを起動してSDL2のウィンドウ作成を確認し、`mise run video-demo` は実際の映像と入力を確認する。CIとコアのspecはヘッドレスで実行できる。

`mise run ci` はリポジトリにある自作 fixture だけを使い、公開テスト ROM は一切読み込まない。公開 CPU テスト ROM はリポジトリに含めず、ローカルでのみ `WS_CPU_TEST_ROM=/path/to/WSCpuTest.wsc mise run public-roms` を実行する。これは WSCpuTest v0.7.1 のソースに従い、Color 機として 8 フレーム待機し、A を 1 フレーム入力して `Test All` を選ぶ。以後 BG タイルマップ（WRAM `0x1000`）の `Ok!` / `Failed!` とテスト中フラグ（`0x0136`）を判定する。必要なら `WS_CPU_TEST_MAX_FRAMES`（既定 13500）で上限を変更できる。単独で WSCpuTest だけを診断したい場合は、従来どおり `mise run wscputest` も使える。

市販ゲームの ROM は配布・収集・ダウンロードしない。互換性確認では、利用者が合法的に用意したローカルファイルだけを `--rom PATH` で明示的に指定して使う。受け付ける拡張子は `.ws` / `.wsc` で、16バイトのカートリッジフッタと起動エントリを検査してから起動する。SRAM セーブはmacOSの専用設定ディレクトリにROMファイル名ごとに保存する。ROM 本体、ハッシュ、セーブデータ、スクリーンショットをリポジトリや CI に追加してはならない。

## コーディング規約

- `crystal tool format` の出力を正とする。
- ハードウェア境界の数値には `UInt8`、`UInt16`、`UInt32`、`UInt64` を明記する。
- コアは同期的であり、OS API、SDL2、時計、fiber に依存しない。
- 通常の問い合わせ失敗は `foo?` と `Nil`、設定不備・初期化失敗は意味のある `Exception` を使う。
- ホットパスでは一時的な `String`、配列、クロージャ、例外を作らない。

## パフォーマンス測定と最適化方針

性能改善は、最適化済みリリースビルドを実測してから行う。まず macOS の `sample` などでホットスポットを確認し、変更後は同一のローカル ROM・フレーム数・実行条件で CPU 時間を比較する。通常 CI に市販 ROM や公開 ROM を追加しない原則は維持し、これらはローカルの opt-in 測定だけに用いる。画面・音声・状態に触れる変更は `mise run spec`、リリースビルド、該当する公開 ROM または市販ゲームの手動確認を通してから採用する。

2026-08 の基準測定では、命令ごとに空の音声書込み配列を再確保する経路がGCを支配していたため、キューを再利用するdrain APIへ変更した。続いて、APUの無音時と波形のみ時のバルクtickを追加した。ローカルのWSCpuTestを12,000フレーム実行した測定では、波形のみ高速経路により user CPU時間が12.33秒から9.52秒へ短縮した。無音NOP fixtureでは、無音高速経路により6.63秒から4.51秒へ短縮した。これらの数値は開発機の比較値であり、他の機種・ROM・バックグラウンド負荷での絶対的な性能保証ではない。

Clock Towerは表示がモノクロのままCrystalのノイズLFSR readbackを使う。したがって、APUの高速経路はノイズのreset要求またはgate（`0x8E` のbit 3/4）が有効な場合に適用してはならない。Crystal実機種別とColor表示モードは別の条件として扱い、LFSRの進行とHyperVoiceのミキシングを混同しない。

PPUでは、走査線単位の背景タイルマップキャッシュとパレットLUTを試行したが、同一ベンチマークで改善を確認できなかったため採用しなかった。今後のPPU／CPU最適化は、まず実ゲームごとのプロファイルで `tile_pixel`、スプライト合成、メモリ／I/Oアクセスなどが支配的であることを確認してから行う。ヘッドレス実行でPCMを消費せず蓄積する負荷はSDL実行時の負荷と異なるため、音声の評価ではキューへ消費する通常フロントエンドの挙動も確認する。

## ログとエラー

通常の実行は標準出力へ簡潔な状態を出力する。診断ログは将来 `debug` 層に集約し、コアから直接出力しない。SDL2 などの初期化に失敗した場合は、呼び出し元が原因を識別できる例外を送出する。
