# Swanium Crystal

WonderSwan 系ハードウェアを Crystal で再実装する、ヘッドレステスト可能なエミュレータプロジェクトです。現在は段階 0 の開発基盤です。

```sh
mise run setup
mise run check
mise run build
./bin/swanium --version
```

SDL2 の導入確認には、デスクトップ環境で `mise run sdl-smoke` を実行します。実 ROM、BIOS、商用ゲームデータは扱いません。詳細は [開発計画](docs/development-plan.md)、[設計](docs/architecture.md)、[テスト](docs/testing.md)、[開発規約](docs/development.md)、[ライセンス方針](docs/licensing.md) を参照してください。
