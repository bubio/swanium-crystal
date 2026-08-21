# Linux 単一ウィンドウ統合計画

## 結論

Linux 版は、GTK3 が唯一のメインウィンドウ、メニュー、ステータスバー、設定画面を所有し、ゲーム表示領域だけを SDL2 が描画する構成にする。GTK3 の `GtkDrawingArea` が生成した X11 子ウィンドウを `SDL_CreateWindowFrom` で包み、そこへ `SDL_Renderer` とストリーミングテクスチャを作る。

この構成は SDL2 公式の `testnative` / `testnativex11` と `SDL_CreateWindowFrom` の契約を実装根拠にする。XM8M は「画面と UI を一つのウィンドウに収める」挙動の参考にするが、Linux UI も SDL で描く実装なので、GTK3 と SDL2 の所有権分担の根拠にはしない。

```text
GtkWindow（唯一の常設トップレベル）
├── GtkMenuBar
├── GtkDrawingArea
│   └── GdkWindow / X11 Window ID
│       └── SDL_CreateWindowFrom
│           └── SDL_Renderer + streaming texture
└── ステータス行

GtkWindow（設定。開いている間だけ存在する transient window）
```

ゲーム画面、キーボード／ゲームパッド入力、音声は SDL2 に残す。GTK3 はゲームの RGBA フレームを Cairo で再描画しない。非表示の補助 SDL ウィンドウや、GTK と SDL の二重描画経路も作らない。macOS 実装は変更しない。

## 解決する問題

- ROM 起動時に GTK と SDL の二つのウィンドウが表示される。
- ウィンドウ、フォーカス、終了、全画面表示の所有者が曖昧になる。
- 回転時と整数倍率変更時に、GTK のレイアウトと SDL の描画寸法がずれる。
- GTK/Cairo へのフレーム複製により、余分な変換と macOS 版とは異なる描画経路が生じる。

## 対応範囲

最初の対象は Ubuntu LTS の X11 セッション、および XWayland 上で X11 バックエンドを使う GTK3 と SDL2 とする。system SDL2 と GTK3 を維持し、この段階では SDL3 へ移行しない。

Wayland ネイティブ対応は同じ作業に混ぜない。SDL3 には既存の `wl_display` と `wl_surface` から外部ウィンドウを作る公式プロパティがあるが、GTK と SDL が同じ `wl_display` を共有すること、サイズ通知、スケーリング、入力を別途検証する必要がある。X11 版の完了後に独立した試作で可否を決める。

## 所有権とライフサイクル

- GTK3 がトップレベル、ゲーム領域のネイティブ子ウィンドウ、メニュー、ステータス行を生成・破棄する。
- `GtkDrawingArea` の realize 完了後にだけ `gdk_x11_window_get_xid` で X11 Window ID を取得する。
- `SDL_CreateWindowFrom` が返す `SDL_Window` はラッパーであり、元の X11 ウィンドウを所有しない。
- 終了時は SDL texture、renderer、ラッパー window の順に破棄し、その後で GTK widget を破棄する。
- GTK と SDL の video API はメインスレッドだけから呼ぶ。
- フレームは `SDL_UpdateTexture` で一度だけ転送し、GTK 側へ複製しない。

## 実装段階

### 0. SDL 公式パターンの最小検証

- [x] `tools/linux/` に GTK3 の `GtkWindow` と `GtkDrawingArea` だけを持つ検証プログラムを置く。
- [x] realize 後の X11 Window ID を `SDL_CreateWindowFrom` に渡し、SDL renderer と texture でテスト画像を表示する。
- [x] 起動、リサイズ、終了を繰り返し、二つ目のトップレベル、クラッシュ、X11 エラーがないことを確認する。
- [x] renderer driver と失敗時の `SDL_GetError` を記録する。

この検証が通るまでは製品コードを切り替えない。失敗しても、別ウィンドウを隠す回避策には進まない。

### 1. 製品コードへの統合

- [x] Linux ネイティブアダプタに、ゲーム領域の作成、realize、X11 Window ID の取得、破棄を閉じ込める。
- [x] Linux の SDL 初期化を通常の `SDL_CreateWindow` から `SDL_CreateWindowFrom` へ切り替える。
- [x] 既存の renderer、texture、入力、音声をラップしたウィンドウへ接続する。
- [x] GTK/Cairo の RGBA 描画経路と非表示の補助 SDL ウィンドウを削除する。
- [x] 初期化失敗時も、作成済みリソースを所有権の逆順で解放する。
- [x] X11 バックエンドを利用できない場合は、原因と対応範囲を明示して終了する。

### 2. 寸法、回転、全画面表示

- [x] 横向き `224×144`、縦向き `144×224` に整数倍率を掛けた値をゲーム領域の要求サイズにする。
- [x] メニューとステータス行の高さは GTK に計測させ、ゲーム領域の寸法へ混ぜない。
- [x] 回転時はトップレベルを作り直さず、ゲーム領域の要求サイズと SDL 出力だけを更新する。
- [x] nearest / bilinear は SDL の描画設定に一本化する。
- [x] 全画面から戻った後も倍率と向きを保持する。
- [x] HiDPI では GTK の論理サイズと SDL renderer の実出力を取得し、倍率を推測しない。

### 3. イベントと入力

- [x] GTK のイベント処理と `SDL_PollEvent` を同じメインスレッドで進め、処理順序を固定する。
- [x] 通常はゲーム領域がフォーカスを持ち、設定画面を閉じたらフォーカスを戻す。
- [x] X11 キー注入、SDL 仮想ゲームパッドの hot-plug とボタン読み取り、WM close、全画面切替を自動検証する。
- [ ] 物理キーボードと物理ゲームパッドでも実機操作を確認する。
- [x] GTK のショートカットとゲーム入力が二重処理されないよう責務を定義する。

### 4. Linux UI の整合

- [x] メニュー項目、チェック状態、無効状態、ショートカットを macOS 版と同じ機能構成にする。
- [x] ステータスは一行に収め、向きや倍率で不要な余白を作らない。
- [x] 設定画面は GTK 標準の余白、行間、ラベル整列、ボタン配置を使い、固定座標を使わない。
- [x] 設定の反映、キャンセル、再表示時の復元を確認する。
- [x] Linux の外観は GTK テーマに従わせ、macOS の見た目をピクセル単位では模倣しない。

### 5. X11 / XWayland の検証と配布

- [x] Ubuntu LTS の GNOME/X11 と Weston 上の XWayland で、起動、ROM 読み込み、終了を確認する。
- [x] 横／縦、倍率 1〜4、フィルタ、全画面、設定画面の反映・取消・再表示を確認する。
- [x] 注入キーボード、仮想ゲームパッド、実音声、ゲーム内保存、ステート保存を確認する。
- [x] GNOME/X11 と Weston/XWayland でフォーカス、装飾、HiDPI を確認する。
- [x] GNOME 以外の任意確認先として KDE の有無を調べ、現在の環境には未導入であることを記録する。KDE は任意の追加リリースマトリクスとする。
- [x] `gdk-x11-3.0` を含む依存を deb / rpm / AppImage へ反映する。
- [x] macOS x86_64 / arm64 のコード生成と既存 CI ジョブ定義が維持されていることを確認する。
- [ ] 現在の差分に対する macOS 実機 CI のビルドと回帰 spec を確認する。

### 6. Wayland ネイティブ対応の判断

- [x] SDL3 の外部 Wayland surface 公式 API で独立した検証プログラムを作る。
- [x] GTK と SDL の `wl_display` / `wl_surface` 共有、サイズ通知、整数倍率、回転、scale 1 / 2 の HiDPI、描画と入力 polling を確認する。
- [x] seat のあるネイティブ Wayland セッションで実入力とフォーカスを確認する。
- [x] 新規 compositor ごとの反復実行で protocol error と二重破棄がないことを確認する。
- [x] 実入力とフォーカスを含め X11 版と同じ完了条件を満たした場合だけ製品統合を計画する。

検証が成立するまでは Wayland ネイティブ対応済みと表示しない。SDL3 への全面移行も、この試作だけを理由には行わない。

#### 製品統合の判断と後続計画

独立試作は surface 共有、描画、寸法、HiDPI、seat 入力、フォーカス、終了の条件を満たしたため、ネイティブ Wayland の製品統合は技術的に実行可能と判断する。ただし現製品は SDL2 を使用しており、試作の成立だけを理由にこの変更へ混ぜない。次の SDL3 移行作業で以下を順に行う。

1. macOS と X11 / XWayland の既存経路を維持したまま、SDL API を SDL3 対応アダプタへ置き換える。
2. Linux 起動時に GDK backend を判定し、X11 は既存の XID、Wayland は GTK と同じ `wl_display` と realized `wl_surface` を SDL3 properties へ渡す。
3. Wayland では同じキーが GDK と SDL の双方に届くことを確認済みなので、GDK→SDL の合成イベントを停止し、SDL の直接入力だけをゲーム入力へ使って二重処理を防ぐ。GTK accelerator はメニュー操作だけを担当する。
4. GTK が surface とトップレベルを所有し、SDL texture、renderer、外部 surface wrapper、GTK widget の順で終了する所有権テストを追加する。
5. X11 / XWayland とネイティブ Wayland の双方で、単一ウィンドウ、横／縦、倍率 1〜4、HiDPI、全画面、設定、入力、音声、保存、反復終了の同じ回帰マトリクスを通す。

この後続作業が完了するまでは、配布物と互換性表でネイティブ Wayland 対応を宣言しない。

## 検証記録

2026-08-18 に Ubuntu 24.04.4 LTS / GNOME / X11、および headless Weston 上の rootful XWayland で以下を確認した。

- `mise run linux-native-probe`: OpenGL renderer (`flags=0xa`) で GTK3 の X11 子ウィンドウへの描画、拡大・縮小、終了に成功。
- `mise run linux-sdl-smoke`: 製品経路で横・縦、倍率 1〜4、nearest / bilinear、全画面、設定の Cancel / Apply / 再表示、SDL 仮想ゲームパッドの追加・削除とボタン press / release を行い、3 回連続で GTK のアプリケーションウィンドウが一つだけであることを X11 のウィンドウツリーから確認。GTK がフォーカスを所有する構成でもゲームパッド状態を更新できるよう、SDL の background controller polling を有効にした。
- `mise run linux-video-smoke`: SDL renderer、ストリーミング texture、入力 polling、dummy audio queue を使う自己完結した 30 フレーム実行に成功。
- `mise run linux-rom-smoke`: 横向き `.ws` と縦向き `.wsc` を実行し、PipeWire 上の PulseAudio 実デバイス、ステート保存後の SRAM 復元、8 KiB の cartridge save と検証マーカーを確認。
- `mise run linux-keyboard-smoke`: X11/XWayland のフォーカス済みゲーム領域へキーを注入し、GTK から SDL の `KEYDOWN` へ一度だけ届くことを確認。
- `mise run linux-launcher-smoke`: ICCCM `WM_DELETE_WINDOW` を送信し、ランチャーを 3 回連続で正常終了。`xdotool windowclose` のような X window の直接破棄は検証に使わない。
- `mise run build-linux`、`mise run format`、`mise run spec`（244 examples）、deb / rpm / AppImage の生成と内容・依存関係の検査に成功。AppImage も単一ウィンドウ smoke test を 3 回通過。
- X11 を含まない `GDK_BACKEND` / `SDL_VIDEODRIVER` を指定した場合、Wayland ネイティブが対象外であることを示すエラーで終了することを確認。
- `tools/linux/native_wayland_probe.c` は SDL3 3.4.12 の Wayland 対応ビルドで実行。新規 Weston compositor の scale 1 と 2 で GTK の論理サイズ `448×288`、SDL pixel size `448×288` / `896×576` を確認し、`448×288 → 672×432 → 288×448 → 448×288` のリサイズ・回転、描画、入力 polling、終了に成功。
- 2026-08-21 に GNOME/X11 内の Weston X11 backend（seat あり）で試作を再実行。親 X11 ウィンドウへ注入したキーが Weston seat を経由して GDK と SDL の両方へ届き（`GDK=1 SDL=1`）、Wayland トップレベルのフォーカス、同じリサイズ・回転、描画、終了も成功した。
- 2026-08-21 に X11 製品経路の倍率変更を再検証し、GTK の子ウィンドウ変更を `SDL_CreateWindowFrom` の wrapper が自動追従しない問題を修正した。GTK の実 allocation を SDL wrapper へ同期し続け、1x でゲーム領域と renderer 出力が `224×144`、4x で `896×576` になることを実動作中に確認した。通常ウィンドウには現在倍率の最小・最大 geometry hint を同値で設定し、`896×645` の4xトップレベルへ `700×500` の変更を要求しても寸法が変わらないことを確認した。全画面時だけ固定制約を外し、復帰時に選択倍率の固定寸法へ戻す。
- macOS は `x86_64-apple-darwin` と `aarch64-apple-darwin` の cross code generation に成功した。実際のリンク、実行、回帰 spec は既存の macOS CI が現在の差分を実行するまで未確認。

製品は SDL2 のままなので、後続の SDL3 移行が完了するまでは引き続き X11 / XWayland 対応として扱う。KDE、物理キーボード／ゲームパッド、macOS 実機 CI は、それぞれ該当環境での検証記録を追加するまで未完了とする。

## 完了条件

- 起動時も ROM 起動後も、常設のメインウィンドウは一つだけである。
- SDL が GTK のゲーム領域へ直接描画し、別の SDL ウィンドウや Cairo のゲーム描画経路がない。
- 横向きと縦向きが指定倍率どおりで、メニューとステータス以外の余白がない。
- 回転、倍率、フィルタ、全画面の変更後もウィンドウ、入力、音声が継続する。
- メニュー、ステータス、設定画面が macOS 版と同じ機能を提供し、GTK 標準レイアウトで表示される。
- 終了と再起動を繰り返してもクラッシュ、X11 エラー、SDL リソースの解放漏れがない。
- `mise run build-linux`、spec、formatter、macOS の既存ビルドと回帰テストを通過する。
- README と配布物で X11、XWayland、Wayland ネイティブの対応範囲を区別する。

## 中止・再検討条件

対象 X11 / XWayland 環境で `SDL_CreateWindowFrom` と SDL renderer の組合せが安定せず、公式の最小例を再現できない場合は製品統合を中止する。原因と driver ごとの結果を記録し、XM8M 型の SDL 単一ウィンドウ UI と SDL3 の外部ネイティブウィンドウ API を別計画として比較する。

二つ目の SDL ウィンドウを隠すことや、GTK/Cairo と SDL の二重描画を恒久実装にすることは代替案に含めない。

## 公式資料

- [SDL2 `testnative.c`](https://github.com/libsdl-org/SDL/blob/SDL2/test/testnative.c)
- [SDL2 X11 実装例 `testnativex11.c`](https://github.com/libsdl-org/SDL/blob/SDL2/test/testnativex11.c)
- [SDL2 `SDL_CreateWindowFrom`](https://wiki.libsdl.org/SDL2/SDL_CreateWindowFrom)
- [GTK3 X11 `gdk_x11_window_get_xid`](https://docs.gtk.org/gdk3-x11/method.X11Window.get_xid.html)
- [SDL3 `SDL_CreateWindowWithProperties`](https://wiki.libsdl.org/SDL3/SDL_CreateWindowWithProperties)
- [SDL3 Wayland integration notes](https://wiki.libsdl.org/SDL3/README-wayland)
- [sdl2-compat の X11 / XWayland 注意事項](https://github.com/libsdl-org/sdl2-compat)
