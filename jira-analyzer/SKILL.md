---
name: jira-analyzer
description: >
  當使用者提到任何 Jira 任務單號（例如 VIPOP-1234、分析 VIPOP-XXXXX、看一下 VIPOP-XXXXX）時，
  立刻觸發此 skill。自動透過 Atlassian MCP 讀取任務內容，並結合本地 codebase（透過 filesystem MCP）
  產出完整的中文技術分析報告。只要訊息中出現「VIPOP-」加上數字的格式，無論是「幫我分析」、
  「看一下」、「評估一下」、「這張票」等說法，都應該觸發此 skill。
compatibility: "需要 Atlassian MCP（讀取 Jira 任務）；建議同時啟用 filesystem MCP（自動讀取本地 codebase）"
---

# Jira 任務分析 Skill

## 目標

當使用者輸入包含 `VIPOP-XXXXX` 格式的任務單號時，自動：

1. 透過 Atlassian MCP 拉取任務詳細資料
2. 透過 filesystem MCP 瀏覽本地 codebase（若可用）
3. 產出一份完整的中文 Markdown 技術分析報告

---

## 執行步驟

### Step 1：擷取任務單號

從使用者訊息中識別 `VIPOP-\d+` 格式的任務單號（例如 `VIPOP-1234`）。

### Step 2：取得 Atlassian Cloud ID

使用 Atlassian MCP 的 `getAccessibleAtlassianResources` 取得 cloudId，再呼叫 `getJiraIssue` 取得任務完整資料。

擷取以下欄位（若存在）：
- `summary`：任務標題
- `description`：任務描述
- `issuetype`：任務類型（Bug / Story / Task / Sub-task 等）
- `status`：目前狀態
- `priority`：優先級
- `assignee`：負責人
- `reporter`：回報者
- `labels`：標籤
- `components`：影響元件
- `fixVersions`：目標版本
- `duedate`：截止日期
- `subtasks`：子任務
- `issuelinks`：相關連結（blocking / blocked by / relates to）
- `parent`：父任務（Epic 或 Story）
- `customfield_*`：任何自訂欄位（Sprint、Story Points 等）

### Step 3：瀏覽本地 Codebase（若 filesystem MCP 可用）

1. 呼叫 `filesystem:list_allowed_directories` 確認可存取的目錄
2. 呼叫 `filesystem:directory_tree` 取得專案結構概覽
3. 根據任務描述中提到的關鍵字（功能名稱、元件名稱、API 路徑等），使用 `filesystem:search_files` 定位相關檔案
4. 使用 `filesystem:read_file` 讀取最相關的 1～5 個檔案（優先讀取核心邏輯，避免讀取 lock 檔或 build 產物）

> 若 filesystem MCP 不可用，跳過此步驟，在報告的「調整細節」中標註「⚠️ 需手動提供相關程式碼」

### Step 3.5：偵測並爬取規格書（若有連結）

掃描 Jira ticket 的以下欄位，尋找規格書 URL：
- `description`（任務描述本文）
- `comment`（留言串）
- 任何 `customfield_*` 欄位

**URL 識別規則：**
- 含 `axshare.com` → Axure 規格書
- 含 `figma.com/file/` 或 `figma.com/proto/` → Figma 規格書

**若找到規格書連結，執行以下流程（需要 Playwright MCP）：**

#### ① 確認 Playwright MCP 可用

若 Playwright MCP 工具**不可用**，立即輸出以下提示並**終止整個分析流程**，不產出任何報告：

```
🚫 無法讀取規格書，分析中止

偵測到規格書連結：{url}
但 Playwright MCP 未啟用，無法爬取規格書內容。

請依以下步驟啟用後重試：
  claude mcp add --scope user playwright npx @playwright/mcp@latest

啟用後重新輸入分析指令即可。
```

#### ② 爬取規格書並驗證載入結果

```
1. playwright:browser_navigate(url)
2. playwright:browser_wait_for(time=3000)
3. playwright:browser_snapshot()             ← 驗證是否成功載入
```

檢查 snapshot 結果，若出現以下任一情況，**立即輸出錯誤提示並終止整個分析流程**：
- 頁面顯示登入表單 / 要求輸入密碼
- 頁面內容為空白或僅有 loading spinner
- 出現 403 / 404 / 存取被拒絕的錯誤訊息

```
🚫 無法讀取規格書，分析中止

規格書網址：{url}
原因：{具體原因，例如「頁面需要登入」、「頁面無法存取（403）」、「內容載入失敗」}

建議處理方式：
- 若需要登入：請先在瀏覽器中登入後，重新執行分析指令
- 若為存取權限問題：請確認連結是否已設為公開，或聯繫規格書擁有者
```

#### ③ 爬取所有頁面內容（載入成功後）

**Axure：**
```
4. 取得左側導覽列的頁面清單
5. 逐一點擊每個頁面節點：
   - playwright:browser_click(頁面節點)
   - playwright:browser_wait_for(time=1500)
   - playwright:browser_get_page_text()
   - 記錄頁面名稱 + 內容
6. 若頁面超過 20 頁，優先爬取含「首頁」「概覽」「流程」「背景」「目標」關鍵字的頁面
```

**Figma：**
```
4. playwright:browser_take_screenshot()
5. playwright:browser_get_page_text()
```

#### ④ 爬取結果的用途（成功後）

- 補充分析報告的「任務概要」與「影響範疇」
- 在報告中新增「## 11. 規格書摘要」區塊
- 額外產出 PRD 文件，存至 `./docs/prd/{ISSUE_KEY}-prd.md`
- 在報告結尾加上：`📄 PRD 文件已產出：./docs/prd/{ISSUE_KEY}-prd.md`

### Step 4：產出分析報告

依照下方的**報告格式**輸出完整 Markdown 報告。

---

## 報告格式

```markdown
# 🎫 VIPOP-XXXXX 任務分析報告

> **任務標題**：{summary}
> **類型**：{issuetype} ｜ **狀態**：{status} ｜ **優先級**：{priority}
> **負責人**：{assignee} ｜ **截止日期**：{duedate}

---

## 1. 任務概要

用 2～4 句話說明這張票的核心目的與背景，讓不熟悉此任務的人能快速理解。

---

## 2. 任務說明

條列或段落說明任務的具體要求、驗收條件（AC）、以及任何補充資訊。
忠實呈現 Jira 描述的內容，但以中文重新整理，程式碼片段維持原樣。

---

## 3. 前置條件 / 相依性

- **依賴任務**：列出 blocking issues 或 depends on（若有）
- **被依賴**：列出哪些任務在等這張完成（若有）
- **環境前提**：需要特定 feature flag、環境變數、第三方服務等（若有）
- 若無相依性，寫「無」

---

## 4. 難度評估

**難度等級**：🟢 簡單 / 🟡 中等 / 🔴 困難

**評估理由**：
- 說明為何給出此難度（涉及的系統複雜度、不確定性、跨團隊協作需求等）
- 列出讓這張票變複雜的因素（若有）

---

## 5. 調整細節

### 5-1. 可能涉及的檔案 / 模組

| 檔案路徑 | 調整原因 |
|---------|---------|
| `path/to/file.ts` | 說明為何需要修改此檔案 |

> 若已讀取本地 codebase，此處列出實際定位到的檔案。
> 若未能讀取，標註推測來源並提示使用者確認。

### 5-2. 調整內容說明

針對每個需修改的地方，說明：
- 目前的行為 / 現況
- 需要改成什麼
- 若有程式碼範例，附上簡短 snippet（以 diff 或一般 code block 呈現）

### 5-3. 新增 / 刪除項目

列出需要新增的檔案、API endpoint、資料庫欄位、設定項等（若有）。

---

## 6. 風險點

- 列出實作過程中最容易出錯或需要特別小心的地方
- 可能影響其他功能的副作用
- 需要特別注意的邊界條件或例外處理
- 若無明顯風險，寫「目前無明顯風險，建議 code review 時重點確認調整範圍」

---

## 7. 影響範疇

- **前端**：哪些頁面 / 元件受影響
- **後端**：哪些 API / Service / DB 受影響
- **其他服務**：是否影響第三方整合、通知、排程任務等
- **使用者影響**：終端使用者會感受到什麼變化（若有）

---

## 8. 測試方式

### 手動測試
1. 條列具體的測試步驟
2. 包含正常流程與異常情境

### 自動化測試
- 建議新增 / 修改哪些 unit test 或 integration test
- 若有現有測試需更新，指出檔案位置

---

## 9. 預計調整時間

| 情境 | 預估時間 |
|-----|---------|
| 🟢 樂觀（一切順利） | X 小時 / X 天 |
| 🔴 悲觀（遇到複雜問題） | X 小時 / X 天 |
| 📅 建議預留時間 | X 小時 / X 天 |

**說明**：解釋影響時間估算的主要因素。

---

## 10. 優先級與排程建議

- **Jira 優先級**：{priority}
- **目標版本 / Sprint**：{fixVersions / sprint}
- **排程建議**：根據難度、相依性、截止日期，給出何時開始處理的建議

---

## 11. 規格書摘要（若爬取成功）

> 此區塊僅在 Step 3.5 成功爬取規格書後出現

**規格書來源**：{url}

### 主要頁面清單
列出爬取到的所有頁面名稱。

### 核心功能摘要
用 3～5 點條列規格書描述的核心功能。

### 與 Jira ticket 的關聯
說明規格書內容如何對應到這張 ticket 的需求，指出有無落差或補充資訊。

### 開放問題
列出規格書中不明確或需進一步確認的地方。

📄 **完整 PRD 文件**：`./docs/prd/{ISSUE_KEY}-prd.md`

---

*報告產生時間：{timestamp}*
*資料來源：Jira {issue_key} + {codebase_source} + {spec_url}*
```

---

## 注意事項

- 報告語言：**中文為主，程式碼 / 路徑 / 專有名詞維持原樣**
- 若 Jira 描述不足以推斷某個分析項目，誠實標註「資訊不足，建議與 PM / 開發者確認」，不要捏造
- 讀取 codebase 時，**優先讀取核心業務邏輯**，跳過 `node_modules`、`.git`、`dist`、`build`、`*.lock` 等目錄
- 任務難度評估要給出具體理由，不能只寫等級
- 時間預估要考量：程式碼複雜度、測試時間、code review 時間、可能的 QA 回饋修改

---

## 範例觸發語句

以下訊息都應觸發此 skill：

- `分析 VIPOP-1234`
- `幫我看一下 VIPOP-567`
- `VIPOP-890 這張要怎麼做`
- `評估一下 VIPOP-1111 的難度`
- `VIPOP-2024 的工作量大概多少`
