---
name: spec-to-prd
description: >
  當使用者提供規格書連結（Axure Share URL、Figma URL）並要求產出 PRD 文件時，立刻觸發此 skill。
  自動透過 Playwright MCP 爬取規格書內容，整理成標準 PRD Markdown 文件並存檔。
  觸發語句包含但不限於：「幫我把這份規格書整理成 PRD」、「爬這個 Axure 連結產出需求文件」、
  「這個 Figma 連結幫我整理成 PRD」、「把規格書轉成 PRD」。
  也會被 jira-analyzer skill 在偵測到 Jira ticket 含有規格書連結時自動呼叫。
compatibility: "需要 Playwright MCP（爬取規格書頁面）；建議同時啟用 filesystem MCP（存檔 PRD）"
---

# Spec to PRD Skill

## 目標

接收規格書連結（Axure Share / Figma），透過 Playwright MCP 爬取所有頁面內容，
產出一份標準 PRD Markdown 文件，並透過 filesystem MCP 存至本地。

---

## 支援的規格書類型

| 類型 | URL 特徵 | 爬取策略 |
|------|---------|---------|
| Axure Share | `*.axshare.com` | 需等待 JS 渲染，逐頁抓取側邊欄導覽 |
| Figma | `figma.com/file/` 或 `figma.com/proto/` | 截圖 + 文字節點擷取 |

---

## 執行步驟

### Step 1：解析連結類型

從使用者訊息或 Jira ticket 描述中擷取規格書 URL，判斷類型：
- 含 `axshare.com` → Axure 流程
- 含 `figma.com` → Figma 流程

若同時有多個連結，逐一處理後合併輸出。

---

### Step 2：爬取規格書內容

> **⛔ 重要：若 Playwright MCP 不可用，或爬取過程中任何一個關鍵驗證失敗，立即停止整個流程並輸出錯誤提示，不繼續產出 PRD。**

#### 前置檢查：確認 Playwright MCP 可用

在開始爬取前，先確認 Playwright MCP 工具是否可呼叫。

**若 Playwright MCP 不可用（工具不存在）：**

```
🚫 無法讀取規格書

Playwright MCP 未啟用，無法爬取規格書內容。
請依以下步驟啟用後重試：

  claude mcp add --scope user playwright npx @playwright/mcp@latest

啟用後重新執行此指令即可。
```
**→ 立即停止，不繼續任何後續步驟。**

---

#### Axure Share 爬取流程

```
1. playwright:browser_navigate(url)
2. playwright:browser_wait_for(time=3000)    ← 等待 JS render
3. playwright:browser_snapshot()             ← 驗證頁面是否成功載入
```

**載入驗證（關鍵）：**
檢查 snapshot 結果是否包含 Axure 的頁面導覽結構或內容區塊。

若出現以下任一情況，**立即停止並輸出錯誤提示**：
- 頁面顯示登入表單 / 要求輸入密碼
- 頁面內容為空白或僅有 loading spinner
- 出現 403 / 404 / 存取被拒絕的錯誤訊息
- 頁面標題或內容顯示非預期的錯誤頁

```
🚫 無法讀取規格書

原因：{具體原因，例如「頁面需要登入」、「頁面無法存取（403）」、「內容載入失敗」}
規格書網址：{url}

建議處理方式：
- 若需要登入：請先在瀏覽器中登入 Axure Share，再重新執行
- 若為存取權限問題：請確認連結是否已設為公開，或聯繫規格書擁有者
- 若為網路問題：請確認網路連線後重試
```
**→ 立即停止，不繼續任何後續步驟。**

載入成功後繼續：
```
4. 找到左側導覽列（頁面清單）
5. 逐一點擊每個頁面節點：
   - playwright:browser_click(頁面節點)
   - playwright:browser_wait_for(time=1500)
   - playwright:browser_get_page_text()
   - 記錄頁面名稱 + 內容
6. 重複直到所有頁面完成
```

**Axure 注意事項：**
- Hash routing（`#id=xxx&p=xxx`）代表不同頁面，點擊後 URL 會變化
- 優先使用 `get_page_text()` 取文字，複雜互動元件用 `browser_snapshot()`

---

#### Figma 爬取流程

```
1. playwright:browser_navigate(url)
2. playwright:browser_wait_for(time=3000)    ← 等待 canvas 載入
3. playwright:browser_snapshot()             ← 驗證是否成功載入
```

**載入驗證（關鍵）：**
若出現以下任一情況，**立即停止並輸出錯誤提示**：
- 頁面要求登入 Figma 帳號
- canvas 區域為空白或出現錯誤訊息
- 連結已失效（頁面顯示「找不到此檔案」）

```
🚫 無法讀取規格書

原因：{具體原因，例如「Figma 需要登入」、「檔案連結已失效」}
規格書網址：{url}

建議處理方式：
- 若需要登入：請先在瀏覽器中登入 Figma，再重新執行
- 若連結失效：請確認連結是否正確，或聯繫設計師取得新連結
```
**→ 立即停止，不繼續任何後續步驟。**

載入成功後繼續：
```
4. playwright:browser_take_screenshot()      ← 擷取視覺稿
5. playwright:browser_get_page_text()        ← 抓取文字層
6. 若為 Prototype 連結，逐一點擊互動元件取得每個畫面
```

**Figma 注意事項：**
- Public share link 通常可直接存取，無需登入
- 重點擷取標注文字、元件名稱、流程說明

---

### Step 3：整理與分析內容

爬取完成後，分析以下維度：
- **功能範疇**：這份規格書涵蓋哪些功能模組
- **使用者流程**：識別主要 user flow（登入、查詢、操作等）
- **UI 元件**：列出出現的核心元件（表單、列表、彈窗等）
- **狀態與情境**：識別各種狀態（空白態、載入中、錯誤態等）
- **邊界條件**：規格書中有無提及例外情境或限制

---

### Step 4：產出 PRD 文件

依照下方**PRD 格式**輸出完整 Markdown，並透過 filesystem MCP 存檔。

**存檔路徑規則：**
- 若從 Jira 觸發：`./docs/prd/{ISSUE_KEY}-prd.md`
- 若直接給連結：`./docs/prd/{slug}-prd.md`（slug 取自頁面標題）
- 若 filesystem MCP 不可用：直接在對話中輸出 Markdown

---

## PRD 格式

```markdown
# PRD：{規格書標題}

> **來源**：{規格書 URL}
> **爬取時間**：{timestamp}
> **關聯 Jira**：{ISSUE_KEY}（若從 Jira 觸發）

---

## 1. 背景與目標

說明此功能/需求的背景脈絡與預期達成的目標。
（從規格書的首頁說明或概覽頁萃取）

---

## 2. 使用者與情境

- **目標使用者**：誰會使用這個功能
- **使用情境**：在什麼場景下觸發
- **前置條件**：使用者需要什麼前提才能使用

---

## 3. 功能範疇

### 3-1. 功能清單

| 功能名稱 | 說明 | 優先級 |
|---------|------|--------|
| 功能 A | 簡述 | P0 |

### 3-2. 不包含範疇（Out of Scope）

明確列出哪些需求不在本次範疇內（若規格書有提及）。

---

## 4. 使用者流程

### 主要流程

用條列或流程圖文字描述主要操作路徑：

1. 使用者進入 {頁面}
2. 操作 {元件}
3. 系統回應 {行為}

### 次要流程 / 例外流程

描述異常情境（404、權限不足、網路錯誤等）的處理流程。

---

## 5. 頁面與元件清單

### {頁面名稱 1}

- **用途**：說明此頁面的功能
- **主要元件**：
  - `{元件名稱}`：說明
- **狀態定義**：
  - 空白態：
  - 載入中：
  - 錯誤態：
  - 成功態：

### {頁面名稱 2}

（重複以上結構）

---

## 6. 資料需求

列出此功能涉及的資料欄位、格式限制、驗證規則：

| 欄位名稱 | 類型 | 必填 | 驗證規則 | 備註 |
|---------|------|------|---------|------|
| email | string | 是 | email format | |

---

## 7. API / 後端需求（推測）

根據規格書功能推測需要的 API：

| API | Method | 說明 |
|-----|--------|------|
| /api/xxx | GET | 取得資料 |

> ⚠️ 此區塊為推測，需與後端確認。

---

## 8. 驗收條件（AC）

列出每個功能的驗收標準：

**功能 A**
- [ ] 使用者可以...
- [ ] 當...時，系統應...
- [ ] 錯誤訊息應顯示...

---

## 9. 開放問題（Open Questions）

列出規格書中不明確或需要進一步確認的地方：

- [ ] {問題描述} → 需確認對象：PM / 設計 / 後端
- [ ] {問題描述}

---

## 10. 附錄

- **規格書頁面清單**：{列出爬取到的所有頁面名稱}
- **截圖參考**：（若有 Figma，列出各畫面名稱）

---

*PRD 產生時間：{timestamp}*
*資料來源：{url}*
```

---

## 注意事項

- 爬取時若遇到需要登入的頁面，停止並提示使用者：「此頁面需要登入，請確認瀏覽器已登入後重試」
- Axure 頁面若有多層導覽，**深度不超過 3 層**，避免爬取過多無關頁面
- 若規格書頁面超過 20 頁，優先爬取「首頁」、「概覽」、「主要功能流程」相關頁面，其餘列入附錄清單即可
- PRD 中資訊不足的地方，用 `⚠️ 資訊不足，建議確認` 標註，不要捏造
- 語言：**中文為主，UI 元件名稱 / 技術術語維持原文**

---

## 範例觸發語句

- `幫我把這個規格書整理成 PRD：https://xxx.axshare.com/...`
- `爬這個 Figma 然後產出需求文件`
- `https://figma.com/proto/xxx 這個要怎麼實作，先幫我整理成 PRD`
- （由 jira-analyzer 自動呼叫，無需使用者手動觸發）
