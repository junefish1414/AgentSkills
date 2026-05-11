---
name: axure-to-md-cli
description: 使用 playwright-cli 將 Axure prototype 規格書轉換成 Markdown 文件。當使用者提供 Axure 網址並要求轉換、閱讀、或整理規格內容時觸發（若同時有 axure-to-md skill 可選擇，優先使用本 skill）。觸發語句包含但不限於：「幫我把這個 Axure 轉成 MD」、「把 Axure 規格書轉成文字」、「讀取這個 Axure 網址」、「Axure 轉 Markdown」。
---

# Axure 規格書轉 Markdown（playwright-cli 版）

使用 `playwright-cli` CLI 工具開啟並閱讀 Axure prototype，將規格內容完整、精確地轉換成 Markdown 文件，連同說明圖片一併儲存到指定位置。

## 前置準備

開始前依序確認以下資訊（若未提供則詢問使用者）：

1. **Axure 網址**
2. **網站密碼**（若有設定）
3. **Jira 單號**（例如 VIPOP-12345），用於決定輸出目錄名稱
4. **repo 路徑**：輸出目錄為 `{repo}/ra-docs/{Jira單號}/`。請使用者提供 ` repo 的本機路徑（例如 `/Users/yourname/projects/104.vip.f2e.recruitment`）。

輸出目錄結構：

```
{repo}/ra-docs/{Jira單號}/
├── spec.md                        # 主要規格文件
└── images/                        # 說明圖片（若有）
    ├── 版本紀錄-時程甘特圖.png
    ├── 一般booking-曝光管道選擇.png
    └── ...
```

- `spec.md` 為主要規格文件，放在 `{repo}/ra-docs/{Jira單號}/spec.md`
- 說明圖片統一放在 `{repo}/ra-docs/{Jira單號}/images/` 子目錄下
- `spec.md` 內引用圖片時使用相對路徑，例如 `images/一般booking-曝光管道選擇.png`

確認 playwright-cli 可用，若指令不存在請提示使用者安裝：

```bash
playwright-cli --version
# 若未安裝，提示使用者執行：npm install -g @playwright/cli@latest
```

> **重要**：本 skill 全程只使用 `playwright-cli` CLI 指令（透過 Bash 工具執行）。
> **嚴格禁止**使用 `mcp__playwright__` 系列 MCP 工具。即使 MCP 工具可用，也不能改用。
> 兩者行為不同（session 管理、指令格式、截圖路徑皆有差異），混用會導致非預期結果。

## 開啟 Axure 並輸入密碼

```bash
playwright-cli open <url>
playwright-cli snapshot
```

若快照中出現密碼欄位，填入密碼並送出：

```bash
playwright-cli fill <password-input-ref> "<password>"
playwright-cli press Enter
```

等待主畫面載入後再次取得快照確認成功進入。

## 讀取分頁清單

Axure Share 左側有頁面樹狀清單（sitemap panel）。

1. 從快照中找到左側邊欄的頁面樹，辨識所有分頁名稱與層級（縮排代表父子關係）
2. 若側邊欄未顯示，尋找漢堡選單或頁面圖示按鈕並點擊展開
3. 展開所有可展開的群組以取得完整清單
4. **略過條件**：分頁名稱包含「不用看」者，連同其所有子頁面一起略過
5. 記錄需要讀取的分頁順序清單（含層級資訊）

## 逐頁讀取規格

對清單中每一個分頁依序執行：

### 切換到該頁

```bash
playwright-cli click <page-ref>
playwright-cli snapshot
```

### 完整讀取文字內容

**優先使用 snapshot 讀取文字**：

```bash
playwright-cli snapshot
```

snapshot 回傳可存取性樹狀結構，包含所有文字、表格、條列內容。

**頁面超出視窗時，系統性捲動讀完整頁**：

```bash
# 確認頁面尺寸
playwright-cli eval "({sh: document.body.scrollHeight, vh: window.innerHeight})"

# 向下捲動（每次約 80% 視窗高度）
playwright-cli mousewheel 0 800
playwright-cli snapshot

# 若有水平捲動
playwright-cli mousewheel 800 0
playwright-cli snapshot
```

### 儲存說明圖片

**預設不截圖**。只有在 snapshot 文字內容無法傳達規格的情況下才截圖。

**需要截圖的條件（必須同時符合）**：

1. snapshot 中出現 `img`、`canvas`、`svg` 等圖形元素，且圖形本身帶有規格資訊（不是裝飾圖）
2. 且這些資訊無法從文字 snapshot 中讀出（例如：純圖形的動線流程圖、帶有標注框的 UI 示意圖、甘特圖）

**不需要截圖的情況**：

- 頁面的所有規格內容都已在 snapshot 文字中（即使有圖片裝飾也不截）
- 圖片只是視覺輔助，規格文字本身已完整
- 頁面是空的資料夾節點

**截圖方法（依情況選擇）：**

> ⚠️ **重要警告**：Axure 頁面中 img 元素混雜「規格大圖」與「標注數字圓圈」（如 ①②③），兩者都是 img，但尺寸差異極大。**絕對不可直接用 ref 順序截圖**，必須先過濾尺寸才能找到正確目標。

**方法 A：截頁面中的特定大圖（有獨立 img element）**

先用 eval 列出 iframe 內所有 img 的尺寸，過濾出寬或高 > 150px 的圖，再截：

```bash
# 步驟 1：列出所有 img 的 id 與尺寸，找出大圖
playwright-cli eval "Array.from(document.querySelector('iframe').contentDocument.querySelectorAll('img')).map(img => ({ id: img.id, w: img.naturalWidth || img.offsetWidth, h: img.naturalHeight || img.offsetHeight })).filter(i => i.w > 150 || i.h > 150)"

# 步驟 2：從結果中取得 id（例如 u14_img），然後從 snapshot 找到對應 ref
playwright-cli snapshot  # 比對 id 找到 ref，例如 img [ref=f1e53]

# 步驟 3：截圖
playwright-cli screenshot <img-ref> --filename "{repo}/ra-docs/{Jira單號}/images/{檔名}.png"
```

> 若步驟 1 回傳的 `naturalWidth` 為 0（圖片尚未載入），改用 `offsetWidth`/`offsetHeight`。

**方法 B：BEFORE/AFTER 對比圖、整頁截圖（優先使用此方法截 Axure 的 UI 示意圖）**

Axure 的 BEFORE/AFTER 對比圖通常是把多張 img 排列在一個容器中，個別截容易截錯。改為調整視窗至 iframe 實際尺寸，整頁截 iframe：

```bash
# 步驟 1：取得 iframe 內容的實際尺寸與 offset
playwright-cli eval "(() => { const f = document.querySelector('iframe'); const d = f.contentDocument; const r = f.getBoundingClientRect(); return {scrollWidth: d.body.scrollWidth, scrollHeight: d.body.scrollHeight, left: Math.round(r.left), top: Math.round(r.top)}; })()"

# 步驟 2：調整視窗大小（width = scrollWidth + left，height = scrollHeight + top）
playwright-cli resize {width} {height}

# 步驟 3：確認 iframe 已完整展開（scrollW 應等於 clientW，scrollH 應等於 clientH）
playwright-cli eval "(() => { const f = document.querySelector('iframe'); const d = f.contentDocument; return {scrollW: d.body.scrollWidth, clientW: f.clientWidth, scrollH: d.body.scrollHeight, clientH: f.clientHeight}; })()"

# 步驟 4：截 iframe 整體
playwright-cli snapshot  # 找 iframe [ref=eXXX]
playwright-cli screenshot <iframe-ref> --filename "{repo}/ra-docs/{Jira單號}/images/{檔名}.png"
```

> **注意**：步驟 3 確認 `scrollW === clientW` 且 `scrollH === clientH`，代表內容完全可見。若不相等，重新確認 offset 後再調整。

**截後驗尺寸（每張截完都要做）**

```bash
# 確認截圖不是小圖（標注圓圈通常 < 50px）
playwright-cli eval "(() => { const img = new Image(); img.src = 'file://{檔名}.png'; return {w: img.naturalWidth, h: img.naturalHeight}; })()"
```

若截出來的圖小於 100x100，代表截到了標注圓圈，需重新用方法 A 步驟 1 過濾尺寸後重截。

**圖片命名規則**：`{頁面名稱}-{描述}.png`，例如：

- `一般booking-曝光管道選擇介面.png`
- `版本紀錄-時程甘特圖.png`
- `頁面盤點-動線流程圖.png`

同一頁面若需多張（例如長頁面的不同區塊），加序號：`一般booking-預約明細-01.png`、`一般booking-預約明細-02.png`

### 解讀內容

從 snapshot 和截圖中辨識並記錄：

**文字內容**

- 標題、說明文字、按鈕文案、標籤、placeholder
- 表格：辨識欄位名稱（表頭）與每列內容，轉成 Markdown 表格
- 條列式清單：保留層級與順序

**需要搭配圖片才能理解的規格**

若某段規格需要搭配說明圖片才能完整理解，在 MD 文件中明確標出對應圖片，並加上清楚解說：

```markdown
**畫面說明**（參考圖片：`images/一般booking-曝光管道選擇.png`）

圖中展示曝光管道的選擇介面，由上至下依序為：
- 焦點職缺（橘色標記，預設勾選）
- 精選工作（綠色標記）
- 優先推薦（紫色標記，顯示「推薦」標籤）

右側文字說明各管道的預設勾選規則（詳見項次 2.3）。
```

**標注說明**（若圖片有編號標注）：

```markdown
**標注說明**（參考圖片：`images/一般booking-預約明細-01.png`）
- 標注 ①：預約明細區塊，依日期分組
- 標注 ②：「使用X則│剩Y則」統計，位於明細上方
- 標注 ③：紅色提醒文案，當有管道檔次已滿時出現
```

**不要推測或補充規格書中沒有寫出來的內容。只記錄你實際看到的。**

## 組合 Markdown 輸出

### 文件結構

```markdown
# [Axure 文件標題]

> 來源：[Axure 網址]
> Jira：[Jira單號]
> 轉換日期：[今天日期]

---

## [頁面名稱]

[頁面內容]

---

### [子頁面名稱]

[子頁面內容]
```

### 格式規則

- **頁面標題層級**：頂層分頁用 `##`，子頁面用 `###`，以此類推，最多到 `######`
- **表格**：轉成標準 Markdown 表格格式
- **圖片引用**：使用相對路徑 `images/{檔名}.png`，並附上解說
- **原始文案**：完全保留，不修改措辭、不補充、不省略
- 分頁之間用 `---` 水平線分隔

## 儲存輸出

將完整 Markdown 內容寫入 `{repo}/ra-docs/{Jira單號}/spec.md`，並告知使用者：

- 輸出目錄的完整路徑
- 共轉換了幾個分頁
- 共儲存了幾張說明圖片（列出檔名）
- 若有略過「不用看」的分頁，列出被略過的名稱

## 結束後關閉瀏覽器

```bash
playwright-cli close
```

## 注意事項

- **全程只用 `playwright-cli` CLI，禁止使用 `mcp__playwright__` MCP 工具**
- **優先使用 `snapshot` 而非截圖**：snapshot 直接讀取 DOM 文字，比視覺辨識更準確，也更省 token；只有在確認需要圖片輔助理解時才截圖
- Axure 頁面通常有 iframe，若 snapshot 無法讀取內容，嘗試 `playwright-cli eval "document.querySelectorAll('iframe')[0].contentDocument.body.innerText"`
- 若某分頁完全空白或只有裝飾圖形沒有文字，標記「（此頁無文字規格）」
- 遇到動態內容（展開/收合元件），嘗試點擊展開後再 snapshot
- 不要因為頁面很多就跳過或縮短內容，每頁都要完整閱讀
- Session 預設在記憶體中，不需要額外管理；若要同時處理多個 Axure 文件，用 `-s=<name>` 指定不同 session

