# OpenMac v2：兩週 Vertical Slice Backlog

> 期間：10 個工作日
> 人力假設：1 位開發者
> 目標：證明 Apple/Xcode 的 brief → approved plan → isolated sessions → verified PR 閉環

> 範圍決策（2026-08-02）：本輪跳過乾淨 Mac 的 Gatekeeper onboarding 與受測者／concierge 驗證。兩者保留為未來 validation，不列入本輪完成門檻；本輪只追蹤目前環境可驗證的程式、contract、fixture 與 AO live prerequisites。

## 目前進度（2026-08-02）

- [x] VS-01：獨立 delivery domain、內容綁定 approval fingerprint、關聯驗證與具 compare-and-swap 的 versioned store。
- [x] VS-02：backend-neutral execution contract、deterministic fixture、可重播 facts、游標／stop／fault／cancellation 行為。
- [x] VS-03：backend-neutral planning contract、strict structured response、local keys → typed UUID edges、deterministic Apple/Xcode fixture、可信 repository identity snapshot、可保存並修正的 invalid draft、持久化 generation blockers，以及綁定 store revision 的 atomic stale-result apply guard。
- [x] VS-04：Debug-only 獨立 plan review window、完整 typed plan 編輯、deterministic waves／risk／session 摘要、原子 draft save／approval、store 與 plan 雙 CAS、跨程序 file lock、schema v1 → v2 fail-closed migration，以及零 execution backend calls 的 fixture bootstrap。Approval scope 綁定整份 brief、plan hash、reviewer/time、canonical Git common-directory 與 planning 前固定的 base commit；落盤與批准都會重新驗證 identity。
- [x] VS-05：只 dispatch 當前 ready wave；先原子保存 task → attempt reservation 與 project/idempotency identity，再並行呼叫具隔離保證的 backend，最後綁定 session receipt。未綁定 reservation 可在重啟後安全重播；並行／重複 dispatch 共用同一批 attempt，start failure 保留可重試原因且不建立 ghost attempt；stop-future-dispatch 會阻止後續 wave。
- [x] VS-06：新增 Debug-only 獨立 Delivery Control Center（`⌥⌘D`），依 persisted backend observations、cursor、attempt、evidence 與 PR facts 衍生 `Needs You`／Running／Verifying／`Ready to Merge`。Fixture loop 可依 DAG 自動跑完 happy path；blocked、failed、missing evidence 都保留原因與下一步，未知或失敗 facts 不會被顯示為完成。
- [ ] VS-07：AO reference adapter 已完成 health／readiness／served OpenAPI version 與必要 operation 驗證、project selection、idempotent start、snapshot facts 與 stop 的隔離實作；27 個 captured contract tests 固定於 upstream revision `9caafbee89383c9bf7e904936eb88c48add2fa88`，並覆蓋 snapshot 去重、未知狀態 fail-closed、明確 terminated mapping、尚未 ready 時停止 compatibility probe、缺少必要 API operation 時降級、首次併發操作共用完整 compatibility probe、快取相容性前重新確認 daemon identity、併發操作共用 in-flight identity probe、完整或 identity 共享 probe 失敗後重新執行完整 compatibility check、unsafe permission scope 在任何 AO side effect 前拒絕、existing session receipt identity 驗證、terminal stop 不重送 kill、unsafe project／execution path identifier 在任何 request 前拒絕、手動 URL 替換 PID 後重跑完整 probe、discovered connection 替換 PID 後要求重新探索，以及 health／ready／discovery PID 不一致時 fail closed。另依 upstream `b58bae51bac08c9e48bded4c636e504863a93c21` 的 `~/.ao/running.json` 契約新增安全本機探索：拒絕 symlink、非本人擁有、可被 group／other 寫入、過大、格式錯誤或 stale PID 的檔案，只建立 `127.0.0.1` URL，且不讀取或保存 browser runtime token。真實隔離 daemon 已通過 health、ready、served OpenAPI 與 project discovery；session spawn 因本機缺少 AO 要求的 `tmux` 而在 upstream preflight 停止，沒有建立 session，故不把 ticket 或 MVP 真實 backend 條件標成完成。
- [ ] VS-08：已保存 reconcile failure 與 stop acknowledgement，Control Center 對可恢復 backend 會在重啟載入時 reconcile，也可手動重試；相同 AO snapshot 不重播 facts，backend down／未知狀態顯示 `Unknown`／`Needs You`，stop receipt 不會假裝 session 已終止。尚欠可設定且驗證過的 AO dashboard deep-link，以及在 live daemon 上完成 restart／stop smoke。
- [ ] VS-09：已新增獨立 `XcodeVerifier`、Control Center 驗證動作與 atomic evidence persistence；執行前核對 backend-confirmed workspace、branch、Git common directory 與 container，命令以 argument array 啟動並保存 scheme、command、exit status、bounded summary、時間及 `.xcresult`。真實 Swift package smoke 已產生並 round-trip 保存 build record；失敗 evidence 會立即進 `Needs You` 且不能成為 `Ready to Merge`。AO captured contract 未提供 workspace path，因此 AO local verification 維持 fail-closed，尚待 upstream 可驗證 identity 或 live backend 路徑。
- [x] VS-10：terminal failed／stopped task 可由明確 Retry 建立 sequence+1、全新 idempotency key 的 isolated attempt；舊 reservation resume 仍重用原 key。Retry 以 expected latest-attempt identity、file lock 與 CAS 防止重複，已有 downstream attempt 時 fail closed。Dispatch project 現在必須明確保證 workspace read/write permission，`unknown`／`danger-full-access` 都在建立 reservation 前拒絕。Control Center 可匯出去識別化本機 funnel JSON，只含里程碑 duration／計數／衍生狀態，不含 brief、prompt、路徑、branch／commit、command／log 或 PR URL。
- [x] VS-11：已決定 invited-evaluator license、版本 `0.1.0 (2)` 與最低 macOS 14；Release feature flag 會包含 v2 review、control center 與安全 AO discovery／connection probe。封裝工具會拒絕未 commit 的 source，產出 arm64／x86_64 zip、SHA-256、build metadata，並在封裝前後嚴格驗證 ad-hoc hardened-runtime 簽章。由 commit `84610a2db899926939271193a37e2e70a2efa2b0` 產生的 clean-source test.2 archive 已通過 checksum、解壓、簽章與 launch smoke；乾淨測試機 Gatekeeper onboarding 依本輪範圍決策延後，不阻塞此 ticket。
- [ ] 下一步：在具 AO runtime prerequisites 的環境完成 explicit isolated-session smoke，再取得 verification workspace identity 並跑 Xcode／PR E2E。乾淨 Mac 與受測者／concierge 驗證已明確延後，不阻塞本輪技術進度。

VS-01～VS-11 contract path 目前由 151 個測試覆蓋，其中 Xcode verifier suite 包含一個真實 Swift package `xcodebuild` smoke；AO discovery suite 以 8 個 deterministic tests 覆蓋有效檔案、missing、stale、invalid identity、writable、oversized、malformed timestamp 與 symlink，install-readiness suite 也驗證 discovery PID 會綁定 connection probe。Xcode 26 的 hosted runner 在本機會卡在 worker materialization，這是 runner 層問題，未算作產品測試通過。測試不啟動真實 Codex 或 AO，也未改動舊 Kanban schema。初始 generation 以 3–5 tasks 作為品質目標；編輯後的產品 plan 允許 3–7 tasks，approval eligibility 一律從目前 typed plan 與未解 generation blockers 重算。

## 1. Slice 完成畫面

到 Day 10，使用者應能：

1. 選擇一個真實 Xcode Git repository。
2. 輸入一段 feature brief，得到 3–5 個 typed dependency tasks。
3. 修改並批准 plan；批准前沒有外部 side effect。
4. 以 fixture 或 AO reference backend 建立隔離 sessions。
5. 從 `Needs You` 畫面處理 blocked／failed／missing evidence。
6. 看到真實 `xcodebuild`／test 與 PR facts。
7. 在所有必要證據成立後得到 `Ready to Merge`，再由人決定是否合併。

所有開發以 feature flag 與獨立 feature boundary 進行。舊 Kanban 只提供入口，不承擔 v2 狀態。

## 2. 優先序與 cut line

- **P0**：沒有它就不能證明核心假設。
- **P1**：能降低測試摩擦，但失敗時可用清楚的人工步驟替代。
- Day 5 前只做 fixture-first 的完整 loop；通過 Gate A 才接真實 AO。
- 不可為了 AO 相容性自建 daemon、fork AO 或把邏輯塞回舊 ViewModel。

## 3. 十日工作表

| 日 | Ticket | P | 交付內容 | 依賴 | Definition of Done |
|---|---|---:|---|---|---|
| 1 | VS-01：Delivery domain | P0 | 建立 `DeliveryRun`、`DeliveryPlan`、`DeliveryTask`、typed edge、acceptance、evidence、attempt、session ref 與 derived state；使用獨立 versioned store | 無 | 單元測試涵蓋 encode/decode、missing reference、cycle、duplicate edge、空 acceptance/evidence；不修改舊 board schema |
| 1 | VS-02：Fixture backend contract | P0 | 定義最小 `ExecutionBackend`：health、list projects、start、facts、stop；建立 deterministic fixture scenarios | VS-01 | 測試可重現 queued/running/blocked/failed/ready、延遲與 malformed facts；UI 測試不啟動真實 Codex/AO |
| 2 | VS-03：Brief → typed plan | P0 | 重用 planner 基礎產生 3–5 tasks；先接受 deterministic fixture/structured response，拒絕文字 `Depends on:` 作為 source of truth | VS-01 | 一個 Xcode brief 可產生合法 DAG；每個 task 都有 acceptance、risk、evidence 與 target/scheme hint；錯誤可編輯且不 crash |
| 3 | VS-04：Plan review 與 approval | P0 | 新增獨立 review screen，支援改 title/prompt/acceptance/dependencies；顯示 waves、風險與 session 數 | VS-03 | cycle、dangling edge、空欄位會阻止 Approve；批准記錄 plan hash/time；批准前 fixture 計數證明零 backend calls |
| 4 | VS-05：Idempotent dispatch | P0 | 只 dispatch ready wave；保存 task → attempt → session mapping；derived state reducer 與 stop-future-dispatch | VS-02、VS-04 | 3-task DAG 會先啟動 2 個平行 task、完成後才啟動第 3 個；重複點擊或 App restart 不重複建立 session；backend/隔離錯誤 fail closed |
| 5 | VS-06：Attention-first fixture loop | P0 | 一個新 top-level delivery screen，分成 `Needs You`、Running、Verifying、`Ready to Merge`；動作只保留 retry/stop/open source | VS-05 | 完整 fixture demo 在 5 分鐘內走完 brief → `Ready to Merge`；blocked、failed、missing evidence 各有明確原因與下一步；通過 Gate A |
| 6 | VS-07：AO reference adapter spike | P0 | 僅實作 slice 所需的 health/version、project selection、start session 與 facts；所有 DTO 隔離於 adapter | VS-02、Gate A | 對 captured fixtures 有 contract tests；可連線一個相容 AO daemon 並建立 1 個 session；不把 AO 型別洩漏到 domain/UI；不相容時顯示版本與可行動錯誤 |
| 7 | VS-08：AO reconcile 與 attention | P0 | 輪詢／訂閱必要 facts，映射 running/blocked/failed/ready；restart reconcile；deep-link 到 AO 處理 terminal/follow-up | VS-05、VS-07 | App restart 後恢復 mapping、沒有 duplicate dispatch；未知 AO state 顯示 Unknown/Needs You，不假裝成功；stop 會停止後續 dispatch，外部 session 終止須明確確認 |
| 8 | VS-09：Xcode 與 PR evidence | P0 | 從既有 runtime 抽出 `XcodeVerifier`；保存 scheme、command、exit status、摘要、時間；接收 backend PR ref/check facts | VS-05；真實 AO 路徑需 VS-08 | 至少一個真實 sample repo 產生 build/test evidence；失敗會阻止 `Ready to Merge`；PR identity 與 attempt 對得上；無 PR API 時可貼 URL，但不得手填「checks passed」 |
| 9 | VS-10：Recovery、安全與測試 | P0 | 補齊 resume、retry attempt、malformed input、權限與 fail-closed 測試；避免 live process 測試；加入本機 funnel export | VS-05、VS-08、VS-09 | 測試不會呼叫真實 Codex/AO；restart、duplicate event、stale fact、backend down、xcodebuild fail 都有 deterministic coverage；預設不是 `danger-full-access` |
| 9 | VS-11：可安裝測試 build | P1 | 決定 license、最低 macOS、版本號；產出不需 Xcode 的 zip/dmg，提供最短 onboarding | VS-10 | test.2 archive 通過 checksum、簽章、架構與本機 launch smoke；未有簽章 credentials 時明確標示測試安裝步驟，不宣稱 notarized；乾淨測試機 Gatekeeper 驗證延後 |
| 10 | VS-12：真實 E2E 與 Gate B（延後） | P0 | 在真實 Xcode repo 跑 3+ task plan，至少 2 個平行 sessions；執行 verification、連到 PR；受測者／concierge tests 依範圍決策延後 | VS-07–VS-11 | 一次完整 AO run 可重現且有 event/evidence export；workspace identity、Xcode evidence 與 PR facts 可核對；受測者訊號與 Gate B 延後，不列入本輪完成判定 |

## 4. 每日並行的使用者驗證工作（延後）

本節本輪不執行；保留為未來 validation window 的招募與觀察清單，不阻塞技術 slice。

- Day 1：寫一頁 screener，只招募每週同時跑 3+ coding sessions 的 Apple developers。
- Day 2：發出 20 個精準邀請，不做大眾 launch。
- Day 3–4：排定至少 5 場 Day 6–10 concierge sessions，收集真實 briefs。
- Day 5：用 fixture prototype 讓 2 位目標使用者完成 think-aloud；只修阻斷核心 loop 的問題。
- Day 6–9：每天至少一個真實 repo run，保存計畫改寫比例與人工介入點。
- Day 10：完成 3–5 場可觀察測試，啟動七天 repeat-usage window。

## 5. Day 5：Gate A

全部成立才開始真實 AO integration：

- fixture loop 能在五分鐘內完成 brief → 3 tasks running → blocked → evidence → `Ready to Merge`。
- plan 使用 typed dependencies，cycle 與 dangling edge 會阻止批准。
- 批准前零 side effects，重複 dispatch 不建立第二個 session。
- `Needs You` 能讓測試者不看 terminal 就說出問題與下一步。
- v2 domain/UI 沒有依賴舊 Kanban column 或 AgentProfile 作為真實狀態。
- 沒有把新 orchestration 邏輯加入 `ContentView.swift` 或巨型 ViewModel。

若未通過：停止 AO integration，先縮小 plan editor、狀態 reducer 或 evidence contract；不以增加 UI 功能掩蓋 contract 問題。

## 6. Day 10：Gate B（延後）

本輪不以 Gate B 的受測者與 repeat-use 條件作為完成門檻；以下條件保留給未來公開 validation window。

進入公開 validation window 前必須成立：

- 一個真實 Xcode repo 完成 3+ task plan，至少 2 個 session 平行且互相隔離。
- App restart 後可 reconcile，沒有 duplicate session 或錯誤完成狀態。
- 至少一筆真實 build/test evidence 與正確 PR identity。
- 缺 evidence、CI failure、blocked 或 unknown state 都不能顯示 `Ready to Merge`。
- AO adapter 只使用少量、可測、版本檢查過的 contract；目前整合成本不超過本 slice 的 30%。
- 有可安裝測試 build、license 決策與最短 onboarding。
- 至少 3 位目標使用者能在一次引導內完成 loop，且至少 2 位明確願意在自己的下一個需求再使用。

任一核心條件失敗：不增加 backend、Marketplace、dashboard 或自動化。先判斷是產品摩擦、plan 品質，還是 backend 不穩；只選一個問題進下一輪。

## 7. 明確不做

- Fork／內嵌 AO 或追平其 adapters。
- 自建 daemon、tmux/terminal、worktree manager、GitHub observer。
- 第二個真實 execution backend。
- Kanban redesign、AgentProfile routing、story points、WIP 或 board health。
- Extension Marketplace、plugin SDK、MCP registry 或 shared-memory 擴充。
- 內嵌 terminal、完整 diff、browser preview、issue intake。
- 自動 merge、review 修復、部署、雲端同步、團隊權限。
- 新語系、全 README 改版、行銷網站或大眾 launch。

## 8. 七天 Validation Window（延後）

本輪不啟動七天 validation window；相關指標保留作為未來是否擴建的判斷依據。

Day 10 後只修 end-to-end blocker，依 [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) 的 Go／Stop 指標判斷：

- 是否有 5 位完成一次、3 位七天內重複使用；
- 是否達到 15 sessions、6 merged PRs；
- brief 到 3 sessions running 是否低於五分鐘；
- 是否至少 2 位願意付費、贊助或參與付費 pilot。

未達 Stop 門檻就停止擴建，而不是再加功能。
