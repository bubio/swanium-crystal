# メニュー構成

この文書はSwanium CrystalのネイティブGUIにおけるメニュー構成を定義する。
ゲーム画面、ゲームパッド入力、音声出力はSDL2が担当し、メニューと設定画面はUIng/libui-ngを介した各OSのネイティブUIとして提供する。

## 共通の操作

- `Open ROM…`: `.ws` または `.wsc` を選び、実行中のROMを置き換える。
- `Open Recent`: 最近開いたROMのサブメニュー。`Clear History`で履歴を消去できる。
- `Save State` / `Load State`: スロットを選ぶサブメニュー。
- `Pause`: エミュレーションの停止と再開を切り替える。
- `Reset`: 現在のROMをリセットする。
- `Scale`: 1xから4xを選ぶサブメニュー。
- `Renderer`: Nearest NeighborとBilinearを選ぶサブメニュー。
- `Escape`: フルスクリーン中は通常ウィンドウへ戻る。アプリケーションは終了しない。

画面の向きはROMヘッダーの縦持ち／横持ち情報から自動決定する。手動回転は提供しない。

## ステートセーブ

ステートは現在ロード中のROMごとに、ROM内容のSHA-256で分離して保存する。ステートロードには先に対象ROMを開く必要があり、ほかのROM向けのステートは表示・ロードしない。各ROMには手動スロット`0`から`9`を持つ。

- `Save State`は全スロットを常に選択できる。既存スロットは`Slot 0 — 2026-08-13 12:34:56`のように更新日時を表示する。
- `Load State`は有効なスロットだけ選択でき、同じ日時表記を使う。
- 保存直後に両サブメニューを更新する。
- ファイル内容のROM識別子が現在のROMと一致しないステートはロードを拒否する。
- カートリッジSRAM／EEPROMの通常セーブとは別であり、自動保存・自動ロード・`Load State File…`は提供しない。

## macOS

macOSではアプリケーション固有の項目をアプリケーションメニューへ置く。`File`メニューは作らず、ROMと実行状態に関する項目は`Emulation`へ統合する。

```text
Swanium Crystal   About Swanium Crystal…
                  ──────────────────────
                  Settings…    ⌘,
                  ──────────────────────
                  Quit          ⌘Q

Emulation         Open ROM…
                  Open Recent ▶
                  ──────────────────────
                  Save State ▶
                  Load State ▶
                  ──────────────────────
                  Pause
                  Reset

View              Scale ▶
                  Fullscreen
                  Renderer ▶
```

## Windows

Windowsではアプリケーションメニューを設けず、ファイル操作と終了を`File`、製品情報を`Help`へ置く。

```text
File              Open ROM…
                  Open Recent ▶
                  ──────────────────────
                  Save State ▶
                  Load State ▶
                  ──────────────────────
                  Settings…
                  ──────────────────────
                  Exit

Emulation         Pause
                  Reset

View              Scale ▶
                  Fullscreen
                  Renderer ▶

Help              About Swanium Crystal…
```

## Linux

LinuxでもWindowsと同じトップレベル構成を使う。デスクトップ環境ごとの表記差を避けるため、設定画面は`Settings…`、終了は`Quit`と表記する。

```text
File              Open ROM…
                  Open Recent ▶
                  ──────────────────────
                  Save State ▶
                  Load State ▶
                  Settings…
                  ──────────────────────
                  Quit

Emulation         Pause
                  Reset

View              Scale ▶
                  Fullscreen
                  Renderer ▶

Help              About Swanium Crystal…
```
