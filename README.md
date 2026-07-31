# OpenMac

OpenMac is a macOS-first AI agent Kanban app for planning, dispatching, and running task execution flows.

## Languages

- English (current)
- [繁體中文](README.zh-Hant.md)
- [简体中文](README.zh-Hans.md)
- [Français](README.fr.md)
- [Español](README.es.md)
- [日本語](README.ja.md)
- [한국어](README.ko.md)

## Screenshots

### Kanban Board
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Agent Live Console
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## Highlights

- AI-agent Kanban workflow (`To Do`, `In Progress`, `Review`, `Done`)
- Auto assignment by skills + load balancing
- Batch execution for assigned tasks (`Run Assigned`)
- Runtime options: `Local Mock` and `OpenAI Compatible`
- OpenAI-compatible auth modes: `API Key` or `Codex Bridge`
- PM Planner:
  - Generate execution tickets from project brief
  - Edit tickets before creating
  - Quick templates (`SaaS Product`, `Desktop App`, `Developer API`)
  - `Create + Run Assigned` flow
- Agent Live Console with copyable output/debug logs
- Shared Agent Memory (board-scoped context notes + automatic execution outcome memory)
- Extension Marketplace (install/update/remove/rescan, saved sources, enable/disable)
- Extension command contribution slots:
  - `app.toolbar`
  - `task.card`
  - `pm.planner.panel`
  - `kanban.toolbar`
  - `kanban.sidebar`
  - `marketplace.panel`
- Extension event hooks: `ticket.created`, `run.finished`, `review.entered`
- Hook orchestrator: queue + dedupe + retry/backoff + bounded concurrency
- Built-in extension test harness (dry-run payload + JSON validation)
- Built-in extension E2E acceptance runner (install + enable + slots + hook + output writeback + cleanup)
- Extension observability panel (success rate, avg runtime, latest input/output/error)
- Board health recommendations, WIP limits, and manual triage
- Workspace import/export JSON
- Multi-language UI:
  - English
  - Traditional Chinese
  - Simplified Chinese
  - French
  - Spanish
  - Japanese
  - Korean
  - Unsupported languages fall back to English

## Tech Stack

- Swift
- SwiftUI
- XCTest / Swift Testing
- Xcode project (`OpenMac.xcodeproj`)

## Project Structure

```text
OpenMac/
  Domain/         # models, dispatch logic, planning engine
  ViewModels/     # board orchestration and runtime integration
  Views/          # reusable SwiftUI views
  Localization/   # language settings and resolver
  *.lproj/        # localized strings
OpenMacTests/     # unit/integration logic tests
OpenMacUITests/   # UI tests
```

## Quick Start

1. Clone this repository.
2. Open `OpenMac.xcodeproj` in Xcode.
3. Select scheme `OpenMac`.
4. Run on `My Mac`.

## V2 Invited Test Build

OpenMac v2 is being validated as an Apple/Xcode spec-to-verified-PR delivery
layer. To create the macOS 14+ universal test package from a clean commit:

```bash
tools/package-test-build.sh --launch-smoke
```

The script writes an ad-hoc signed, non-notarized zip and SHA-256 file to
`dist/`. Invited builds use the included OpenMac Evaluation License. See the
[test build install guide](docs/v2/TEST_BUILD_INSTALL.md) for Gatekeeper,
fixture, and Agent Orchestrator connection steps.

With an AO daemon already running, developers can execute the read-only live
adapter probe:

```bash
tools/test-agent-orchestrator-live.sh --url http://127.0.0.1:3001
```

Session creation remains separately opt-in. See the
[AO live smoke guide](docs/v2/AO_LIVE_SMOKE.md) for its prerequisites and
side-effect boundary.

## AI Runtime Setup

### Option A: API Key

- Set `OPENAI_API_KEY` (or `OPENAI_COMPAT_API_KEY`) in your environment.
- (Optional) set `OPENAI_BASE_URL` if using an OpenAI-compatible endpoint.

### Option B: Codex Bridge

1. Install Codex CLI / Codex app.
2. Run `codex login` in Terminal.
3. In app runtime settings, choose `OpenAI Compatible` + `Codex Bridge`.

## Extension SDK

- SDK docs: [docs/EXTENSION_SDK.md](docs/EXTENSION_SDK.md)
- PM plugin API: [docs/PM_PLUGIN_API.md](docs/PM_PLUGIN_API.md)

Scaffold a new extension:

```bash
./tools/openmac-plugin-init.sh com.example.my-plugin ~/Desktop "My Plugin"
```

## Testing (TDD-friendly)

Run all tests:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

Run a specific test target:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```
