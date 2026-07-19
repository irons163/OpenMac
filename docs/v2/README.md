# OpenMac v2

> 狀態：VS-01～VS-03 已完成，下一步為 plan review／approval
> 更新日期：2026-07-19

OpenMac v2 的定位是：

> **Apple/Xcode 開發的 spec-to-verified-PR 交付層。**

它不複製 Agent Orchestrator（AO），也不再以通用 Kanban／PM 工具作為主產品。OpenMac 負責把 feature brief 轉成可批准的 typed dependency plan，交給隔離的 coding-agent sessions 執行，再用 Xcode build/test 與 PR facts 驗證結果。AO 是第一個可選的 reference backend，不是產品硬依賴。

本目錄包含三份執行文件：

- [產品規格](PRODUCT_SPEC.md)：目標使用者、核心流程、資料邊界、MVP 與驗證指標。
- [功能凍結清單](FEATURE_FREEZE.md)：哪些既有能力保留、凍結、替換、延後或列為移除候選。
- [兩週 vertical slice backlog](VERTICAL_SLICE_BACKLOG.md)：單人、十個工作日的交付順序與決策閘門。

在 Day 10 決策閘門通過前：

- 不改寫現有 README 的產品承諾。
- 不刪除舊 Kanban 資料或相容程式。
- 不增加新的 Marketplace、PM、AgentProfile 或語系功能。
- 不 fork AO，也不把 AO 原始碼搬進 OpenMac。
