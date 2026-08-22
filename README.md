# Swanium Crystal

Swanium Crystal は、WonderSwan Crystal、WonderSwan Color、WonderSwan のゲームを動かすエミュレータです。[Swanium](https://github.com/bubio/swanium)はRustとSlintで開発しましたが、これは、CrystalとSDL2開発しました。将来は複数のプラットフォームに対応する予定です。

## インストール

[Releases](https://github.com/bubio/swanium-crystal/releases) から、お使いの環境に合ったファイルをダウンロードしてください。
macOS 向けには `Swanium-Crystal-<version>-macos-arm64.zip` または
`Swanium-Crystal-<version>-macos-x86_64.zip` を展開して利用します。
Windows 向けには `Swanium-Crystal-<version>-windows-x86_64.zip` を展開し、
`swanium-crystal.exe` を実行します。

| プラットフォーム | CPU | 最小OS | 配布形式 | 状態 |
| --- | --- | --- | --- | --- |
| macOS | Apple Silicon / Intel | macOS 13.5 | `.app` | 対応済み |
| Windows | x86_64 | Windows 10 / 11 | `.zip` | 対応済み |
| Linux | x86_64 / arm64 | GTK 3 + SDL2（X11 / XWayland） | `.deb` / `.rpm` / AppImage | 対応済み |

Linux 版は X11 セッション、または Wayland セッション上の XWayland を使用します。GTK3 がメインウィンドウ、メニュー、ステータス、設定画面を所有し、SDL2 は同じウィンドウ内のゲーム領域へ直接描画します。Wayland ネイティブバックエンドは未対応です。`GDK_BACKEND=wayland` や `SDL_VIDEODRIVER=wayland` を明示した環境では起動せず、X11 / XWayland を使用するよう案内します。

> **注意**: このアプリは Apple によるノータリゼーション（公証）を受けていないため、初回起動時に Gatekeeper によってブロックされる場合があります。以下のいずれかの方法で回避できます：
>
> **方法1: ターミナルで隔離フラグを削除**
> ```bash
> xattr -cr "/Applications/Swanium Crystal.app"
> ```
>
> **方法2: システム設定から許可**
> 1. アプリを開こうとしてブロックされた後
> 2. 「システム設定」→「プライバシーとセキュリティ」を開く
> 3. 「"Swanium Crystal"は開発元を確認できないため、使用がブロックされました」の横にある「このまま開く」をクリック


## 操作方法

| 操作 | キーボード |
| --- | --- |
| X方向パッド | 矢印キー |
| Y方向パッド | W / A / S / D |
| A / B ボタン | X / Z |
| Start | Return |
| 終了 | Escape |
| ステート保存 | F5 |
| ステート読込 | F9 |

対応するゲームパッドでは、方向パッド、A/B、Startが使えます。キーとゲームパッドの割り当ては、メニューから変更できます。

## セーブとステート

ゲーム内のセーブデータ（SRAM）は、ROMごとに自動保存されます。F5/F9のステート保存も、開いているROMごとに保存されます。

| プラットフォーム | セーブデータ | ステート・設定 |
| --- | --- | --- |
| macOS | `~/Library/Application Support/swanium-crystal/saves` | `~/Library/Application Support/swanium-crystal` |
| Windows | `%LOCALAPPDATA%\swanium-crystal\saves` | `%LOCALAPPDATA%\swanium-crystal` |
