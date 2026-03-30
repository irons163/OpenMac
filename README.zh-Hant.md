# OpenMac

OpenMac 是一款 macOS 優先的 AI Agent Kanban 應用，用來做專案規劃、任務分派與執行流程管理。

## 語言

- [English](README.md)
- 繁體中文（目前）
- [简体中文](README.zh-Hans.md)
- [Français](README.fr.md)
- [Español](README.es.md)
- [日本語](README.ja.md)
- [한국어](README.ko.md)

## 截圖

### Kanban 看板
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Agent 即時主控台
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## 主要功能

- AI Agent Kanban 流程（`To Do`、`In Progress`、`Review`、`Done`）
- 依技能與負載自動分配任務
- 已指派任務批次執行（`Run Assigned`）
- Runtime 模式：`Local Mock`、`OpenAI Compatible`
- OpenAI 相容驗證：`API Key` 或 `Codex Bridge`
- PM Planner：
  - 由專案說明自動產生可執行 ticket
  - 建立前可編輯 ticket
  - 快速模板（`SaaS Product`、`Desktop App`、`Developer API`）
  - `Create + Run Assigned` 一鍵流程
- Agent Live Console，可複製輸出與除錯紀錄
- 看板健康建議、WIP 限制、手動分流
- 工作區 JSON 匯入/匯出
- 介面多語系（英/繁中/簡中/法/西/日/韓），不在清單時預設英文

## 技術棧

- Swift
- SwiftUI
- XCTest / Swift Testing
- Xcode 專案（`OpenMac.xcodeproj`）

## 專案結構

```text
OpenMac/
  Domain/         # 資料模型、分派邏輯、規劃引擎
  ViewModels/     # 看板編排與 runtime 整合
  Views/          # 可重用 SwiftUI 元件
  Localization/   # 語言設定與解析
  *.lproj/        # 在地化字串
OpenMacTests/     # 單元/邏輯測試
OpenMacUITests/   # UI 測試
```

## 快速開始

1. 下載此專案。
2. 用 Xcode 開啟 `OpenMac.xcodeproj`。
3. 選擇 scheme：`OpenMac`。
4. 在 `My Mac` 執行。

## AI Runtime 設定

### 方案 A：API Key

- 在環境變數設定 `OPENAI_API_KEY`（或 `OPENAI_COMPAT_API_KEY`）。
- 若使用 OpenAI 相容端點，可選填 `OPENAI_BASE_URL`。

### 方案 B：Codex Bridge

1. 安裝 Codex CLI 或 Codex App。
2. 在 Terminal 執行 `codex login`。
3. 在 App Runtime 設定選擇 `OpenAI Compatible` + `Codex Bridge`。

## 測試（TDD 友善）

執行全部測試：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

只跑特定測試 target：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```

