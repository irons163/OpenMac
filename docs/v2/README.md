# OpenMac v2

> 狀態：VS-01～VS-07、VS-09～VS-11 已完成；VS-08 dashboard deep-link 尚待完成（AO workspace identity、Xcode build 與 PR facts 已驗證）
> 更新日期：2026-08-02

本輪範圍決策：跳過乾淨 Mac 的 Gatekeeper onboarding，以及受測者／concierge 驗證。它們仍可在未來 validation window 執行，但不再是本輪完成門檻。

OpenMac v2 的定位是：

> **Apple/Xcode 開發的 spec-to-verified-PR 交付層。**

它不複製 Agent Orchestrator（AO），也不再以通用 Kanban／PM 工具作為主產品。OpenMac 負責把 feature brief 轉成可批准的 typed dependency plan，交給隔離的 coding-agent sessions 執行，再用 Xcode build/test 與 PR facts 驗證結果。AO 是第一個可選的 reference backend，不是產品硬依賴。

目前 AO adapter 只依賴 slice 所需的 daemon contract，並將相容版本固定在
`0.1.0-route-shell`。Captured fixtures 取自
[`Untrivial-ai/agent-orchestrator`](https://github.com/Untrivial-ai/agent-orchestrator)
revision `9caafbee89383c9bf7e904936eb88c48add2fa88`。另已對 upstream revision
`b58bae51bac08c9e48bded4c636e504863a93c21` 的隔離 daemon 通過 health、
served OpenAPI 與 project discovery；早期測試因缺少 AO runtime 要求的 `tmux`
而在 upstream preflight 停止。2026-08-02 安裝 `tmux 3.7b` 後，使用 AO desktop
daemon 與 disposable fake-harness project 完成 session start、facts 與 stop
acknowledgement smoke。Connection screen 會安全讀取 `~/.ao/running.json`，依序
檢查 health、readiness 與 served OpenAPI，要求兩個 daemon probes 回報相同
PID、有 run-file 時也必須與其 PID 相符，並確認 adapter 使用的必要 API
operations 都存在。後續操作會先重新確認 daemon PID；若手動 URL 背後的
process 已替換，新的 daemon 必須重新通過完整 OpenAPI probe。手動 URL 仍只
接受 loopback；discovered connection 遇到不同 PID 則拒絕並要求重新探索，
不會沿用舊 run-file identity。並行 reconciliation 會共用同一個進行中的
identity probe，首次並行操作也會共用完整的 health、readiness 與 OpenAPI
compatibility probe，避免 sessions 數量放大 traffic；失敗的共享 probe 不會被
快取；無論失敗發生在首次完整 probe 或後續 identity probe，daemon 恢復後的
下一次操作都會重新執行完整 compatibility check。
AO session start 也會在 adapter 邊界拒絕 `unknown` 或 `dangerFullAccess`
權限，不會先送出 project、session 或 spawn request。
恢復既有 session 時也會重新核對 session／project identity、固定 branch、worker
kind、harness 與建立時間；不完整 receipt 會 fail closed。
已終止的 session stop 只保存 `alreadyTerminal` acknowledgement，不會重送 kill
或假裝取得了新的 stopped fact。
AO project／execution identifiers 也必須是單一安全 URL path component；`/`、`\`
與 `.`／`..` segment 會在送出 compatibility probe 前拒絕。

VS-08 已能從 persisted session mapping 自動或手動 reconcile，對相同 AO
snapshot 去重，將 backend outage／未知狀態顯示為 `Needs You`，並把 stop
acknowledgement 與後續明確的 stopped fact 分開保存。AO dashboard 位址可能由
部署設定改變；2026-08-02 已完成 AO daemon PID `8874 → 11085` 的重啟後
compatibility smoke。Control Center 已補 scene-active reload/reconcile，且
deterministic restart test 會用新的 model instance 驗證 persisted facts 不重播；
packaged test.2 已通過 `tools/test-packaged-app-restart.sh` 的 launch →
terminate → relaunch → terminate smoke；取得可驗證設定前的 dashboard deep-link
仍待完成，不猜測 URL。另對 upstream `main` revision
[`9159a020`](https://github.com/Untrivial-ai/agent-orchestrator/tree/9159a0206a2e1d2a99333118bf9ebc5590b7404f)
重新核對：其 desktop dashboard 仍不是 daemon 的 HTTP route，session view
仍沒有可供外部 app 使用的 dashboard URL；`/preview` 只代表瀏覽器 preview。

VS-09 的 `XcodeVerifier` 只接受 backend-confirmed workspace，並在執行前核對
Git common directory、branch 與 container identity。它不經 shell 拼接參數，
會保存 scheme、command、exit status、摘要、時間與 `.xcresult`；真實 Swift
package smoke 已產生可 round-trip 的 build record。AO 的
`ControllersSessionView` 仍把 `workspacePath` 留在 daemon 內部 metadata，未
直接暴露到 session response；對支援的 served contract，adapter 會透過官方
`POST /api/v1/shell-terminals` 取得 `workingDir`，核對 project／session identity
與 absolute path 後立即以 `DELETE` 釋放暫時 terminal，再保存
`verificationWorkspaceURL`。shell-terminal endpoint 缺失、回應不合法或清理失敗
都會 fail closed，因此不會把原始 repo 冒充隔離 workspace。AO live smoke 已驗證
此路徑；另以 disposable AO workspace 實際跑過 `XcodeVerifier` 的 Swift package
build，並以 AO 官方 PR claim endpoint 綁定公開 PR 後驗證 URL、open state、CI
與 review facts 由同一個 execution identity 傳入。PR creation／push／merge
仍未由 smoke 執行。

VS-10 將 resume 與 retry 分成兩個明確語意：未綁定 session 的 reservation
以同一 idempotency key 安全重播；terminal failed／stopped task 的人工 Retry
才會原子建立 sequence+1 的新 attempt。Stale retry、已有 downstream attempt、
權限為 `unknown` 或 `danger-full-access` 都會在啟動 session 前 fail closed。
Control Center 也可匯出本機 funnel JSON；檔案只含里程碑 duration、狀態與
計數，明確排除 brief／prompt、repository path、branch／commit、command／log
及 PR URL。

VS-11 的目前測試版本為 `0.1.0 (2)`、最低 macOS 14，產出 arm64／x86_64
universal zip 與 SHA-256。由 clean commit
`65618e6` 產生的 archive（SHA-256
`d4e2020f2ebecaeaad3061c0f8b2b06881b43a2e4d3e68eab5607c7bfde5f553`）已通過 checksum、
封裝前後簽章、架構與本機 launch smoke。Release build 以獨立 feature flag
開啟 v2 畫面，另有安全 AO discovery 與 compatibility／project discovery
probe。測試包使用 OpenMac Evaluation License、ad-hoc hardened-runtime 簽章
且未 notarized；乾淨 Mac Gatekeeper onboarding 依本輪範圍決策延後，不影響本機技術 slice 的完成判定。

本目錄包含六份執行文件：

- [產品規格](PRODUCT_SPEC.md)：目標使用者、核心流程、資料邊界、MVP 與驗證指標。
- [功能凍結清單](FEATURE_FREEZE.md)：哪些既有能力保留、凍結、替換、延後或列為移除候選。
- [兩週 vertical slice backlog](VERTICAL_SLICE_BACKLOG.md)：單人、十個工作日的交付順序與決策閘門。
- [測試 build 安裝指南](TEST_BUILD_INSTALL.md)：checksum、Gatekeeper、五分鐘 fixture walkthrough 與 AO connection probe。
- [AO live smoke](AO_LIVE_SMOKE.md)：對既有 loopback daemon 執行 opt-in adapter compatibility 與明確授權的 isolated-session smoke。
- [Concierge validation](CONCIERGE_VALIDATION.md)：test.2 招募條件、30 分鐘觀察腳本、紀錄模板與早期停止條件（本輪延後）。

在 Day 10 決策閘門通過前：

- 不改寫現有 README 的產品承諾。
- 不刪除舊 Kanban 資料或相容程式。
- 不增加新的 Marketplace、PM、AgentProfile 或語系功能。
- 不 fork AO，也不把 AO 原始碼搬進 OpenMac。
