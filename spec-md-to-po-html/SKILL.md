---
name: spec-md-to-po-html
description: >
  當使用者要求把 ra-docs 下的規格書 / 補問清單 / index 轉成 PO 友善的 HTML 時觸發。
  觸發語句包含但不限於：「VIPOP-XXXXX HTML 化」、「把 VIPOP-XXXXX 的 checklist 轉 HTML」、
  「VIPOP-XXXXX PO 版」、「給 PO 看的 HTML」、「VIPOP-XXXXX 規格書 HTML」。
  也會被 jira-to-spec skill 在 Step 6.5 詢問使用者後呼叫。
  自動讀取 {repo}/ra-docs/{ISSUE_KEY}/ 下的 .md 檔案，產出對應的 .html 至 html/ 子目錄。
compatibility: "需要 filesystem MCP；輸入須為 jira-to-spec 已產出的 ra-docs 結構"
---

# Spec MD to PO HTML — 規格書 / 補問清單 HTML 化

## 與 jira-to-spec 的分工

| Skill | 職責 |
|-------|------|
| jira-to-spec | 內容生成(.md) |
| spec-md-to-po-html | 表現層轉換(.md → .html) |

兩者完全解耦：HTML 化失敗不影響 .md 可用性；.md 內容更新後可隨時重跑此 skill 重新生成 HTML。

---

## 觸發後執行步驟總覽

```
Step 0:收集資訊與前置作業
Step 1:盤點輸入檔案(checkList / spec / sub-spec / index)
Step 2:讀取共用樣式與腳本範本
Step 3:逐檔轉換
  ├─ checkList.md  → checkList.html  (互動式)
  ├─ {ISSUE_KEY}-spec.md → spec.html (閱讀型,單一情境)
  ├─ {ISSUE_KEY}-NN-{topic}.spec.md → 對應 html(複合情境)
  └─ {ISSUE_KEY}-index.md → index.html(複合情境)
Step 4:寫入 html/ 子目錄
Step 5:對話輸出摘要
```

---

### Step 0:收集資訊與前置作業

**0A. 必要資訊**

若對話中未提供,同時詢問:
1. **Jira 單號**(例如 VIPOP-44376)
2. **repo 在本機的絕對路徑**(例如 `/Users/yourname/projects/my-repo`)

若使用者是從 jira-to-spec 流程接續呼叫,以上兩項通常已知,直接沿用。

**0B. 確認輸入目錄存在**

```bash
ls {repo}/ra-docs/{ISSUE_KEY}/
```

若目錄不存在 → 提示「請先用 jira-to-spec 產出規格書,再進行 HTML 化」並停止執行。

**0C. 準備輸出子目錄**

```bash
rm -rf {repo}/ra-docs/{ISSUE_KEY}/html
mkdir -p {repo}/ra-docs/{ISSUE_KEY}/html
```

> 每次重跑都清空,避免舊版本 .html 殘留。

---

### Step 1:盤點輸入檔案

在 `{repo}/ra-docs/{ISSUE_KEY}/` 下偵測下列檔案,決定要轉換哪些:

| 偵測檔案 | 對應 HTML | 情境 |
|---------|----------|------|
| `{ISSUE_KEY}-checkList.md` | `html/checkList.html` | 必有 |
| `{ISSUE_KEY}-spec.md` | `html/spec.html` | 單一情境才有 |
| `{ISSUE_KEY}-index.md` | `html/index.html` | 複合情境才有 |
| `{ISSUE_KEY}-NN-{topic}.spec.md`(多份) | `html/NN-{topic}.spec.html`(多份) | 複合情境才有 |

**判斷情境**:
- 有 `{ISSUE_KEY}-index.md` → **複合情境**,處理 index + 所有子 spec + checkList
- 無 `{ISSUE_KEY}-index.md` → **單一情境**,處理 spec + checkList

將盤點結果列出,供 Step 3 逐檔處理。

---

### Step 2:讀取共用樣式與腳本範本

從 skill 目錄讀取:
- `references/styles.css` — 共用樣式(內聯到每份 HTML 的 `<style>`)
- `references/checklist.js` — checkList 專用互動腳本
- `references/spec.js` — spec / index 專用(目錄導覽、Mermaid 渲染)

讀取失敗 → 使用本檔末尾「內建備用範本」,並告知使用者。

---

### Step 3:逐檔轉換

#### 3A. checkList.md → checkList.html

**輸入**:`{ISSUE_KEY}-checkList.md`(由 jira-to-spec Step 5 產出)

**解析重點**:
1. 抽取 frontmatter(若有)取得 issue_key、composite 旗標
2. 識別三級分類標題:`### 🔴 Blocker`、`### 🟡 Warning`、`### 🟢 Info`
3. 識別跨子情境段落:`## 🔴 Blocker — 全票阻塞問題(跨子情境)`
4. 識別子情境分群:`## 子情境 NN:{topic_zh}`
5. 每題抽取:
   - 題號(`Q-001`)
   - 題目內容
   - 選項(`- [ ] A. ...`)及推薦標記(原文中含「(建議)」)
   - `[子 spec NN]` 標籤(用於子情境歸屬)
6. AI 假設區(`### 🟢 Info` 下的 `- A-001:...`)

**輸出 HTML 結構**(依 mockup `VIPOP-1234-checkList.html` 為準):

- 頂部統計列:總題數、Blocker 數、Warning 數、AI 假設數
- 跨子情境 Blocker 區塊(若有)放最前
- 子情境分組區塊(複合情境才有),每子情境內按 Blocker → Warning 排
- AI 假設區塊放最後
- 底部三顆按鈕:複製 Jira 回覆 / 匯出 JSON / 列印
- 內嵌 `references/styles.css` + `references/checklist.js`(把 `{{ISSUE_KEY}}` 替換成實際單號)

**選項解析規則**:
- `- [ ] A. 文字` → 選項 A,內容「文字」
- `- [ ] A. 文字(建議)` → 選項 A,自動加上 `<span class="recommend">建議</span>`
- `- [ ] C. 其他:___` → 選項 C 自動加入文字輸入框(`class="other-input" data-other="Q-NNN"`)
- 含 `` `代碼` `` 的選項 → 包成 `<code>` 標籤

**每個 input 必備屬性**(供 checklist.js 正確讀寫):
- radio:`name="q-001" data-q="Q-001" value="A|B|C"`
- AI 假設 checkbox:`data-q="A-001"`,預設 `checked`
- 其他輸入框:`class="other-input" data-other="Q-001"`

**localStorage key**:`po-checklist-{ISSUE_KEY}`

#### 3B. spec.md / NN-{topic}.spec.md → 對應 html

**輸入**:單一情境的 `{ISSUE_KEY}-spec.md` 或複合情境的 `{ISSUE_KEY}-NN-{topic}.spec.md`

**轉換策略**:
1. **Markdown → HTML**:使用標準 Markdown 規則,但要保留以下特殊處理:
   - Mermaid 程式碼塊(` ```mermaid `)→ `<div class="mermaid">...</div>`(用 CDN 自動渲染)
   - `⚠️` 警告標記 → 包成 `<span class="spec-warning">`,PO 一眼看到
   - `🤖 AI 建議` → 包成 `<span class="ai-suggest">`
   - 圖片相對路徑 `images/xxx.png` → 改為 `../images/xxx.png`(因為 html/ 在子目錄)
   - 附件參考 `參考附件:{檔名}` → 連結到 `../files/{檔名}`
2. **左側目錄 sidebar**:從 H2 標題自動生成,可點跳轉(`<a href="#sec-N">`),用 `.layout` + `.sidebar` 排版,sticky 在視窗左側
3. **頂部 frontmatter 摘要卡**:顯示 scope、type、sections_filled、generated_at
4. **頁尾連結**:複合情境的子 spec 互相連結;單一情境連回 checkList.html
5. 內嵌 `references/styles.css` + `references/spec.js`

#### 3C. index.md → index.html(僅複合情境)

**輸入**:`{ISSUE_KEY}-index.md`(由 jira-to-spec Step 4C 產出)

**轉換重點**:
1. 子 spec 列表的 Markdown 表格 → HTML 表格,每列「主題」欄變成跳到對應 `.spec.html` 的連結
2. 「共用資源」段落的檔案連結 → 都改成相對路徑(`./checkList.html`、`../jira.md` 等)
3. 頂部加總覽卡:`N 份子 spec` / `總題數` / `Blocker 數`(從 checkList 抽出)
4. 內嵌簡化樣式(不需要 Mermaid,可省略 spec.js 的 Mermaid 段)

---

### Step 4:寫入 html/ 子目錄

最終輸出結構:

#### 4A. 單一情境
```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── (既有 .md / images / files 不動)
  └── html/
      ├── checkList.html
      └── spec.html
```

#### 4B. 複合情境
```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── (既有 .md / images / files 不動)
  └── html/
      ├── index.html
      ├── checkList.html
      ├── 01-{topic}.spec.html
      ├── 02-{topic}.spec.html
      └── 03-{topic}.spec.html
```

**重要**:單檔自包含(CSS 內聯、JS 內聯),只有 Mermaid 用 CDN。檔案可以單獨複製到任何地方都能開。

---

### Step 5:對話輸出摘要

```
✅ HTML 化完成

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/html/
   ├── index.html        ← PO 從這裡開始閱讀(複合情境)或直接看 checkList.html(單一情境)
   ├── checkList.html    ← 互動式補問清單(可勾選 + 複製回 Jira)
   ├── spec.html / NN-*.spec.html
   ...

🎨 互動功能
   - localStorage 自動暫存(關閉再開不會掉答案)
   - 「複製 Jira 回覆格式」按鈕:整理成 Markdown 直接貼回 Jira comment
   - 匯出 JSON / 列印 / PDF 存檔

💡 給 PO 的話術建議:
   「{ISSUE_KEY} 的補問清單我整理成可勾選的 HTML 了,在 ra-docs/{ISSUE_KEY}/html/checkList.html。
    勾完選項按下方『複製 Jira 回覆格式』,把內容貼回這張票的 comment 即可。」
```

---

## 注意事項

- **絕不修改原 .md 檔案**:本 skill 只讀,所有產出在 `html/` 子目錄
- **單檔自包含**:CSS / JS 全部內聯,只允許 Mermaid 用 CDN(`cdn.jsdelivr.net`)
- **路徑全部相對**:`html/` 內的 .html 引用 `../images/xxx.png`、`../files/xxx.pdf`
- **dark mode 自動**:透過 `@media (prefers-color-scheme: dark)` 自動切換
- **無外部依賴**:不用 React / Vue / 任何框架,純 vanilla,確保 PO 端任何瀏覽器都能開
- **不寫回 Jira**:本 skill 只負責產 HTML;若 PO 答案需自動寫回 Jira,屬未來 `checklist-reply-to-jira` skill 範圍

---

## 範例觸發語句

應觸發此 skill:
- `把 VIPOP-44376 的 checklist 轉成 HTML`
- `VIPOP-567 PO 版`
- `幫 VIPOP-111 的規格書產 HTML`
- `VIPOP-890 HTML 化`

不應觸發:
- `寫 VIPOP-1234 規格書` → 觸發 jira-to-spec
- `分析 VIPOP-1234` → 觸發 jira-analyzer

---

## 內建備用範本(references 讀取失敗時使用)

> 正常情況下 Step 2 會從 `references/` 讀取最新版本,此處僅作 fallback。
> 完整範本請參考 `references/styles.css`、`references/checklist.js`、`references/spec.js`。

**最小可用 CSS**:採用 mockup 的色彩變數系統與卡片排版。關鍵變數:
- 警示色:Blocker `#FCEBEB`/`#A32D2D`、Warning `#FAEEDA`/`#BA7517`、Info `#E6F1FB`/`#185FA5`
- 子情境色:01 紫 `#EEEDFE`、02 綠 `#E1F5EE`、03 珊瑚 `#FAECE7`
- 字級:H1 22px、H2 18px、H3 16px、Body 15px、font-weight 400 / 500

**最小可用 JS**:
- localStorage 暫存所有 radio / checkbox 狀態
- 進度條:已答題數 / 總題數
- 複製按鈕:組裝成 Markdown 後寫入 `navigator.clipboard`
- 匯出 JSON:`Blob` + 動態 `<a download>`
