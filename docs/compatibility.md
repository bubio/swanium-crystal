# 互換性

動作保証対象は macOS と Linux である。Linux は GTK3 と SDL2 を使う X11 セッション、および Wayland セッション上の XWayland を対象とし、Wayland ネイティブはまだ対象外である。Windows とその他のプラットフォームは、macOS と Linux の市販ゲーム互換性が安定してから検証・配布対象に加える。

## 記録方針

市販ゲームの互換性は、利用者が合法的に保持するローカル ROM を macOS 実機で確認して記録する。ROM 本体、ハッシュ、セーブデータ、スクリーンショットはリポジトリや CI に含めない。

各タイトルでは、タイトル名、検証した版、確認日、macOS の機種、起動、入力、映像、音声、ゲーム内セーブと復元、10分以上の連続実行、既知の制限を記録する。互換性の問題は可能な限りハードウェア機能と再現手順に結び付け、自作 fixture または公開テスト ROM の回帰テストへ還元する。

## 検証済み市販ゲーム

次表の「起動」は、ROM を直接起動して画面を出さない状態で300フレーム（約5秒）実行し、未対応CPU命令が発生しないことを確認した結果である。これは自動化できる起動確認であり、操作感・映像・音声・ゲーム内セーブの最終確認を代替しない。

| タイトル | ROM内の版 | 確認日 | 確認環境 | 起動 | 入力・映像・音声・セーブ | 既知の制限 |
| --- | --- | --- | --- | --- | --- | --- |
| Clock Tower | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 400フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み | QUICK STARTの黒画面はノイズLFSRの修正で解消済み |
| Makaimura | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 300フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み | なし |
| Final Fantasy 4 | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 300フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み | なし |
| Last Alive | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 300フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み | 縦画面表示と書込み単位PCM復元を実装済み |
| Wizardry | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 300フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み | なし |
| Wizardry: Scenario 1 | 0 | 2026-08-08 | macOS / Apple Silicon・Intel | 900フレーム通過 | 起動、操作、映像、音声、ゲーム内セーブ・復元、10分連続実行を手動確認済み。負のチャンネル3スイープ値で音声処理が停止しないことを確認 | なし |

採用済みタイトルの実機確認は完了した。段階4では、市販ROMを使わないCIの画面・SDL起動検証と、今後見つかる差分の回帰テスト化が残る。

## ハードウェア機能

機能単位の対応状況は、市販ゲームの検証結果と公開テスト ROM の結果に基づいて追記する。

## 公開テスト ROM（ローカル検証）

2026-08-08に macOS で、外部に保持した公開テスト ROM を直接起動して確認した。ROM本体やハッシュはリポジトリへ含めない。`WSCpuTest v0.7.1` は専用ハーネスで `Test All` の `Ok!` とCPU停止まで確認し、その他は未対応CPU命令・異常停止なしで指定フレーム数を完走した。

| テスト | 実行結果 | 対応機能 |
| --- | --- | --- |
| WSCpuTest v0.7.1 | 56フレームで `Ok!`、停止 | V30命令・フラグ・割込み |
| ws-test-suite: prefixes / 80186 quirks / interrupt timing / interrupts | 各600フレーム完走 | CPU prefix、V30拡張、割込み境界 |
| ws-test-suite: GDMA timing / sound DMA / alignment access | 各600フレーム完走 | GDMA、SDMA、DMAアラインメント |
| ws-test-suite: sprite scanline limit / tile extended range | 各600フレーム完走 | PPUスプライト上限、Colorタイル範囲 |
| ws-test-suite: cartridge EEPROM / sound quirks / RTC mapper | 各600フレーム完走 | EEPROM、APU、RTC・mapper |
| WSHWTest / WSTimingTest | 各1800フレーム完走 | ハードウェアI/O・タイミング回帰の起動確認 |
