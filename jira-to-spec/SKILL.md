---
name: jira-to-spec
description: >
  當使用者提到 Jira 任務單號並要求產出「規格書」時觸發。
  觸發語句包含但不限於：「幫 VIPOP-XXXXX 寫規格書」、「把 VIPOP-XXXXX 整理成規格書」、
  「VIPOP-XXXXX 的規格書」、「幫我產這張票的 spec」、「VIPOP-XXXXX spec」。
  自動透過 Atlassian MCP 讀取 Jira 任務內容，結合規格書標準模板，
  產出一份完整的中文規格書 Markdown 文件。
  注意：若使用者只說「分析 VIPOP-XXXXX」而未提及規格書/spec，應觸發 jira-analyzer 而非此 skill。
  本 skill 僅在使用者明確要求產出規格書、spec 文件時觸發。
compatibility: "需要 Atlassian MCP（讀取 Jira 任務）；建議同時啟用 Playwright MCP（爬取規格書連結）"
---

# Jira to Spec — 從 Jira Ticket 產出規格書

## 目標

當使用者輸入包含 `VIPOP-XXXXX` 格式的任務單號，並要求產出規格書時：

1. 透過 Atlassian MCP 拉取任務詳細資料
2. 若任務描述中含有 Axure / Figma 連結，透過 Playwright MCP 爬取規格書內容作為補充
3. 依據**規格書標準模板**產出完整 Markdown 文件

---

## 與 jira-analyzer 的分工

| Skill | 觸發條件 | 產出物 |
|-------|---------|--------|
| jira-analyzer | 使用者提到 VIPOP-XXXXX 且要求「分析」「評估」「看一下」 | 技術分析報告（難度、時間估算、風險點） |
| jira-to-spec | 使用者提到 VIPOP-XXXXX 且要求「規格書」「spec」「寫規格」 | 規格書標準模板格式文件 |

---

## 執行步驟

### Step 0：檢查 template 是否有更新

執行任何步驟前，先用 filesystem MCP 讀取以下路徑：

```
/Users/june.wang/.skill-sources/last-template-change.md
```

- **檔案存在** → 讀取內容，並在規格書產出完成後，於對話末尾告知使用者：
  「📢 規格書模板自上次使用後有更新，變動摘要如下：[摘要 changelog 內容]」
- **檔案不存在** → 略過，直接執行 Step 1

> 此檔案由每日同步腳本在偵測到遠端更新時自動產出；無更新時會被刪除。

---

### Step 1：擷取任務單號

從使用者訊息中識別 `VIPOP-\d+` 格式的任務單號。

### Step 2：取得 Jira 任務資料

使用 Atlassian MCP 取得任務完整資料：

```
工具：Atlassian:getJiraIssue
參數：
  cloudId: "3b735765-d212-40c4-acb7-0aa53cf89612"
  issueIdOrKey: "{擷取到的單號}"
  responseContentFormat: "markdown"
```

擷取以下欄位（若存在）：
- `summary`：任務標題
- `description`：任務描述（核心資訊來源）
- `issuetype`：任務類型（Bug / Story / Task / Sub-task）
- `status`：目前狀態
- `priority`：優先級
- `assignee`：負責人
- `reporter`：回報者（通常是 PM/PO）
- `labels`：標籤
- `components`：影響元件
- `fixVersions`：目標版本
- `duedate`：截止日期
- `subtasks`：子任務
- `issuelinks`：相關連結
- `parent`：父任務（Epic）
- `customfield_*`：自訂欄位（Sprint、Story Points 等）
- `attachment`：附件（可能含規格書連結）
- `comment`：留言（可能含補充需求或規格書連結）

> ⚠️ 留言中含「改為」「調整」「要補做」等動詞時，視為規格補充（不只是驗收紀錄），納入規格書內容。

### Step 3：偵測規格書連結（選擇性）

掃描 `description`、`comment`、`attachment` 中的 URL：
- 含 `axshare.com` → Axure 規格書
- 含 `figma.com` → Figma 設計稿

若偵測到規格書連結，且 Playwright MCP 可用：
1. 嘗試爬取規格書內容作為補充資訊
2. 若爬取失敗（需登入、頁面不可讀等），**不中斷流程**，在規格書的「參考資料」區塊標註連結即可

> ⚠️ 與 jira-analyzer 不同：此 skill 爬取規格書失敗時**不終止**，因為主要資訊來源是 Jira ticket 本身。

### Step 4：判斷需求類型

根據 Jira 任務內容，判斷需求的 `scope` 和 `type`：

**scope 判斷規則：**
| 條件 | scope |
|------|-------|
| 修改文案、調整版面、小幅 UI 調整 | patch |
| 新增功能、大幅改動流程 | feature |
| 移除功能或頁面 | removal |
| 純追蹤埋點、GA 事件 | tracking |

**type 判斷規則：**
| 條件 | type |
|------|------|
| 純文案/版面改動 | content |
| 涉及操作流程、按鈕行為 | interaction |
| 涉及角色權限判斷 | permission |
| 純 GA/NCC 埋點 | ga |
| 純版面重排 | layout |
| 以上多項混合 | mixed |

### Step 5：讀取最新規格書模板

使用 filesystem MCP 讀取本地最新模板：

```
路徑：/Users/june.wang/66-personal-folder/AgentSkills/jira-to-spec/references/template.md
```

**讀取規則：**
- ✅ **讀取成功** → 以該檔案內容作為規格書結構，依據下方「Section 選用規則」挑選適用區塊填充
- ❌ **讀取失敗** → 使用本 SKILL.md 末尾的「內建備用模板」繼續執行，並告知使用者「無法讀取本地模板，使用內建備用版本」

### Step 6：依 scope/type 選用適用 Section

template.md 包含 16 個 Section，**不是每張票都要全填**。依需求類型選用：

| scope / type | 必填 Section | 選填 Section |
|-------------|-------------|-------------|
| patch + content | 1, 3 | 15, 16 |
| patch + interaction | 1, 4, 5 | 15, 16 |
| patch + ga | 1, 12 | 16 |
| feature + interaction | 1, 2, 4, 5, 15, 16 | 6, 9, 10, 11, 12 |
| feature + permission | 1, 2, 4, 6, 15, 16 | 5, 7 |
| feature + mixed | 1, 2, 4, 5, 6, 15, 16 | 視內容決定其餘 |
| removal | 1, 8, 15 | 12, 13 |
| tracking | 1, 12 | 16 |

> 這是指引而非硬規則，實際應根據 Jira 內容判斷。不相關的 Section 整段省略，不要填空殼。

### Step 7：填充規格書內容

依照選用的 Section 填充，遵循以下原則：

1. **忠實呈現 Jira 內容**：不捏造資訊，Jira 未提及的部分用 `⚠️ Jira 未提及，建議與 PM 確認` 標註
2. **智慧填充**：根據任務描述合理推斷影響範圍、角色、流程等
3. **留言視為規格補充**：含「改為」「調整」「要補做」等動詞的留言，內容要納入對應 Section
4. **Section 16 主動出題**：AI 主動依需求類型補充極端情境，每條標示「🤖 AI 建議，待 PO 確認」或「⚠️ 未定義」
5. **操作流程附流程圖**：Section 4 每個流程都要附 Mermaid `flowchart TD` 流程圖
6. **狀態變化附狀態圖**：Section 7 使用 Mermaid `stateDiagram-v2`
7. **前端視角**：所有分析以前端工程師角度出發

### Step 8：在末尾加入 PO 補問清單

規格書最後固定加一個額外區塊，將所有 ⚠️ 彙整並分三級，問題盡量用選擇題格式：

```
## 📋 PO 補問清單（AI 產出）

### 🔴 Blocker（必須回答才能開工）
Q-001：{問題} → 選項 A / B / C

### 🟡 Warning（強烈建議回答）
Q-002：{問題} → 選項 A / B

### 🟢 Info（AI 已做預設假設，無異議視為同意）
A-001：{假設描述}
```

### Step 9：輸出

1. 直接在對話中輸出完整 Markdown 規格書
2. **同時生成完整的 HTML 版規格書**（見下方「HTML 規格書生成」），檔名：`{ISSUE_KEY}-spec.html`
3. 若 Step 0 偵測到 template 有更新，在對話末尾附上更新摘要

---

## HTML 規格書生成

規格書產出後，自動將整份 Markdown 內容轉為一個自包含的 HTML 檔案。

**生成規則：**
- 將規格書的所有 Markdown 內容（標題、段落、表格、列表、程式碼區塊等）轉為對應的 HTML 標籤
- Mermaid 區塊用 `<pre class="mermaid">` 包裹，由 Mermaid.js CDN 即時渲染為流程圖
- 表格轉為 `<table>` 並套用樣式
- frontmatter（id, title, scope 等）轉為頁首的 metadata 資訊卡
- 檔名：`{ISSUE_KEY}-spec.html`

**轉換對照：**

| Markdown 語法 | HTML 輸出 |
|--------------|----------|
| `## 標題` | `<h2>標題</h2>` |
| `### 子標題` | `<h3>子標題</h3>` |
| 段落文字 | `<p>文字</p>` |
| `- 列表項` | `<ul><li>列表項</li></ul>` |
| `1. 有序列表` | `<ol><li>有序列表</li></ol>` |
| `\| 表格 \|` | `<table>...</table>` |
| `` ```mermaid `` | `<pre class="mermaid">...</pre>` |
| `**粗體**` | `<strong>粗體</strong>` |
| `` `行內代碼` `` | `<code>行內代碼</code>` |
| `⚠️ 提示文字` | `<div class="warning">⚠️ 提示文字</div>` |
| `- [ ] 驗收項` | `<input type="checkbox" disabled> 驗收項` |

**HTML 骨架模板：**

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{ISSUE_KEY} 規格書</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f8f9fa; color: #1a1a1a;
      line-height: 1.7; padding: 2rem; max-width: 960px; margin: 0 auto;
    }
    .spec-meta {
      background: #fff; border: 1px solid #e0e0e0; border-radius: 8px;
      padding: 1.25rem 1.5rem; margin-bottom: 2rem;
      display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 0.5rem 2rem;
    }
    .spec-meta .meta-item { font-size: 0.85rem; color: #555; }
    .spec-meta .meta-item strong { color: #1a1a1a; }
    h1 { font-size: 1.6rem; margin-bottom: 0.25rem; }
    h2 { font-size: 1.3rem; margin: 2.5rem 0 1rem; padding-bottom: 0.4rem; border-bottom: 2px solid #e0e0e0; }
    h3 { font-size: 1.1rem; margin: 1.5rem 0 0.75rem; }
    p { margin-bottom: 0.75rem; }
    ul, ol { margin: 0.5rem 0 1rem 1.5rem; }
    li { margin-bottom: 0.35rem; }
    code { background: #f0f0f0; padding: 0.15rem 0.4rem; border-radius: 3px; font-size: 0.9em; }
    table { width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.9rem; }
    th, td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; text-align: left; }
    th { background: #f5f5f5; font-weight: 600; }
    tr:hover { background: #fafafa; }
    .mermaid { background: #fff; border: 1px solid #e8e8e8; border-radius: 8px; padding: 1.5rem; margin: 1rem 0; text-align: center; }
    .warning { background: #fff8e1; border-left: 4px solid #ffc107; padding: 0.75rem 1rem; margin: 0.75rem 0; border-radius: 0 4px 4px 0; font-size: 0.9rem; }
    input[type="checkbox"] { margin-right: 0.5rem; }
    .spec-footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #e0e0e0; font-size: 0.8rem; color: #888; }
  </style>
</head>
<body>
  <h1>📋 {ISSUE_KEY} — {title}</h1>
  <div class="spec-meta">
    <div class="meta-item"><strong>Scope：</strong>{scope}</div>
    <div class="meta-item"><strong>Type：</strong>{type}</div>
    <div class="meta-item"><strong>Source：</strong>jira</div>
    <div class="meta-item"><strong>Created：</strong>{created}</div>
    <div class="meta-item"><strong>Deadline：</strong>{deadline}</div>
    <div class="meta-item"><strong>Related：</strong>{related}</div>
  </div>
  <!-- 規格書各 Section 的 HTML 內容 -->
  <div class="spec-footer">
    <p>規格書產生時間：{timestamp}</p>
    <p>資料來源：Jira {ISSUE_KEY}</p>
    <p>產生方式：jira-to-spec skill 自動產出，內容需經 PM/PO 確認</p>
  </div>
  <script>
    mermaid.initialize({ startOnLoad: true, theme: 'default', flowchart: { useMaxWidth: true, htmlLabels: true } });
  </script>
</body>
</html>
```

**輸出方式：**
- 在 Claude Code 中：將 HTML 寫入 `{ISSUE_KEY}-spec.html`，完成後提示使用者 `open {ISSUE_KEY}-spec.html`
- 在 Claude.ai 中：建立 HTML 檔案並提供下載

---

## 內建備用模板

> ⚠️ 此模板僅在 filesystem MCP 無法讀取本地 `references/template.md` 時使用。
> 正常情況下，Step 5 會優先從以下路徑讀取最新版本：
> `/Users/june.wang/66-personal-folder/AgentSkills/jira-to-spec/references/template.md`

```markdown
id:                # Jira ticket ID，例：VIPOP-44376
title:             # 一行摘要
scope:             # patch | feature | removal | tracking
type:              # content | interaction | permission | ga | layout | mixed
source:            # jira | prd | slack | meeting
created:           # YYYY-MM-DD
deadline:          # YYYY-MM-DD（選填，有排程才填）
related:           # 關聯 ticket，例：[VIPOP-44300, VIPOP-44301]
----------------------------------------------------------------

## 1. 影響範圍

### 受影響的角色

| 角色 | 影響方式 |
| ---- | -------- |
| 未登入訪客 | 看不到此功能入口 |
| 免費企業用戶 | 看到功能入口但無法使用，引導升級 |
| VIP 企業用戶 | 完整使用 |
| 獵頭、派遣身份用戶 | 看不到此功能入口 |

### 受影響的頁面 / 功能

| 頁面名稱 | 頁面路徑 | 異動類型 |
|---------|---------|---------|
| | | 新增 / 修改 / 移除 |

### 這次不改

| 不改的項目 | 原因 |
|-----------|------|
| | |

## 2. 權限設計

### 角色權限矩陣

| 角色 | 進入頁面 | 使用功能 | 查看資料 | 操作資料 | 未滿足時行為 |
|------|:-------:|:-------:|:-------:|:-------:|------------|
| 未登入 | ❌ | ❌ | ❌ | ❌ | 導向登入頁 |
| 獵派公司 | ✅ | ❌ | 部分 | ❌ | 隱藏功能按鈕 |
| Web、純刊登公司 | ✅ | ❌ | ❌ | ❌ | 隱藏功能按鈕 |
| 一般公司 | ✅ | ❌ | 部分 | ❌ | 顯示 tooltip 升級引導 |
| ATS 用戶 | ✅ | ✅ | ✅ | ✅ | - |

### 權限檢查時機

| 檢查點 | 檢查內容 | 不通過時行為 |
|--------|---------|------------|
| 進入頁面 | 是否登入 | 導向登入頁，登入後跳回 |
| 執行功能 | 是否 VIP | 顯示升級引導 Modal |
| 操作資料 | 是否有足夠點數 | 顯示儲值引導 Modal |
| 操作途中 | 登入是否過期 | 彈出重新登入提示，保留操作狀態 |

## 3. 文案 / 版面異動

**頁面**：{頁面名稱}（{頁面路徑}）

| 區域 | 現行內容 | 改為 | 備註 |
|------|---------|------|------|
| | | | |

**版面調整**：
- 將 {A 區塊} 從 {位置 1} 移至 {位置 2}

**響應式差異**：
| 裝置 | 差異說明 |
|------|---------|
| Desktop | |
| Tablet | |
| Mobile | |

## 4. 操作流程

**現行流程**：
1. 用戶進入 {頁面}（{頁面路徑}）
2. {互動}
3. {系統回應}
4. {結果}

**調整後流程**：
1. 用戶進入 {頁面}（{頁面路徑}）
2. {互動}
3. {系統回應}
4. {結果}

**流程圖**：
\```mermaid
flowchart TD
    A[開始] --> B{條件判斷}
    B -->|是| C[動作]
    B -->|否| D[替代動作]
\```

## 5. 提示與文案

#### {提示名稱}（Modal / Toast / Banner / Tooltip）

| 屬性 | 內容 |
|------|------|
| 標題 | |
| 內容 | |
| 主要按鈕 | {文字} → {按下後行為} |
| 次要按鈕 | {文字} → {按下後行為} |
| 觸發時機 | {什麼情況下出現} |
| 可否關閉 | 點遮罩關閉 / ESC 關閉 / 僅按鈕關閉 |
| 顯示頻率 | 每次都顯示 / 每日一次 / 僅首次 |

## 6. 商業規則

| 用戶身份 | 狀態條件 | 看到什麼 | 可以做什麼 | 不可以做什麼 |
|---------|---------|---------|-----------|------------|
| 未登入 | - | | | |
| 免費用戶 | - | | | |
| 付費用戶 | 點數足夠 | | | |
| 付費用戶 | 點數不足 | | | |

**計費規則**：
- {描述扣點/收費邏輯}
- {例外情況}
- {退款/撤銷規則}

**額度規則**：
- 每日上限：
- 每月上限：
- 超額處理：

## 7. 狀態變化

| 原始狀態 | 觸發條件 | 新狀態 | 用戶看到的變化 | 可逆？ |
|---------|---------|--------|-------------|-------|
| | | | | |

**狀態圖**：
\```mermaid
stateDiagram-v2
    [*] --> 狀態A
    狀態A --> 狀態B : 觸發條件
    狀態B --> 狀態A : 回復條件
\```

## 8. 功能移除

**移除什麼**：{用用戶角度描述}

**移除後用戶體驗**：
- 原本有 {功能} 的位置 → {移除後顯示什麼？留白？替代內容？}
- 原本透過 {入口} 進入的用戶 → {導向哪裡？}
- 已收藏/加入書籤的用戶 → {看到什麼？}

**資料處理**：
- 既有資料是否保留？
- 是否需要遷移？
- 是否需要通知用戶？

## 9. 頁面結構

**頁面**：{頁面名稱}
**網址**：{預期的 URL path}
**誰可以進入**：{權限描述}
**進不去的人看到什麼**：{無權限畫面描述}

**頁面區塊**：
1. {區塊名稱} — {功能描述}

**頁面狀態**：
| 狀態 | 顯示內容 |
|------|---------|
| 載入中 | |
| 有資料 | |
| 無資料（空狀態） | |
| 錯誤 | |

**設計稿**：
| 裝置 | 連結 |
|------|------|
| Desktop | {Figma 連結} |
| Mobile | {Figma 連結} |

**SEO**：
| 屬性 | 值 |
|------|-----|
| title | |
| description | |
| og:image | |
| 是否需要 SSR | |

## 10. 表單

**表單名稱**：{名稱}
**用途**：{這個表單要完成什麼事}

#### 欄位定義

| 欄位名稱 | 欄位類型 | 必填 | 預設值 | 備註 |
|---------|---------|:----:|-------|------|
| | | | | |

#### 輸入驗證

| 欄位名稱 | 驗證規則 | 錯誤提示 | 驗證時機 |
|---------|---------|---------|---------|
| | 必填 | 「請輸入{欄位名}」 | blur / submit |
| | 最少 N 字 | 「至少輸入 N 個字」 | blur / submit |
| | 最多 N 字 | 「不可超過 N 個字」 | 即時（輸入時） |
| | 格式限制（正則） | 「格式不正確」 | blur |

#### 輸入處理

| 輸入情境 | 處理方式 |
|---------|---------|
| 前後空白 | 自動 trim / 保留 |
| 連續空白 | 壓縮為單一空白 / 保留 |
| HTML 標籤 | 移除（strip tags）/ 轉義（escape）/ 保留 |
| Script / XSS | 移除 |
| Emoji 表情符號 | 允許 / 移除 / 顯示但不送出 |
| 特殊符號（<>'"&） | 允許 / 移除 / 轉義 |
| 換行符號 | 允許 / 轉為空白 / 移除 |
| 複製貼上含格式文字 | 僅保留純文字 / 保留格式 |
| 超過字數上限 | 截斷不讓輸入 / 允許輸入但送出時報錯 |
| 純空白送出 | 視為未填，觸發必填驗證 |

#### 欄位間連動

- 當 {欄位A} 選擇 {值} 時，{欄位B} {行為}

#### 送出行為

- Loading 狀態：{按鈕 disabled + spinner / 全頁 loading}
- 成功 → {用戶看到什麼}
- 失敗 → {用戶看到什麼}
- 重複送出防護：{按鈕 disabled / debounce / 前一次完成前不可再送}
- 送出快捷鍵：{Enter / Ctrl+Enter / 無}

#### 草稿 / 暫存

- 是否需要自動儲存？
- 離開頁面時是否提示未儲存？

## 11. 列表 / 搜尋結果

**資料來源**：{描述}
**預設排序**：{規則}
**每頁筆數**：{數量}
**分頁方式**：傳統分頁 / 無限捲動 / 載入更多按鈕

**篩選條件**：
| 篩選項 | 類型 | 選項來源 | 預設值 | 可複選 |
|--------|------|---------|-------|:-----:|
| | | | | |

**排序選項**：
| 排序項 | 預設方向 |
|--------|---------|
| | 升冪 / 降冪 |

**單筆資料顯示**：
| 欄位 | 顯示規則 | 備註 |
|------|---------|------|
| | | |

**空狀態**：{無搜尋結果時顯示什麼}
**載入狀態**：{搜尋中顯示什麼}

## 12. 追蹤埋點

**追蹤目的**：{為什麼要追蹤？要分析什麼？}

| 觸發時機 | 事件名稱 | 攜帶參數 | 追蹤目的 |
|---------|---------|---------|---------|
| | | | |

**轉換漏斗**（選填）：
1. {步驟 1} → 追蹤事件：{event}
2. {步驟 2} → 追蹤事件：{event}
3. {步驟 3} → 追蹤事件：{event}

## 13. 通知 / 信件

| 觸發時機 | 通知類型 | 對象 | 內容摘要 | 頻率限制 |
|---------|---------|------|---------|---------|
| | Email / 站內信 / Push | | | |

## 14. 既有頁面調整

**頁面**：{頁面名稱}（{頁面路徑}）
**調整原因**：{為什麼舊頁面也要動}
**設計稿**：{Figma 連結}

## 15. 錯誤處理

### 頁面層級錯誤

| 錯誤情境 | 用戶看到什麼 | 用戶可以做什麼 |
|---------|------------|-------------|
| 頁面載入失敗 | 錯誤頁面 + 重試按鈕 | 重試 / 回首頁 |
| 無權限進入 | 403 提示 + 引導 | 返回 / 登入 / 升級 |
| 頁面不存在 | 404 頁面 | 回首頁 |

### 操作層級錯誤

| 操作 | 錯誤情境 | 錯誤提示（文案） | 提示方式 | 用戶可以做什麼 |
|------|---------|---------------|---------|-------------|
| {操作名稱} | API 回應 5xx | 「系統忙碌中，請稍後再試」 | Toast / Modal | 重試 |
| {操作名稱} | API 回應逾時 | 「連線逾時，請檢查網路後重試」 | Toast | 重試 |
| {操作名稱} | 網路斷線 | 「網路連線中斷，請檢查網路設定」 | Banner（頂部） | 恢復網路後自動重試 / 手動重試 |
| {操作名稱} | 業務邏輯錯誤（如餘額不足） | {具體文案} | Modal | {具體行為} |
| {操作名稱} | 登入過期 | 「登入已過期，請重新登入」 | Modal（不可關閉） | 重新登入，登入後回到原頁面 |

### 表單驗證錯誤

| 錯誤類型 | 顯示位置 | 顯示時機 | 清除時機 |
|---------|---------|---------|---------|
| 單一欄位驗證失敗 | 欄位下方（inline） | blur / submit | 用戶開始重新輸入時 |
| 多欄位聯合驗證失敗 | 表單頂部（summary） | submit | 任一相關欄位修改時 |
| API 回傳的欄位錯誤 | 對應欄位下方 | API 回應後 | 用戶開始重新輸入時 |
| API 回傳的通用錯誤 | Toast / Modal | API 回應後 | 自動消失 / 用戶關閉 |

### 錯誤恢復策略

| 情境 | 恢復方式 |
|------|---------|
| 用戶填了很長的表單，送出失敗 | 保留已填內容，不清空表單 |
| 操作到一半頁面意外重整 | {是否有暫存機制} |
| 扣點成功但後續操作失敗 | {是否退點 / 如何補救} |

## 16. 例外情境

| # | 情境分類 | 情境描述 | 建議預期行為 | 狀態 |
|---|---------|---------|------------|------|
| 1 | 操作類 | 用戶連續快速點擊送出按鈕 | | 🤖 AI 建議，待 PO 確認 |
| 2 | 操作類 | 同時開多個分頁操作同一功能 | | 🤖 AI 建議，待 PO 確認 |
| 3 | 操作類 | 瀏覽器上一頁/下一頁 | | ⚠️ 未定義 |
| 4 | 操作類 | 用戶在操作途中登入過期 | | ⚠️ 未定義 |
| 5 | 網路類 | 網路斷線或逾時 | | 🤖 AI 建議，待 PO 確認 |
| 6 | 網路類 | API 回應異常（5xx / 非 JSON） | | 🤖 AI 建議，待 PO 確認 |
| 7 | 資料類 | 資料量為 0（空狀態） | | ⚠️ 未定義 |
| 8 | 資料類 | 資料量極大（效能邊界） | | 🤖 AI 建議，待 PO 確認 |
| 9 | 資料類 | 資料在操作途中被他人異動 | | ⚠️ 未定義 |
| 10 | 輸入類 | 特殊字元或超長文字輸入 | | 🤖 AI 建議，待 PO 確認 |
| 11 | 輸入類 | 複製貼上含格式文字 / HTML | | ⚠️ 未定義 |
| 12 | 裝置類 | 手機端鍵盤彈出導致版面位移 | | ⚠️ 未定義 |
| 13 | 裝置類 | 不同瀏覽器的相容性 | | 🤖 AI 建議，待 PO 確認 |
| 14 | 權限類 | 操作到一半權限被降級 | | ⚠️ 未定義 |
| 15 | 併發類 | 多人同時操作同一筆資料 | | ⚠️ 未定義 |

---

## 📋 PO 補問清單（AI 產出）

### 🔴 Blocker（必須回答才能開工）

**Q-001：{問題描述}**
- [ ] A. {選項}（建議）
- [ ] B. {選項}
- [ ] C. 其他：_______

### 🟡 Warning（強烈建議回答）

**Q-002：{問題描述}**
- [ ] A. {選項}
- [ ] B. {選項}

### 🟢 Info（AI 已做預設假設，無異議視為同意）

- A-001：{假設描述}
- A-002：{假設描述}
```

---

## 注意事項

- 語言：**中文為主，技術術語 / 路徑 / 元件名稱維持原文**
- 資訊不足時誠實標註 `⚠️`，**絕對不捏造**
- Section 只填有意義的，不要為了模板完整性而填空殼
- 操作流程的流程圖使用 Mermaid `flowchart TD` 格式
- 狀態變化用 Mermaid `stateDiagram-v2` 格式
- 產出的規格書是 **v1 草稿**，末尾提醒使用者需與 PM/PO 確認後才算定稿
- 若 Jira ticket 類型是 Bug，提示使用者「Bug 類型的票通常不需要完整規格書，建議改用 jira-analyzer 進行分析」
- **HTML 規格書**：每次產出規格書時，一律同時生成完整的 HTML 版本，檔名為 `{ISSUE_KEY}-spec.html`

---

## 範例觸發語句

以下訊息應觸發此 skill：

- `幫 VIPOP-44376 寫規格書`
- `把 VIPOP-1234 整理成規格書`
- `VIPOP-567 的 spec`
- `幫我產 VIPOP-890 的規格書`
- `VIPOP-2024 規格書產出`
- `這張票 VIPOP-111 要寫 spec`

以下訊息**不應**觸發此 skill（應觸發 jira-analyzer）：

- `分析 VIPOP-1234`
- `幫我看一下 VIPOP-567`
- `VIPOP-890 的難度評估`
