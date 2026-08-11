# メニュー構成

この文書はSwanium CrystalのネイティブGUIにおけるメニュー構成を定義する。
ゲーム画面、ゲームパッド入力、音声出力はSDL2が担当し、メニューと設定画面はUIng/libui-ngを介した各OSのネイティブUIとして提供する。

## 共通の操作

- `Open ROM…`: `.ws` または `.wsc` を選び、実行中のROMを置き換える。
- `Open Recent`: 最近開いたROMのサブメニュー。
- `Save State` / `Load State`: スロットを選ぶサブメニュー。
- `Pause`: エミュレーションの停止と再開を切り替える。
- `Reset`: 現在のROMをリセットする。
- `Scale`: 1xから4xを選ぶサブメニュー。
- `Rotation`: 通常・左回転・右回転を選ぶサブメニュー。
- `Renderer`: Nearest NeighborとBilinearを選ぶサブメニュー。

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
                  Rotation ▶
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
                  Rotation ▶
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
                  Rotation ▶
                  Renderer ▶

Help              About Swanium Crystal…
```
