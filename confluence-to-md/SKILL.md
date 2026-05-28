---
name: confluence-to-md
description: >
  使用 Atlassian MCP 將 Confluence 規格頁面（含子頁、附件、圖片）轉換成 Markdown 文件。
  當使用者提供 Confluence 連結（例如 `104corp.atlassian.net/wiki/...`）並要求轉換、閱讀、
  或整理規格內容時觸發。觸發語句包含但不限於：「幫我把這個 Confluence 轉成 MD」、
  「讀取這份 Confluence 規格」、「Confluence 轉 Markdown」。
  也可由 jira-to-spec skill 自動呼叫（當 Jira 內容偵測到 Confluence 連結時）。
compatibility: "需要 Atlassian MCP；輸出結構對齊 axure-to-md（spec.md + images/ + files/）"
---

# Confluence 規格頁轉 Markdown

使用 **Atlassian MCP** 讀取 Confluence 頁面內容、子頁、附件與圖片，輸出 Markdown 規格書。
輸出結構與 `axure-to-md` skill 對齊，方便 `jira-to-spec` 等上游 skill 整合。

> **嚴格限制**：本 skill 全程使用 `mcp__atlassian__*` 系列工具，不啟動瀏覽器、不使用 playwright。

---

## 前置準備

開始前依序確認以下資訊（若未提供則詢問使用者）：

1. **Confluence 頁面網址**（例如 `https://104corp.atlassian.net/wiki/spaces/XXX/pages/123456789/Page+Title`）
2. **Jira 單號**（例如 `VIPOP-12345`），用於決定輸出目錄名稱
3. **repo 路徑**：輸出目錄為 `{repo}/ra-docs/{Jira單號}/`
4. **mode**（可選，預設 `full`）：
   - `full`：讀取主頁 + 所有子頁，輸出完整 `spec.md`
   - `page-only`：僅讀取主頁（不展開子頁），輸出 `spec.md`
   - `descendants-only`：只列出子頁清單至 `confluence-sitemap.md`，不讀內容（給主 agent 後續挑選用）
   - `pages-from-list`：依傳入的 `pages_file`（Markdown 檔，「## 需讀取」區塊下的條列項目即頁面標題清單），只讀清單中的頁面

---

## 輸出目錄結構

```
{repo}/ra-docs/{Jira單號}/
├── spec.md                        # 主要規格文件（合併主頁+子頁）
├── confluence-sitemap.md          # 頁面樹清單（descendants-only / 含子頁時產出）
├── images/                        # 頁面內嵌的圖片
│   ├── {page-slug}-{filename}.png
│   └── ...
└── files/                         # 附件（PDF、Excel 等）
    └── {page-slug}-{filename}.pdf
```

- `spec.md` 為主要規格文件
- 圖片統一放在 `{repo}/ra-docs/{Jira單號}/images/`
- 附件（非圖片）放在 `{repo}/ra-docs/{Jira單號}/files/`
- 檔名規則：`{page-slug}-{原始檔名}`，避免不同頁面同名衝突
  - `{page-slug}` 為頁面標題轉小寫、空白轉 `-`、移除特殊符號（最多 30 字元）

---

## 解析 Confluence URL

從 URL 取得以下資訊：

- **格式 A**：`/wiki/spaces/{spaceKey}/pages/{pageId}/{Page+Title}`
- **格式 B**：`/wiki/display/{spaceKey}/{Page+Title}`（舊版）
- **格式 C**：含 `pageId=` query string 的網址

**優先取 `pageId`**（純數字）。若 URL 只有標題沒有 pageId：

```
工具：mcp__atlassian__searchConfluenceUsingCql
參數：
  cql: 'title = "{decoded title}" AND space = "{spaceKey}"'
```

從結果中找到對應 `id` 作為 pageId。

---

## Step 1：取得 Cloud ID

Atlassian MCP 多數工具需要 `cloudId`，先取得：

```
工具：mcp__atlassian__getAccessibleAtlassianResources
```

回傳列表中找到對應 `url` 為 `https://104corp.atlassian.net` 的項目，記下其 `id` 作為後續 `cloudId`。

---

## Step 2：讀取主頁內容

```
工具：mcp__atlassian__getConfluencePage
參數：
  cloudId: "{cloudId}"
  pageId: "{pageId}"
```

回傳重點欄位：
- `title`：頁面標題
- `body.storage.value` 或 `body.atlas_doc_format.value`：頁面內容
- `version`、`createdBy`、`createdAt`、`updatedAt`：版本資訊
- `_links.webui`：完整 URL

**內容轉換規則（Confluence storage → Markdown）**：

| Confluence 元素 | Markdown 對應 |
|----------------|--------------|
| `<h1>` ~ `<h6>` | `#` ~ `######` |
| `<p>` | 段落 |
| `<table>` / `<tr>` / `<th>` / `<td>` | Markdown 表格 |
| `<ul>` / `<ol>` / `<li>` | `-` / `1.` 條列 |
| `<strong>` / `<em>` | `**bold**` / `*italic*` |
| `<a href="...">` | `[text](url)` |
| `<code>` / `<pre>` | inline code / fenced code block |
| `<ac:structured-macro name="info/warning/note">` | `> ℹ️ INFO`、`> ⚠️ WARNING`、`> 📝 NOTE` |
| `<ac:structured-macro name="code">` | 三反引號程式碼區塊（含 language） |
| `<ac:image>` → `<ri:attachment ri:filename="...">` | `![filename](images/{page-slug}-{filename})` |
| `<ac:link>` → `<ri:page ri:content-title="...">` | `[頁面標題](#{標題-anchor})` |

**轉換原則**：
- 忠實呈現，不省略、不補充
- Confluence 的 macro 若無法對應，用 `> 📌 Confluence Macro: {name}` 標記並保留可見文字
- 表格欄位過多時不要硬擠，可改用「欄位 / 內容」垂直格式

---

## Step 3：下載頁面附件與圖片

讀取頁面附件清單。Atlassian MCP 沒有直接「列出附件」的工具，但 `getConfluencePage` 回傳的 `body` 內會內嵌 `<ac:image>` 與 `<ri:attachment>`。從中解析所有 `ri:filename`。

**附件下載路徑**（透過 `mcp__atlassian__fetch`）：

```
工具：mcp__atlassian__fetch
參數：
  url: "https://104corp.atlassian.net/wiki/download/attachments/{pageId}/{filename}"
```

- 圖片副檔名（`.png`、`.jpg`、`.jpeg`、`.gif`、`.svg`、`.webp`）→ 存至 `images/{page-slug}-{filename}`
- 其他副檔名（`.pdf`、`.xlsx`、`.docx`、`.zip` 等）→ 存至 `files/{page-slug}-{filename}`

若 `mcp__atlassian__fetch` 無法直接寫入二進位檔案，改用以下備援：
1. 用 `fetch` 取得 base64 內容
2. 透過 Bash `base64 -d` 解碼後寫入目標路徑

**檔名清理**：
- URL decode（`%20` → 空白等）
- 把空白轉 `_`
- 移除 `/`、`\`、`:` 等不合法字元

---

## Step 4：處理子頁面

**僅在 `mode=full` 或 `mode=descendants-only` 或 `mode=pages-from-list` 時執行。**

```
工具：mcp__atlassian__getConfluencePageDescendants
參數：
  cloudId: "{cloudId}"
  pageId: "{pageId}"
  depth: "all"     # 取全部層級
```

回傳子頁列表，含 `id`、`title`、`parentId`。

### 依 mode 處理：

**`mode=full`**（全部子頁都抓）：
- 對每個子頁重複 Step 2 + Step 3
- 在 `spec.md` 中以階層 `##` ~ `######` 排列
- 父子關係依 `parentId` 還原樹狀結構

**`mode=descendants-only`**：
- 將樹狀結構輸出至 `{repo}/ra-docs/{Jira單號}/confluence-sitemap.md`，**不讀子頁內容**
- 格式：
  ```markdown
  # Confluence Sitemap

  > 來源：[Confluence 主頁 URL]
  > 主頁：{主頁標題} ({pageId})

  - {主頁標題}
    - {子頁 1 標題} ({pageId})
      - {孫頁 1 標題} ({pageId})
    - {子頁 2 標題} ({pageId})
  ```
- 完成後直接跳到 Step 6

**`mode=pages-from-list`**：
- 讀取 `pages_file`，解析「## 需讀取」區塊下的條列項目作為目標頁面標題清單
- 與 descendants 結果比對：
  - 完全相符 → 列入讀取目標
  - 找不到 → 在輸出最後一段「⚠️ 清單中以下頁面未在 Confluence 找到：...」標明
- 僅讀取目標頁面（主頁強制納入）

---

## Step 5：組合 Markdown 輸出

```markdown
# {主頁標題}

> 來源：{Confluence URL}
> Jira：{Jira單號}
> 最後更新：{updatedAt}
> 轉換日期：{今天日期}

---

## {主頁標題}

{主頁內容}

---

## {子頁 1 標題}

{子頁 1 內容}

### {孫頁 1 標題}

{孫頁 1 內容}

---

## {子頁 2 標題}

{子頁 2 內容}
```

### 格式規則

- **頁面標題層級**：主頁用 `##`，子頁依層級遞增（最深到 `######`）
- **圖片引用**：相對路徑 `images/{page-slug}-{filename}`
- **附件引用**：在原處標注 `📎 附件：[{原始檔名}](files/{page-slug}-{filename})`
- **保留原始文案**：完全保留，不修改措辭、不補充、不省略
- **頁面間分隔**：用 `---` 水平線

---

## Step 6：儲存輸出與摘要

依 mode 不同：

- **`mode=descendants-only`**：
  - 僅輸出 `confluence-sitemap.md`
  - 告知使用者「Confluence sitemap 已輸出，共 N 個頁面」

- **`mode=full` / `mode=page-only` / `mode=pages-from-list`**：
  - 寫入 `{repo}/ra-docs/{Jira單號}/spec.md`
  - 告知使用者：
    - 輸出目錄完整路徑
    - 共轉換頁面數（`pages-from-list` 模式另列「實際讀到 vs. 清單未匹配」）
    - 圖片數量（列出檔名）
    - 附件數量（列出檔名）

輸出摘要格式：

```
✅ Confluence 已轉換為 Markdown

📁 輸出位置
   {repo}/ra-docs/{Jira單號}/
   ├── spec.md                    （{N} 個頁面）
   ├── confluence-sitemap.md      （若有子頁）
   ├── images/                    （{X} 張圖片）
   └── files/                     （{Y} 個附件）

📖 已讀取頁面
   - {主頁標題}
   - {子頁 1}
   - ...

{若有未匹配項目}
⚠️ 未在 Confluence 找到的清單項目：
   - {標題}
```

---

## 注意事項

- **全程只用 `mcp__atlassian__*` MCP 工具**，禁止啟動 playwright 或瀏覽器
- 內容轉換忠實呈現，不推測、不補充規格書中沒寫的內容
- Confluence macro 無法完整還原時，標記 `> 📌 Confluence Macro: {name}` 讓上游知道有資訊遺失
- 若 `getConfluencePage` 回傳的 `body` 為空，先嘗試以 `body-format: atlas_doc_format` 重新取得
- 圖片下載失敗時，於 `spec.md` 對應位置標記 `⚠️ 圖片下載失敗：{filename}`，繼續處理其他內容（不中斷）
- 多個頁面同名附件，以 `{page-slug}-` 前綴隔開，避免覆蓋

---

## 範例觸發語句

應觸發此 skill：
- `幫我把這份 Confluence 轉成 MD：https://104corp.atlassian.net/wiki/spaces/.../pages/123/...`
- `讀取這個 Confluence 規格`
- `Confluence 轉 Markdown`

由其他 skill 呼叫的情境：
- `jira-to-spec` 偵測到 Jira 內容含 `104corp.atlassian.net/wiki/` 連結時自動呼叫
