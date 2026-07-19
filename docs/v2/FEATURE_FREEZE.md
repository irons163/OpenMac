# OpenMac v2 功能凍結清單

> 生效日期：2026-07-18
> 適用期間：現在起至 v2 vertical slice 與七天 validation gate 完成

## 1. 凍結規則

1. 凍結項目只修安全、資料遺失、crash 或會阻斷 v2 的問題，不增加功能。
2. Day 10 決策閘門前不刪除舊資料模型或使用者資料，只做隔離的新流程。
3. v2 新程式放在獨立 feature boundary，不再把核心狀態塞進現有近 12k 行的 `ContentView.swift`。
4. 舊 Kanban 可以暫時存在，但不再是 source of truth；新狀態由 runtime、Git、Xcode 與 PR facts 衍生。
5. 新增工作若不能直接縮短「brief → verified PR」時間，預設不做。

## 2. 保留並重用

| 既有能力 | v2 處置 | 現有位置 |
|---|---|---|
| Project brief 與 planner 基礎 | 重用 prompt／解析概念，輸出改成 typed `DeliveryPlan` | [`ProjectPlanningEngine.swift`](../../OpenMac/Domain/ProjectPlanningEngine.swift) |
| Dependency 分析 | 重用 cycle／blocked 判斷概念；dependency 來源改成 typed IDs | [`DependencyGraphInsightsUseCase.swift`](../../OpenMac/UseCases/DependencyGraphInsightsUseCase.swift) |
| 並行 wave scheduling | 抽成 delivery-task scheduler，不再依賴 AgentProfile 欄位 | [`ExecutionCoordinator.swift`](../../OpenMac/ViewModels/ExecutionCoordinator.swift) |
| Retry、backoff、checkpoint | 保留可測的政策與恢復概念，適配 `ExecutionAttempt` | [`ExecutionCheckpointUseCase.swift`](../../OpenMac/UseCases/ExecutionCheckpointUseCase.swift) |
| Approval gate | 從 story-point threshold 改成 plan approval 與 risk gate | [`KanbanModels.swift`](../../OpenMac/Domain/KanbanModels.swift) |
| Artifact／evidence contract | 保留型別化概念，改為 source-attributed `EvidenceFact` | [`KanbanModels.swift`](../../OpenMac/Domain/KanbanModels.swift) |
| Codex 串流、取消與事件解析 | 保留作 legacy/reference adapter 的實作素材，不作 v2 核心 contract | [`KanbanBoardExecutionSupport.swift`](../../OpenMac/ViewModels/KanbanBoardExecutionSupport.swift) |
| Git worktree 經驗 | 保留測試與命名邏輯；v2 的 lifecycle 由 backend 擁有且必須 fail closed | [`KanbanBoardViewModel+ExecutionRuntime.swift`](../../OpenMac/ViewModels/KanbanBoardViewModel+ExecutionRuntime.swift) |
| Xcode project 探測與 build verification | 優先抽成 `XcodeVerifier`，成為 Apple-specific 差異化 | [`KanbanBoardViewModel+ExecutionRuntime.swift`](../../OpenMac/ViewModels/KanbanBoardViewModel+ExecutionRuntime.swift) |
| Snapshot persistence | 保留舊資料讀取；v2 使用獨立 store 與 schema version | [`KanbanBoardStore.swift`](../../OpenMac/Domain/KanbanBoardStore.swift) |
| 英文／繁中與外觀基礎 | 保留既有能力，不增加新的字串面或語系 | [`AppLanguage.swift`](../../OpenMac/Localization/AppLanguage.swift) |

## 3. 立即凍結

以下領域維持相容，不再新增選項、畫面、模板或自動化：

- Kanban columns、拖拉、board templates 與 board-level automation。
- AgentProfile skills、capacity、load balancing 與 auto assignment。
- Story points、WIP limits、board health、epic、milestone 與 PM 報表。
- PM Autopilot quick templates 與 one-click flow。
- Shared Agent Memory 與 memory provider 擴充。
- Extension Marketplace、來源管理、更新頻道、UI contribution slots 與 hook ecosystem。
- PM Plugin API／Extension SDK 的新版本；只修重大安全或相容問題。
- Local Mock／OpenAI Compatible 設定頁的新增 provider 與 model 選項。
- Token／cost quota dashboard 的精細化。
- 新的語系、主題、sidebar widget、dashboard 或 observability panel。
- 現有 board-level GitHub PR 發布功能的擴充。
- 將更多狀態與動作加入 `ContentView.swift`。

## 4. 必須替換的 contract

| 舊 contract | v2 contract | 原因 |
|---|---|---|
| `Board → Column → WorkTask` | `DeliveryRun → DeliveryPlan → DeliveryTask → EvidenceFact` | Kanban 是 view，不是 runtime truth |
| 手動 `To Do/In Progress/Review/Done` | `DerivedDeliveryState` | 狀態必須來自 session、Git、verifier 與 PR facts |
| 文字中的 `Depends on:` | typed `DependencyEdge(fromID, toID)` | 文字解析不可靠、難以驗證與遷移 |
| 呼叫端各自提供 raw／resolved repository paths | 由檔案系統解析產生的 `DeliveryPlanningRepositoryContext`，非 fixture 使用前重驗 identity | 避免兩組路徑脫鉤與 symlink 改指後沿用 stale identity |
| 一次性 task execution record | `ExecutionAttempt + ExternalSessionRef` | 需要 session identity、重啟恢復與多次嘗試 |
| board root 建 branch 後 `git add -A` | 每個 task/attempt 的 branch 與 PR facts | 避免無關變更混入與 ownership 不清 |
| worktree 失敗後退回共用 workspace | fail closed | 隔離是安全邊界，不是最佳化選項 |
| transient execution timeline | durable、schema-versioned event/fact store | App 重啟後仍需重建真實狀態 |
| agent 說完成即成功 | evidence policy + human verification | 交付必須可驗證 |

## 5. 延後，不進兩週 vertical slice

- 第二個以上的真實 execution backend。
- 自建 daemon、terminal、worktree manager 或 SCM observer。
- 內嵌 terminal、完整 diff viewer、browser preview 或 Xcode replacement。
- GitHub issue intake、Linear/Jira/Slack 等 tracker 與通知整合。
- 自動處理 review feedback、merge conflict、merge 或 deployment。
- Cloud sync、multi-user collaboration、RBAC、distributed runners。
- Marketplace、第三方 verifier、通用 output artifact 生態系。
- AI 自動選 agent/model、token 最佳化或成本預測。
- 完整舊 board → v2 plan migration；vertical slice 只需新建 delivery run。
- README 全語系重寫與品牌更新；通過驗證後再做。

## 6. 驗證後的移除候選

只有在 v2 通過 repeat-usage gate、資料 migration 有測試且使用者確認後，才評估移除：

- 硬編碼固定 ticket 的 rule-based planner。
- 重複的 `Depends on:` parsers 與 placeholder dependency task。
- `autoRelaxWIPLimitsDuringRun` 及其他以展示層限制影響 runtime 的邏輯。
- AgentProfile 的 skills、capacity、workload 作為核心 schema。
- Story point、WIP、board health、epic 與 milestone 作為核心 schema。
- board-level `git add -A` PR flow。
- 預設 `danger-full-access` 與隔離失敗 fallback。
- 未宣告 permissions 仍能執行 shell 的 extension compatibility mode。
- quota/error 時自動退出或重啟 Codex app。
- 內建的特定工具／provider UI 特例。
- 預植 demo board、demo agents 與舊 onboarding。

移除前必須提供：舊 snapshot 備份、一次性 importer、dry-run 報告與可回復版本。Marketplace／extension 程式若確定停止，先標記 deprecated，再於下一個 major version 移除。

## 7. Vertical slice 的允許新增範圍

兩週內唯一允許的新產品面：

- `DeliveryRun`／typed plan／evidence 的獨立資料模型與 store。
- Brief → plan review → approve 的單一路徑。
- `ExecutionBackend` protocol、deterministic fixture 與一個 AO reference adapter。
- Attention-first delivery screen。
- `XcodeVerifier` 與 PR evidence reference。
- 安全的 stop、resume、reconcile 與 idempotent dispatch。
- 為上述路徑必要的 tests、最小 onboarding、安裝 build 與本機 funnel export。
