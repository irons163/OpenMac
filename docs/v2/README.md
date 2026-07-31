# OpenMac v2

> 狀態：VS-01～VS-06、VS-10 已完成；VS-07～VS-09 本機 contracts 已完成，待真實 AO daemon／dashboard／permission／workspace identity smoke test
> 更新日期：2026-07-31

OpenMac v2 的定位是：

> **Apple/Xcode 開發的 spec-to-verified-PR 交付層。**

它不複製 Agent Orchestrator（AO），也不再以通用 Kanban／PM 工具作為主產品。OpenMac 負責把 feature brief 轉成可批准的 typed dependency plan，交給隔離的 coding-agent sessions 執行，再用 Xcode build/test 與 PR facts 驗證結果。AO 是第一個可選的 reference backend，不是產品硬依賴。

目前 AO adapter 只依賴 slice 所需的 daemon contract，並將相容版本固定在
`0.1.0-route-shell`。Captured fixtures 取自
[`Untrivial-ai/agent-orchestrator`](https://github.com/Untrivial-ai/agent-orchestrator)
revision `9caafbee89383c9bf7e904936eb88c48add2fa88`；本機尚未安裝或啟動 AO，
因此不宣稱已完成真實 session smoke test。

VS-08 已能從 persisted session mapping 自動或手動 reconcile，對相同 AO
snapshot 去重，將 backend outage／未知狀態顯示為 `Needs You`，並把 stop
acknowledgement 與後續明確的 stopped fact 分開保存。AO dashboard 位址可能由
部署設定改變；在取得可驗證設定前不猜測 deep-link。

VS-09 的 `XcodeVerifier` 只接受 backend-confirmed workspace，並在執行前核對
Git common directory、branch 與 container identity。它不經 shell 拼接參數，
會保存 scheme、command、exit status、摘要、時間與 `.xcresult`；真實 Swift
package smoke 已產生可 round-trip 的 build record。Captured AO API 尚未提供
workspace path，因此 AO session 不會被錯誤地拿原始 repo 代替驗證。

VS-10 將 resume 與 retry 分成兩個明確語意：未綁定 session 的 reservation
以同一 idempotency key 安全重播；terminal failed／stopped task 的人工 Retry
才會原子建立 sequence+1 的新 attempt。Stale retry、已有 downstream attempt、
權限為 `unknown` 或 `danger-full-access` 都會在啟動 session 前 fail closed。
Control Center 也可匯出本機 funnel JSON；檔案只含里程碑 duration、狀態與
計數，明確排除 brief／prompt、repository path、branch／commit、command／log
及 PR URL。

本目錄包含三份執行文件：

- [產品規格](PRODUCT_SPEC.md)：目標使用者、核心流程、資料邊界、MVP 與驗證指標。
- [功能凍結清單](FEATURE_FREEZE.md)：哪些既有能力保留、凍結、替換、延後或列為移除候選。
- [兩週 vertical slice backlog](VERTICAL_SLICE_BACKLOG.md)：單人、十個工作日的交付順序與決策閘門。

在 Day 10 決策閘門通過前：

- 不改寫現有 README 的產品承諾。
- 不刪除舊 Kanban 資料或相容程式。
- 不增加新的 Marketplace、PM、AgentProfile 或語系功能。
- 不 fork AO，也不把 AO 原始碼搬進 OpenMac。
