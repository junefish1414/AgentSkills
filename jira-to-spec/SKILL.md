---
name: jira-to-spec
description: >
  當使用者提到 Jira 任務單號並要求產出「規格書」時觸發。
  觸發語句包含但不限於：「幫 VIPOP-XXXXX 寫規格書」、「把 VIPOP-XXXXX 整理成規格書」、
  「VIPOP-XXXXX 的規格書」、「幫我產這張票的 spec」、「VIPOP-XXXXX spec」。
  自動透過 Atlassian MCP 讀取 Jira 任務內容，結合規格書標準模板，
  產出規格書 Markdown 與 HTML 檔案至 docs/{ISSUE_KEY}/。
  注意：若使用者只說「分析 VIPOP-XXXXX」而未提及規格書/spec，應觸發 jira-analyzer 而非此 skill。
compatibility: "需要 Atlassian MCP、filesystem MCP；建議同時啟用 Playwright MCP"
---

# Jira to Spec — 從 Jira Ticket 產出規格書

## 與 jira-analyzer 的分工

| Skill | 觸發條件 | 產出物 |
|-------|---------|--------|
| jira-analyzer | 「分析」「評估」「看一下」 | 技術分析報告 |
| jira-to-spec | 「規格書」「spec」「寫規格」 | 規格書文件檔案 |

---

## 執行步驟

### Step 0：前置確認（平行執行，節省時間）

同時執行以下四件事：

**A. 檢查 template 更新**
用 filesystem MCP 讀取 `~/.skill-sources/last-template-change.md`：
- 存在 → 記錄變動摘要，於最後輸出時告知使用者
- 不存在 → 略過

**B. 確認輸出目錄**
用 filesystem MCP 確認 `{SKILL_REPO}/docs/{ISSUE_KEY}/` 是否存在，不存在則建立。
`SKILL_REPO` 從 `~/.skill-sources/config` 讀取。

**C. 讀取最新模板**
用 filesystem MCP 讀取 `{SKILL_REPO}/jira-to-spec/references/template.md`：
- 成功 → 作為規格書結構
- 失敗 → 使用本檔末尾「內建備用模板」，並告知使用者

**D. 若 Jira description 含 axshare.com 連結 → 立即詢問 Axure 密碼**
- 不等到 Step 2C 才中斷，在 Step 0 就先問：
  > 「偵測到 Axure 規格書（{axure_url}），請提供存取密碼，我才能截圖並納入規格書。」
- 收到密碼後繼續執行 Step 1；密碼會在 Step 2C 使用

---

### Step 1：取得 Jira 任務資料

```
工具：mcp-atlassian:jira_get_issue
參數：
  issue_key: "{ISSUE_KEY}"
  fields: "summary,description,issuetype,status,priority,assignee,reporter,
           labels,duedate,subtasks,issuelinks,parent,comment,attachment"
  comment_limit: 20
```

解析重點：
- `description`：主要規格來源
- `comment`：含「改為」「調整」「要補做」的留言視為規格補充，一併納入
- `attachment`：掃描是否有 Figma / Axure 連結，有則記錄供 Step 2 使用
- `subtasks`：列出子任務清單，納入影響範圍

---

### Step 2：收集圖片資源（選擇性，最多 3 個來源）

**依序嘗試，任一失敗不中斷流程：**

**2A. Jira 附件圖片**（最優先）
```
工具：mcp-atlassian:jira_get_issue_images
參數：issue_key: "{ISSUE_KEY}"
```
- 取回後**只挑最多 5 張**最能說明規格的圖片（跳過純截圖紀錄、驗收截圖）
- 每張記錄：`{ data: base64, label: "來源：Jira {ISSUE_KEY} 附件", section: "對應的 Section" }`

**2B. Figma 設計稿截圖**（若 Step 1 偵測到 figma.com 連結）
```
工具：Playwright MCP → browser_screenshot
```
- 只截取主要設計畫面，最多 2 張
- 記錄：`{ data: base64, label: "來源：Figma 設計稿" }`
- 失敗 → 略過，在參考資料留連結即可

**2C. Axure 規格書截圖**（若偵測到 axshare.com 連結）

> ⚠️ **Axure 為必要步驟，不可跳過。** 偵測到 axshare.com 連結時，必須完成以下流程才能繼續。

**步驟 2C-0：確認密碼已取得（來自 Step 0D）**
- 密碼已在 Step 0D 取得，直接繼續執行 2C-1
- 若 Step 0D 未執行（舊流程補救）→ 此時暫停詢問密碼後再繼續

**步驟 2C-1：確認 Playwright MCP 可用**
- 嘗試呼叫 `browser_navigate` 前，先確認 Playwright MCP 工具可被呼叫
- 若 Playwright MCP 不可用（工具不存在或呼叫失敗）→ **中斷整個規格書流程**，回報：
  > 「無法使用 Playwright MCP，Axure 規格書無法存取。請確認 Playwright MCP 已啟用後重試。」

**步驟 2C-2：開啟 Axure 並輸入密碼**
```
工具：Playwright MCP → browser_navigate → browser_evaluate → browser_screenshot
```
- 導航至 axshare.com 連結
- 若頁面出現密碼輸入欄位，填入使用者提供的密碼並送出
- 若密碼錯誤或無法通過驗證 → **中斷流程**，回報：
  > 「Axure 密碼驗證失敗，請確認密碼是否正確後重試。」
- 若頁面無法載入（網路錯誤、404 等） → **中斷流程**，回報：
  > 「Axure 規格書無法存取（{錯誤原因}），請確認連結是否有效。」

**步驟 2C-3：列出所有頁面，決定截圖清單**
- 進入 Axure 後，先用 `browser_snapshot` 或點擊左側 Project Pages 展開頁面清單
- 記錄所有頁面名稱與數量（標題列會顯示「N of M」）

**步驟 2C-4：逐頁截圖**
- 截圖前使用 `browser_resize` 將視窗調整至 **1440×900**，減少不必要滾動
- 每頁進入後，用 `browser_evaluate` 查詢 **iframe 內部** 的捲動尺寸（Axure 用 iframe 渲染，`document.body` 無效）：
  ```js
  () => {
    const iframe = document.querySelector('iframe');
    if (!iframe) return null;
    const doc = iframe.contentDocument || iframe.contentWindow.document;
    return { scrollWidth: doc.body.scrollWidth, scrollHeight: doc.body.scrollHeight,
             clientWidth: doc.body.clientWidth, clientHeight: doc.body.clientHeight };
  }
  ```
- 若 `scrollHeight > clientHeight`（可向下滾動）→ 先截圖上方，再按 `PageDown` 鍵滾動（**不可用 `window.scrollTo`，在 iframe 架構下無效**），再截一張
- 若 `scrollWidth > clientWidth`（可向右滾動）→ 先截圖左側，再按 `End` 鍵滾至最右再截一張
- 若畫面可雙向滾動，依序截：左上 → 右上 → 左下 → 右下（最多 4 張分區截圖）
- 記錄：`{ data: base64, label: "來源：Axure 規格書（第 N 張／共 M 張）" }`

> 圖片總數上限：**10 張**（Jira 5 + Figma 2 + Axure 最多 4），超過不再取，避免 token 暴增。
> Axure 若無滾動需求則 1 張即可；有上下或左右滾動則最多 4 張分區截圖。

---

### Step 3：判斷需求類型

**scope 判斷：**
- 修改文案 / 小幅 UI → `patch`
- 新增功能 / 大幅改動 → `feature`
- 移除功能 → `removal`
- 純埋點 → `tracking`

**type 判斷：**
- 純文案版面 → `content`
- 操作流程按鈕 → `interaction`
- 角色權限 → `permission`
- 純 GA/NCC → `ga`
- 純版面重排 → `layout`
- 複合 → `mixed`

**依 scope/type 決定要填哪些 Section：**

| scope/type | 必填 | 選填 |
|------------|------|------|
| patch + content | 1, 3 | 15, 16 |
| patch + interaction | 1, 4, 5 | 15, 16 |
| patch + ga | 1, 12 | 16 |
| feature + interaction | 1, 2, 4, 5, 15, 16 | 6, 9, 10, 11, 12 |
| feature + permission | 1, 2, 4, 6, 15, 16 | 5, 7 |
| feature + mixed | 1, 2, 4, 5, 6, 15, 16 | 其餘視內容 |
| removal | 1, 8, 15 | 12, 13 |
| tracking | 1, 12 | 16 |

---

### Step 4：填充規格書內容

依 Step 3 決定的 Section 清單填充，遵循以下原則：

1. **忠實呈現**：Jira 未提及用 `⚠️ 未提及，建議與 PM 確認` 標註，不捏造
2. **留言補充**：含「改為」「調整」「要補做」的留言內容納入對應 Section
3. **操作流程附流程圖**：Section 4 每個流程附 Mermaid `flowchart TD`
4. **狀態變化附狀態圖**：Section 7 狀態變化用 Mermaid `stateDiagram-v2`
5. **Section 16 主動出題**：AI 依需求類型主動補充極端情境，每條標示「🤖 AI 建議」或「⚠️ 未定義」
6. **圖片嵌入**：將 Step 2 收集的圖片依 `section` 欄位，嵌入對應 Section 末尾：
   ```markdown
   ![來源：Jira VIPOP-XXXXX 附件](data:image/png;base64,{base64})
   ```
7. **前端視角**：所有分析以前端工程師角度出發

---

### Step 5：在規格書末尾加入 PO 補問清單

將所有 ⚠️ 彙整，分三級，用選擇題格式：

```markdown
## 📋 PO 補問清單

### 🔴 Blocker（必須回答才能開工）
**Q-001：{問題}**
- [ ] A. {選項}（建議）
- [ ] B. {選項}
- [ ] C. 其他：___

### 🟡 Warning（強烈建議回答）
**Q-002：{問題}**
- [ ] A. {選項}
- [ ] B. {選項}

### 🟢 Info（AI 預設假設，無異議視為同意）
- A-001：{假設}
```

---

### Step 6：寫入檔案

用 filesystem MCP 寫入兩個檔案：

**6A. Markdown 檔**
```
路徑：{SKILL_REPO}/docs/{ISSUE_KEY}/{ISSUE_KEY}-spec.md
內容：完整規格書 Markdown（含 base64 圖片）
```

**6B. HTML 檔**
將 Markdown 轉為 HTML，寫入：
```
路徑：{SKILL_REPO}/docs/{ISSUE_KEY}/{ISSUE_KEY}-spec.html
```

HTML 轉換規則：
- frontmatter → 頁首 metadata 資訊卡
- `## 標題` → `<h2>`，`### 子標題` → `<h3>`
- 表格 → `<table>`（含 hover 樣式）
- ` ```mermaid ` → `<pre class="mermaid">`（由 Mermaid.js CDN 渲染）
- `⚠️ 文字` → `<div class="warning">`
- `- [ ]` → `<input type="checkbox" disabled>`
- `![label](data:image/...)` → `<figure><img src="data:image/..."><figcaption>label</figcaption></figure>`
- base64 圖片加 `max-width: 100%; border-radius: 4px; margin: 1rem 0`

HTML 使用以下精簡樣式（inline，不依賴外部 CSS）：

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{ISSUE_KEY} 規格書</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f8f9fa;color:#1a1a1a;line-height:1.7;padding:2rem;max-width:960px;margin:0 auto}
    .meta{background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:1.25rem 1.5rem;margin:.5rem 0 2rem;display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:.5rem 2rem}
    .meta span{font-size:.85rem;color:#555}.meta strong{color:#1a1a1a}
    h1{font-size:1.6rem;margin-bottom:.25rem}
    h2{font-size:1.3rem;margin:2.5rem 0 1rem;padding-bottom:.4rem;border-bottom:2px solid #e0e0e0}
    h3{font-size:1.1rem;margin:1.5rem 0 .75rem}
    p{margin-bottom:.75rem}ul,ol{margin:.5rem 0 1rem 1.5rem}li{margin-bottom:.35rem}
    code{background:#f0f0f0;padding:.15rem .4rem;border-radius:3px;font-size:.9em}
    table{width:100%;border-collapse:collapse;margin:1rem 0;font-size:.9rem}
    th,td{border:1px solid #ddd;padding:.5rem .75rem;text-align:left}
    th{background:#f5f5f5;font-weight:600}tr:hover td{background:#fafafa}
    .mermaid{background:#fff;border:1px solid #e8e8e8;border-radius:8px;padding:1.5rem;margin:1rem 0;text-align:center}
    .warning{background:#fff8e1;border-left:4px solid #ffc107;padding:.75rem 1rem;margin:.75rem 0;border-radius:0 4px 4px 0;font-size:.9rem}
    figure{margin:1rem 0}figure img{max-width:100%;border-radius:4px;border:1px solid #e0e0e0}
    figcaption{font-size:.8rem;color:#888;margin-top:.25rem}
    input[type=checkbox]{margin-right:.4rem}
    footer{margin-top:3rem;padding-top:1rem;border-top:1px solid #e0e0e0;font-size:.8rem;color:#888}
  </style>
</head>
<body>
  <h1>📋 {ISSUE_KEY} — {title}</h1>
  <div class="meta">
    <span><strong>Scope：</strong>{scope}</span>
    <span><strong>Type：</strong>{type}</span>
    <span><strong>Created：</strong>{created}</span>
    <span><strong>Deadline：</strong>{deadline}</span>
    <span><strong>Related：</strong>{related}</span>
  </div>
  {BODY_HTML}
  <footer>
    <p>產生時間：{timestamp}　資料來源：Jira {ISSUE_KEY}　產生方式：jira-to-spec skill 自動產出，需 PM/PO 確認</p>
  </footer>
  <script>mermaid.initialize({startOnLoad:true,theme:'default',flowchart:{useMaxWidth:true,htmlLabels:true}})</script>
</body>
</html>
```

---

### Step 7：對話輸出摘要

**不在對話輸出完整 Markdown 內容**，只輸出以下摘要：

```
✅ 規格書已產出

📁 檔案位置
   {SKILL_REPO}/docs/{ISSUE_KEY}/
   ├── {ISSUE_KEY}-spec.md
   └── {ISSUE_KEY}-spec.html

📊 規格書摘要
   scope: {scope} | type: {type}
   填充 Section: {已填 Section 編號列表}
   ⚠️ 待確認項目: {N} 個（含 Blocker {X} 個）
   🖼️ 嵌入圖片: {N} 張（Jira {X} 張 / Figma {X} 張 / Axure {X} 張）

🔴 Blocker 摘要（需優先回答）
   {逐條列出 Blocker 問題，最多顯示 3 條}

{若 Step 0A 偵測到 template 更新}
📢 Template 有更新：{變動摘要一行}
```

---

## 注意事項

- 語言：**中文為主，技術術語 / 路徑 / 元件名稱維持原文**
- 資訊不足時標註 `⚠️`，**絕對不捏造**
- Section 只填有意義的，不填空殼
- Bug 類型 ticket → 提示「建議改用 jira-analyzer 分析」
- 圖片超過 7 張上限時，優先保留「操作流程」和「UI 設計稿」相關的圖片

---

## 內建備用模板（filesystem 讀取失敗時使用）

> 正常情況下 Step 0C 會從本地讀取最新版本，此處僅作 fallback。

Section 編號與標題對照：

| # | 標題 | 對應需求類型 |
|---|------|------------|
| 1 | 影響範圍（角色 / 頁面 / 這次不改） | 全部 |
| 2 | 權限設計（矩陣 / 檢查時機） | permission |
| 3 | 文案 / 版面異動 | content |
| 4 | 操作流程（現行 / 調整後 / 流程圖） | interaction |
| 5 | 提示與文案（Modal / Toast / Banner） | interaction |
| 6 | 商業規則（計費 / 額度） | permission |
| 7 | 狀態變化（狀態圖） | permission |
| 8 | 功能移除（體驗 / 資料處理） | removal |
| 9 | 頁面結構（URL / 狀態 / SEO） | feature |
| 10 | 表單（欄位 / 驗證 / 送出） | feature |
| 11 | 列表 / 搜尋結果（排序 / 分頁） | feature |
| 12 | 追蹤埋點（事件 / 漏斗） | ga / tracking |
| 13 | 通知 / 信件 | feature |
| 14 | 既有頁面調整 | feature |
| 15 | 錯誤處理（頁面 / 操作 / 表單 / 恢復） | 全部 |
| 16 | 例外情境（操作 / 網路 / 資料 / 裝置 / 權限 / 併發） | 全部 |

各 Section 詳細格式請參照：
`{SKILL_REPO}/jira-to-spec/references/template.md`

---

## 範例觸發語句

應觸發此 skill：
- `幫 VIPOP-44376 寫規格書`
- `VIPOP-567 的 spec`
- `這張票 VIPOP-111 要寫 spec`

不應觸發（應觸發 jira-analyzer）：
- `分析 VIPOP-1234`
- `幫我看一下 VIPOP-567`
- `VIPOP-890 的難度評估`