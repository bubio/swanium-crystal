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

- [ ] `tools/linux/` に GTK3 の `GtkWindow` と `GtkDrawingArea` だけを持つ検証プログラムを置く。
- [ ] realize 後の X11 Window ID を `SDL_CreateWindowFrom` に渡し、SDL renderer と texture でテスト画像を表示する。
- [ ] 起動、リサイズ、終了を繰り返し、二つ目のトップレベル、クラッシュ、X11 エラーがないことを確認する。
- [ ] renderer driver と失敗時の `SDL_GetError` を記録する。

この検証が通るまでは製品コードを切り替えない。失敗しても、別ウィンドウを隠す回避策には進まない。

### 1. 製品コードへの統合

- [ ] Linux ネイティブアダプタに、ゲーム領域の作成、realize、X11 Window ID の取得、破棄を閉じ込める。
- [ ] Linux の SDL 初期化を通常の `SDL_CreateWindow` から `SDL_CreateWindowFrom` へ切り替える。
- [ ] 既存の renderer、texture、入力、音声をラップしたウィンドウへ接続する。
- [ ] GTK/Cairo の RGBA 描画経路と非表示の補助 SDL ウィンドウを削除する。
- [ ] 初期化失敗時も、作成済みリソースを所有権の逆順で解放する。
- [ ] X11 バックエンドを利用できない場合は、原因と対応範囲を明示して終了する。

### 2. 寸法、回転、全画面表示

- [ ] 横向き `224×144`、縦向き `144×224` に整数倍率を掛けた値をゲーム領域の要求サイズにする。
- [ ] メニューとステータス行の高さは GTK に計測させ、ゲーム領域の寸法へ混ぜない。
- [ ] 回転時はトップレベルを作り直さず、ゲーム領域の要求サイズと SDL 出力だけを更新する。
- [ ] nearest / bilinear は SDL の描画設定に一本化する。
- [ ] 全画面から戻った後も倍率と向きを保持する。
- [ ] HiDPI では GTK の論理サイズと SDL renderer の実出力を取得し、倍率を推測しない。

### 3. イベントと入力

- [ ] GTK のイベント処理と `SDL_PollEvent` を同じメインスレッドで進め、処理順序を固定する。
- [ ] 通常はゲーム領域がフォーカスを持ち、設定画面を閉じたらフォーカスを戻す。
- [ ] キーボード、ゲームパッド hot-plug、終了、全画面切替を確認する。
- [ ] GTK のショートカットとゲーム入力が二重処理されないよう責務を定義する。

### 4. Linux UI の整合

- [ ] メニュー項目、チェック状態、無効状態、ショートカットを macOS 版と同じ機能構成にする。
- [ ] ステータスは一行に収め、向きや倍率で不要な余白を作らない。
- [ ] 設定画面は GTK 標準の余白、行間、ラベル整列、ボタン配置を使い、固定座標を使わない。
- [ ] 設定の反映、キャンセル、再表示時の復元を確認する。
- [ ] Linux の外観は GTK テーマに従わせ、macOS の見た目をピクセル単位では模倣しない。

### 5. X11 / XWayland の検証と配布

- [ ] Ubuntu LTS の X11 と Wayland セッション上の XWayland で、起動、ROM 読み込み、終了を確認する。
- [ ] 横／縦、倍率 1〜4、フィルタ、全画面、設定画面の組合せを確認する。
- [ ] キーボード、ゲームパッド、音声、ゲーム内保存、ステート保存を確認する。
- [ ] GNOME と、可能なら KDE でフォーカス、装飾、HiDPI の差を確認する。
- [ ] `gdk-x11-3.0` を含む依存を deb / rpm / AppImage へ反映する。
- [ ] macOS の既存ビルドと回帰 spec が無変更で通ることを確認する。

### 6. Wayland ネイティブ対応の判断

- [ ] SDL3 の外部 Wayland surface 公式 API で独立した検証プログラムを作る。
- [ ] GTK と SDL の `wl_display` 共有、サイズ通知、整数倍率、回転、HiDPI、入力を確認する。
- [ ] protocol error、二重破棄、フォーカス不整合がなく、X11 版と同じ完了条件を満たす場合だけ製品統合を計画する。

検証が成立するまでは Wayland ネイティブ対応済みと表示しない。SDL3 への全面移行も、この試作だけを理由には行わない。

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
