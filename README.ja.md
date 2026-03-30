# OpenMac

OpenMac は、macOS 向けに最適化された AI エージェント Kanban アプリです。計画、アサイン、実行フローを一体で管理できます。

## 言語

- [English](README.md)
- [繁體中文](README.zh-Hant.md)
- [简体中文](README.zh-Hans.md)
- [Français](README.fr.md)
- [Español](README.es.md)
- 日本語（現在）
- [한국어](README.ko.md)

## スクリーンショット

### Kanban ボード
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Agent Live Console
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## 主な機能

- AI エージェント Kanban フロー（`To Do`、`In Progress`、`Review`、`Done`）
- スキルと負荷に基づく自動アサイン
- アサイン済みタスクの一括実行（`Run Assigned`）
- Runtime モード：`Local Mock`、`OpenAI Compatible`
- OpenAI 互換認証：`API Key` または `Codex Bridge`
- PM Planner：
  - プロジェクト概要から実行可能なチケットを生成
  - 作成前にチケット編集可能
  - クイックテンプレート（`SaaS Product`、`Desktop App`、`Developer API`）
  - `Create + Run Assigned` フロー
- Agent Live Console（出力・デバッグログのコピー対応）
- ボード健全性提案、WIP 制限、手動トリアージ
- ワークスペース JSON の import/export
- 多言語 UI（EN/ZH-TW/ZH-CN/FR/ES/JA/KO）、対象外言語は英語フォールバック

## 技術スタック

- Swift
- SwiftUI
- XCTest / Swift Testing
- Xcode プロジェクト（`OpenMac.xcodeproj`）

## プロジェクト構成

```text
OpenMac/
  Domain/         # モデル、ディスパッチロジック、計画エンジン
  ViewModels/     # ボード制御と runtime 統合
  Views/          # 再利用可能な SwiftUI ビュー
  Localization/   # 言語設定と解決処理
  *.lproj/        # ローカライズ文字列
OpenMacTests/     # 単体/ロジックテスト
OpenMacUITests/   # UI テスト
```

## クイックスタート

1. このリポジトリを clone。
2. Xcode で `OpenMac.xcodeproj` を開く。
3. scheme `OpenMac` を選択。
4. `My Mac` で実行。

## AI Runtime 設定

### A: API Key

- 環境変数 `OPENAI_API_KEY`（または `OPENAI_COMPAT_API_KEY`）を設定。
- OpenAI 互換エンドポイント利用時は `OPENAI_BASE_URL` も任意で設定。

### B: Codex Bridge

1. Codex CLI または Codex アプリをインストール。
2. Terminal で `codex login` を実行。
3. アプリの runtime 設定で `OpenAI Compatible` + `Codex Bridge` を選択。

## テスト（TDD 向け）

全テスト実行：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

特定ターゲットのみ：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```

