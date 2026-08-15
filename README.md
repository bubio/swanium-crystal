# Swanium Crystal

Swanium Crystal は、WonderSwan Crystal、WonderSwan Color、WonderSwan のゲームを動かすエミュレータです。[Swanium](https://github.com/bubio/swanium)はRustとSlintで開発しましたが、これは、CrystalとSDL2開発しました。将来は複数のプラットフォームに対応する予定です。

## インストール

[Releases](https://github.com/bubio/swanium-crystal/releases) から、お使いの環境に合ったファイルをダウンロードしてください。

| プラットフォーム | CPU | 最小OS | 配布形式 | 状態 |
| --- | --- | --- | --- | --- |
| macOS | Apple Silicon / Intel | macOS 13.5 | `.app` | 対応済み |
| Windows | — | — | — | 今後対応予定 |
| Linux | — | — | — | 今後対応予定 |

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

セーブデータとステートを削除すると元に戻せません。必要に応じて、アップデート前や削除前にバックアップしてください。
