# OpenMac

OpenMac 是一款 macOS 优先的 AI Agent Kanban 应用，用于项目规划、任务分配和执行流程管理。

## 语言

- [English](README.md)
- [繁體中文](README.zh-Hant.md)
- 简体中文（当前）
- [Français](README.fr.md)
- [Español](README.es.md)
- [日本語](README.ja.md)
- [한국어](README.ko.md)

## 截图

### Kanban 看板
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Agent 实时控制台
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## 核心功能

- AI Agent Kanban 流程（`To Do`、`In Progress`、`Review`、`Done`）
- 基于技能和负载自动分配任务
- 已分配任务批量执行（`Run Assigned`）
- Runtime 选项：`Local Mock`、`OpenAI Compatible`
- OpenAI 兼容认证：`API Key` 或 `Codex Bridge`
- PM Planner：
  - 根据项目说明生成可执行 ticket
  - 创建前可编辑 ticket
  - 快速模板（`SaaS Product`、`Desktop App`、`Developer API`）
  - `Create + Run Assigned` 一键流程
- Agent Live Console，支持复制输出和调试日志
- 看板健康建议、WIP 限制、手动分流
- 工作区 JSON 导入/导出
- 多语言界面（英/繁中/简中/法/西/日/韩），不支持语言回退英文

## 技术栈

- Swift
- SwiftUI
- XCTest / Swift Testing
- Xcode 项目（`OpenMac.xcodeproj`）

## 项目结构

```text
OpenMac/
  Domain/         # 模型、分派逻辑、规划引擎
  ViewModels/     # 看板编排与 runtime 集成
  Views/          # 可复用 SwiftUI 视图
  Localization/   # 语言设置与解析
  *.lproj/        # 本地化字符串
OpenMacTests/     # 单元/逻辑测试
OpenMacUITests/   # UI 测试
```

## 快速开始

1. 克隆仓库。
2. 使用 Xcode 打开 `OpenMac.xcodeproj`。
3. 选择 scheme：`OpenMac`。
4. 在 `My Mac` 上运行。

## AI Runtime 配置

### 方案 A：API Key

- 设置环境变量 `OPENAI_API_KEY`（或 `OPENAI_COMPAT_API_KEY`）。
- 如使用 OpenAI 兼容端点，可选设置 `OPENAI_BASE_URL`。

### 方案 B：Codex Bridge

1. 安装 Codex CLI 或 Codex App。
2. 在终端运行 `codex login`。
3. 在应用 runtime 设置中选择 `OpenAI Compatible` + `Codex Bridge`。

## 测试（TDD 友好）

运行全部测试：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

只运行指定测试 target：

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```

