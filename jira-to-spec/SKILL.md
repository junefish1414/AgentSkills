---
name: jira-to-spec
description: >
  當使用者提到 Jira 任務單號並要求產出「規格書」時觸發。
  觸發語句包含但不限於：「幫 VIPOP-XXXXX 寫規格書」、「把 VIPOP-XXXXX 整理成規格書」、
  「VIPOP-XXXXX 的規格書」、「幫我產這張票的 spec」、「VIPOP-XXXXX spec」。
  自動透過 Atlassian MCP 讀取 Jira 任務內容，結合規格書標準模板，
  產出規格書 Markdown 與 HTML 檔案至 {repo}/ra-docs/{ISSUE_KEY}/。
  注意：若使用者只說「分析 VIPOP-XXXXX」而未提及規格書/spec，應觸發 jira-analyzer 而非此 skill。
compatibility: "需要 Atlassian MCP、filesystem MCP；Axure / Confluence 規格皆以 PDF 為主要知識庫（不再使用 axure-to-md / playwright）；若使用者不提供 Confluence PDF 則 fallback 至 confluence-to-md skill"
---

# Jira to Spec — 從 Jira Ticket 產出規格書

## 與 jira-analyzer 的分工

| Skill | 觸發條件 | 產出物 |
|-------|---------|--------|
| jira-analyzer | 「分析」「評估」「看一下」 | 技術分析報告 |
| jira-to-spec | 「規格書」「spec」「寫規格」 | 規格書文件檔案 |

---

## 執行步驟總覽

```
Step 0:收集資訊與前置作業
Step 1:取得 Jira 任務資料(+ Axure 偵測)
Step 2:平行派出 subagent
  ├─ Subagent A → 產出 jira.md
  └─ Subagent B/C → 產出 PDF 索引(僅在有 PDF 時)
                          ↓
                    【資料庫快照建立完成】
                          ↓
Step 3:判斷需求類型與情境組合
  ├─ 3-3A 單一情境 → Step 4B-1 → 5A → 5C → 6A → 7A(主檔)
  └─ 3-3B 複合情境 → references/composite.md
        (§1 拆分 → §2 填充 → §3 index → §4 補問清單 → 5C → §5 輸出 → §6 摘要)
  (5C:單一/複合都跑——依各題 🔗 影響 呼叫 blocker-overview 產 overview.html — 阻塞圖 + 可開工比例 + 待決問題詳述)
Step 6.5:詢問是否產出 PO 友善 HTML(每次必問)
Step 7:對話輸出摘要
```

---

### Step 0：收集資訊與前置作業

**0A. 向使用者收集必要資訊**

若對話中尚未提供，請同時詢問：
1. **Jira 單號**（例如 VIPOP-44376）
2. **repo 在本機的絕對路徑**（例如 `/Users/yourname/projects/my-repo`）

收到兩項資訊後，才繼續執行後續步驟。

---

**0B. 清空並重建輸出目錄**

每次執行都要做，確保不保留舊版本殘留：

```bash
rm -rf {repo}/ra-docs/{ISSUE_KEY}
mkdir -p {repo}/ra-docs/{ISSUE_KEY}/files
```

---

**0C. 讀取最新模板**

用 filesystem MCP 讀取 `{SKILL_REPO}/jira-to-spec/references/template.md`：
- 成功 → 作為規格書結構
- 失敗 → **中止流程**，告知使用者 template.md 讀取失敗（含嘗試的路徑），請修復後重試

---

### Step 1：取得 Jira 任務資料

```
工具：mcp-atlassian:jira_get_issue
參數：
  issue_key: "{ISSUE_KEY}"
  fields: "summary,description,issuetype,status,priority,assignee,reporter,
           labels,duedate,subtasks,issuelinks,parent,comment"
  comment_limit: 20
```

解析重點：
- `description`：主要規格來源
- `comment`：含「改為」「調整」「要補做」的留言視為規格補充，一併納入
- `subtasks`：列出子任務清單，納入影響範圍

**偵測外部規格連結（在 description 與所有 comment 中搜尋）**：

掃描 description 與所有 comment 的文字，分別尋找以下兩種規格來源：

1. **Confluence 連結**：包含 `104corp.atlassian.net/wiki/` 的 URL
2. **Axure 連結**：包含 `axshare.com` 的 URL

依偵測結果分流（**一次詢問使用者提供 PDF**）：

| Confluence | Axure | 流程 |
|------------|-------|------|
| 有 | 無 | Confluence-only：進入 Step 1A 收 Confluence PDF |
| 無 | 有 | Axure-only：進入 Step 1A 收 Axure PDF |
| 有 | 有 | 兩者並存：進入 Step 1A 一次收兩份 PDF |
| 無 | 無 | 跳過 Step 1A，直接進入 Step 2 |

---

**Step 1A：一次詢問使用者提供規格 PDF（僅在偵測到外部連結時執行）**

向使用者一次詢問所有偵測到的外部規格 PDF，避免來回多輪互動。

詢問模板（依情境組合）：

> 「偵測到以下外部規格來源：
> {若有 Confluence}- Confluence：`{confluence_url}`（建議提供 **Confluence PDF**）
> {若有 Axure}- Axure：`{axure_url}`（請提供 **Axure PDF**）
>
> ⚠️ **Confluence PDF 強烈建議提供**：因 Atlassian Cloud API 限制，
> 直接讀取 Confluence 將無法取得頁面上的圖片，Agent 看不到圖會導致規格遺失。
> 提供 PDF 可確保完整解析（文字 + 圖片）。
>
> ⚠️ **Axure**：本流程不再使用 playwright 爬取線上 Axure，
> 請提供 Axure 匯出的 PDF 作為知識庫。
>
> 請提供 PDF 的本機絕對路徑（或回覆「無」）：
> - Confluence PDF：________
> - Axure PDF：________」

依使用者回覆分四種狀況：

1. **提供 Confluence PDF** → 複製到 `{repo}/ra-docs/{ISSUE_KEY}/files/confluence-spec.pdf`
2. **提供 Axure PDF** → 複製到 `{repo}/ra-docs/{ISSUE_KEY}/files/axure-spec.pdf`
3. **Confluence 連結存在但未提供 PDF** → 二次確認：

   > 「未提供 Confluence PDF。
   > 因 Atlassian Cloud 限制，直接抓取的 Confluence 內容**不含圖片**，
   > Agent 無法感知圖片內容，可能導致規格遺失。
   > 是否仍要繼續使用 API 抓取（fallback 至 confluence-to-md）？(y/N)」

   - 選 **是** → 標記 `confluence_fallback=true`，Step 2 將呼叫 `confluence-to-md`
   - 選 **否** → 中止流程，提示使用者準備 PDF 後重試

4. **Axure 連結存在但未提供 PDF** → 標記 `axure_skip=true`，Step 2 不處理 Axure（規格書僅參考 Jira / Confluence）。不需二次確認，但 Step 7 摘要**必須**輸出 Axure 缺漏警示

收到使用者回覆後才繼續 Step 2。

---

### Step 2：派出 subagent 收集規格來源

流程改為單階段派出 subagent，依 Step 1 收到的 PDF 與選項決定要不要派 B / C。
**Axure 與 Confluence 都以 PDF 為主要知識來源，不再透過 playwright 線上爬取。**

**外部規格分流提醒**（依 Step 1 結果）：
- 純 Confluence（有 PDF）→ 跑 Subagent C-pdf
- 純 Confluence（無 PDF，使用者選擇 fallback）→ 跑 Subagent C-api
- 純 Axure（有 PDF）→ 跑 Subagent B-pdf
- 純 Axure（無 PDF）→ 略過 Axure，僅跑 Subagent A
- Confluence + Axure → 依各自 PDF 提供狀況分別派出
- 兩者皆無 → 只跑 Subagent A

---

**Subagent A：整理 Jira 資料**

任務：
1. 將 Jira 的 `description` 與所有 `comment`（優先含「改為」「調整」「要補做」的留言）整理成 Markdown，寫入：
   ```
   {repo}/ra-docs/{ISSUE_KEY}/jira.md
   ```
   格式建議：
   ```markdown
   # {ISSUE_KEY} — {summary}

   ## 描述
   {description 轉 Markdown}

   ## 留言（規格相關）
   ### {留言作者} ({留言時間})
   {留言內容}
   ```

---

**Subagent B-pdf：以 Axure PDF 作為知識庫（取代原本 playwright 爬取）**

僅在 Step 1A 收到 Axure PDF 時派出。

任務：
1. 確認 PDF 位置：`{repo}/ra-docs/{ISSUE_KEY}/files/axure-spec.pdf`（Step 1A 已複製進來）
2. **不轉成 Markdown、不寫 spec.md**，PDF 本身即為知識庫
3. 用 Read tool 對 PDF 做一次完整掃讀（可分頁讀取），產出索引檔：
   ```
   {repo}/ra-docs/{ISSUE_KEY}/axure-pdf-index.md
   ```
   內容為 PDF 章節 / 頁碼 / 主題對照表，方便 Step 4 主 agent 快速定位：
   ```markdown
   # Axure PDF 索引

   > 來源：files/axure-spec.pdf

   | 頁碼 | 章節 / 主題 | 摘要（30 字內） |
   |------|------------|----------------|
   | 1-3 | 封面 / 版本紀錄 | ... |
   | 4-12 | 一般 booking 流程 | ... |
   ```
4. Step 4 主 agent 會視需要直接 Read PDF 指定頁面，不需要產出完整 spec.md。

---

**Subagent C-pdf：以 Confluence PDF 作為知識庫**

僅在 Step 1A 收到 Confluence PDF 時派出。

任務：
1. 確認 PDF 位置：`{repo}/ra-docs/{ISSUE_KEY}/files/confluence-spec.pdf`
2. **不轉成 Markdown、不寫 confluence-spec.md**，PDF 本身即為知識庫
3. 同 Subagent B-pdf，產出 PDF 索引：
   ```
   {repo}/ra-docs/{ISSUE_KEY}/confluence-pdf-index.md
   ```
4. Step 4 主 agent 會視需要直接 Read PDF 指定頁面。

---

**Subagent C-api：fallback 至 confluence-to-md（僅使用者堅持不提供 Confluence PDF 時派出）**

任務：
- 呼叫 `confluence-to-md` skill 的 `mode: full`，傳入 Confluence URL、repo 路徑、Jira 單號
- 該 skill 會：解析 pageId、取得 cloudId、讀主頁 + 全部子頁、嘗試下載附件與圖片（**多半失敗**，Atlassian Cloud 限制）
- 輸出檔：
  ```
  {repo}/ra-docs/{ISSUE_KEY}/confluence-spec.md
  {repo}/ra-docs/{ISSUE_KEY}/confluence-sitemap.md
  ```
- `confluence-spec.md` 即為知識庫，Step 4 主 agent 會 Read 它

---

所有派出的 subagent 完成後，**直接進入 Step 3**。

> 原本的 Step 2-2 / 2-3（Axure sitemap 比對與分頁挑選）已移除——Axure 不再透過 playwright 線上爬取，改用 PDF 知識庫，不需要再做分頁選擇。

---

### Step 3:判斷需求類型與情境組合

**輸入**:`{repo}/ra-docs/{ISSUE_KEY}/jira.md`(若有 `*-pdf-index.md` 或 `confluence-spec.md` 也一併參考)

#### 3-1：抽取並分類 change units
讀取 `references/requirement-types.md`，依其中的 scope / type 定義，
將來源中的改動點抽成 `change_units`（結構見該檔）。

#### 3-2：判斷單一或複合情境（路由叉口）
- **單一情境**（滿足任一）：只有 1 個 change unit；或多個但 (scope, type) 組合全部相同
  → 走 3-3A
- **複合情境**：存在 2 個以上不同的 (scope, type) 組合
  → 走 3-3B，讀取 `references/composite.md` 依其流程處理

#### 3-3A：單一情境
依 `references/requirement-types.md` 的「(scope, type) → Section 對照表」決定要填的 Section，
進入 Step 4B-1 產出單一份 spec。

#### 3-3B：複合情境
完整流程（拆分結構、排序、slug、填充、index、checklist、輸出、摘要）見 `references/composite.md`。

---

### Step 4：讀取來源資料並填充規格書

**Step 4A：讀取所有可用來源**

在填充前，依序讀取以下資料（全部讀完再開始寫）：

1. **`{repo}/ra-docs/{ISSUE_KEY}/jira.md`** — Jira 描述與規格留言
2. **`{repo}/ra-docs/{ISSUE_KEY}/files/confluence-spec.pdf`**（若存在）— Confluence PDF，**主要規格來源**。用 Read tool 帶 `pages` 參數依需求讀指定頁
3. **`{repo}/ra-docs/{ISSUE_KEY}/files/axure-spec.pdf`**（若存在）— Axure PDF，**主要規格來源**。用 Read tool 帶 `pages` 參數依需求讀指定頁
4. **`{repo}/ra-docs/{ISSUE_KEY}/confluence-pdf-index.md`** / **`axure-pdf-index.md`**（若存在）— 由 Subagent B-pdf / C-pdf 產出的 PDF 章節頁碼索引，用來決定要 Read PDF 的哪幾頁
5. **`{repo}/ra-docs/{ISSUE_KEY}/confluence-spec.md`**（若存在）— **僅 fallback 情境**才會有：使用者堅持不提供 Confluence PDF、改走 confluence-to-md 時的產物
6. **`{repo}/ra-docs/{ISSUE_KEY}/confluence-sitemap.md`**（若存在，fallback 情境用）— Confluence 頁面樹
7. **`{repo}/ra-docs/{ISSUE_KEY}/files/`** — 列出所有附件檔名（含上述 PDF）

```bash
# 列出 files/ 內容
ls {repo}/ra-docs/{ISSUE_KEY}/files/
```

**讀取 PDF 的策略**：
- PDF 多半超過 10 頁，**不可一次全讀**（會失敗或太貴）
- 先讀對應的 `*-pdf-index.md` 確認章節頁碼
- 依 Jira 內容找出相關主題，用 Read tool 的 `pages` 參數每次讀 5–20 頁
- 同一份 PDF 可分多次讀，但要避免重複讀同一段

**來源優先順序**（依 Step 1 結果）：
- 有 Confluence PDF → 以 Confluence PDF 為主要規格，`jira.md` 補充
- 有 Axure PDF → 以 Axure PDF 為主要規格，`jira.md` 補充
- 兩份 PDF 都有 → 並列為主要規格；遇到衝突時以 **Confluence 為準**，並在規格書內標注 `📝 註：Axure 與 Confluence 描述不一致，本處採 Confluence`
- 只有 `confluence-spec.md`（fallback 情境）→ 以該檔為主要規格，但需在 Step 7 摘要中提示「Confluence 圖片未納入，規格可能不完整」
- 都沒有 → 僅參考 `jira.md`

**Step 4B：填充規格書**

##### 4B-1:單一情境填充

依 Step 3-3A 決定的 Section 清單填充,遵循以下原則:

1. **忠實呈現**：來源檔未提及用 `⚠️ 未提及，建議與 PM 確認` 標註，不捏造
2. **留言補充**：含「改為」「調整」「要補做」的留言內容納入對應 Section
3. **操作流程附流程圖**：Section 4 每個流程附 Mermaid `flowchart TD`
4. **狀態變化附狀態圖**：Section 7 狀態變化用 Mermaid `stateDiagram-v2`
5. **引用附件**：`files/` 下的附件在相關 Section 標注「參考附件：{檔名}」
6. **Section 16 主動出題**：AI 依需求類型主動補充極端情境，每條標示「🤖 AI 建議」或「⚠️ 未定義」
7. **前端視角**：所有分析以前端工程師角度出發

頂部加入 frontmatter:

```markdown
---
issue_key: VIPOP-1234
scope: feature
type: interaction
sections_filled: [1, 2, 4, 5, 15, 16]
generated_at: 2026-05-14T...
---
```

##### 4B-2：複合情境填充
逐子 spec 的填充流程見 `references/composite.md` §2
（沿用 4B-1 的 7 條，僅把填充範圍限定在各子情境的 change_units）。

#### Step 4C：複合情境的 index 檔
複合情境額外產出的 `{ISSUE_KEY}-index.md`，內容與格式見 `references/composite.md` §3。

---

### Step 5：在規格書中未明確的項目整理成 PO 補問清單

**影響與背景標註總則（5A / 5B 都適用）**：

每個 🔴 Blocker / 🟡 Warning 問題都要標 `🔗 影響` 與 `背景` 兩行，作為 Step 5C overview 圖與詳述卡片的資料源頭：

- **`- 🔗 影響`（必填）**：列出它沒答會卡住哪些項目。
  - **封閉集合**：只能指向「本票實際存在的項目」——已抽出的 change_unit（U1…）、實際要填的 Section（§N）、或其他實際存在的問題（Q-NNN）。**禁止連到清單外不存在的東西**（防幻覺）。
  - **決策鏈**：若某問題要先答了另一題才有意義，用 `Q-NNN` 指向前置題（例如「權限不足怎麼處理」依賴「是否規劃權限模組」）。
  - **沒影響就寫「無」**：確實獨立的問題標 `🔗 影響：無`。
- **`- 背景`（必填）**：前後文——這題從哪來、牽涉哪個功能、為什麼有爭議或未定（例如「Confluence 寫 A、Jira 留言寫 B，兩者打架」）。寫到**沒有專案脈絡的主管也讀得懂在問什麼**。這是 Step 5C overview **詳述卡片「背景」欄的唯一來源，缺了卡片背景就空**。

#### 5A:單一情境

將所有 ⚠️ 彙整,分三級,用選擇題格式,寫入 `{ISSUE_KEY}-checkList.md`:

```markdown
# VIPOP-1234 PO 補問清單

### 🔴 Blocker（必須回答才能開工）
**Q-001：{問題}**
- 🔗 影響：Q-002、U3、§2、§6、§15、§16（連帶 6 項，全票最廣）
- 背景：{前後文，例如「Confluence 寫完整改版、Jira 留言縮限範疇，兩者打架」}
- [ ] A. {選項}（建議）
- [ ] B. {選項}
- [ ] C. 其他：___

### 🟡 Warning（強烈建議回答）
**Q-002：{問題}**
- 🔗 影響：§15、§16
- 背景：{前後文}
- [ ] A. {選項}
- [ ] B. {選項}

### 🟢 Info（AI 預設假設，無異議視為同意）
- A-001：{假設}
```

#### 5B：複合情境
整票一份、按子情境分組的補問清單（每題同樣要標 🔗 影響 / 背景），見 `references/composite.md` §4。

---

#### 5C:整票 overview 圖與可開工比例(單一 / 複合情境都產)

依 5A / 5B 每題標的 `🔗 影響` + Step 3 的 change_units 清單,產出**一張整票總覽圖**,讓主管/PM 一眼看完:這票要改什麼、哪些坑沒決定、坑連累什麼、哪些可直接開工。圖下方另附**待決問題詳述**卡片,讓主管不靠專案脈絡也讀得懂每題在問什麼。

**節點來源(封閉集合,與 `🔗 影響` 同源)**:
- 所有 change_unit(U1…)
- 所有 🔴 Blocker 與 🟡 Warning 問題(Q-NNN)
- 被任一 `🔗 影響` 指到的 Section(§N)

**邊**:逐題把 `🔗 影響` 的每個目標連成一條邊(Q→Q 決策鏈 / Q→U / Q→§ / U→§)。

**三欄佈局**:① 待決問題 → ② 改動單元 → ③ 受影響規格(對應 blocker-overview 的 decide / units / spec 三欄)。

**節點上色(就緒判定)**:
- change_unit 三態:
  - 🔴 **卡住**(stuck):被任一**未答的** 🔴 Blocker 連到
  - 🟡 **待確認**(soft):只被 🟡 Warning 連到(無 Blocker)
  - ✅ **可開工**(free):沒被任何未答問題連到
- 問題:`root`(被其他 Q 依賴的根決策,粗框)/ `blk`(🔴)/ `warn`(🟡)
- Section:比照連到它的最嚴重來源上色

**可開工比例(分子/分母都標,避免被當成 PO 規格分數)**:
- 分母 = change_unit 總數;分子 = ✅可開工數(沒被任何未答 Blocker 連到的 unit)
- 呈現為分數 `可開工 {ready}/{total}`,三態並列 `✅{n} 可開工 / 🔴{n} 卡住 / 🟡{n} 待確認`
- **務必標明「卡住=等決策,非規格未寫」**:PO 寫越完整、拆出的 unit 越多,分母越大,少數根決策未定就會壓低比例——這不是 PO 規格完成度
- 此數字**隨 PM 回答 Blocker 動態上升**:答掉一題後,其下游 unit 若不再被任何未答 Blocker 連到即轉可開工。重跑 Step 5 即可刷新。

**輸出**:呼叫 **`blocker-overview`** skill 產 `{ISSUE_KEY}-overview.html`——**圖與可開工比例只放這裡,不內嵌進 checklist**(checkList.md / 之後轉出的 checkList.html 皆維持純補問清單)。HTML/CSS 細節全在該 skill,本流程只把上方算好的資料傳入(介面詳見該 skill):
- `issue_key` / `summary` / `out_path = {repo}/ra-docs/{ISSUE_KEY}/{ISSUE_KEY}-overview.html`
- `ready`:`{ total=change_unit 總數, ready/stuck/soft=上方三態統計 }`
- `nodes`:三欄(decide/units/spec)節點,各帶 `state`(問題 `root`/`blk`/`warn`;單元與規格 `stuck`/`soft`/`free`)、`title`(問題寫**完整問句**、單元/規格寫完整名稱,讓主管不查編號就懂)、`desc`(一行白話影響,規格欄可省)
- `edges`:依各題 `🔗 影響` 連線,色 `r`=🔴 / `a`=🟡 / `g`=可開工。只連封閉集合內節點,**不得**新增清單外節點。
- `details`:每個 Blocker/Warning 一筆,供圖下方「待決問題詳述」卡片用——`question`(完整問句)、`background`(**前後文**,直接取自 5A/5B 該 Q 的 `背景` 行:這題從哪來、牽涉哪個功能、目前卡在哪,讓沒專案脈絡的主管也讀得懂)、`options`(選項,取自 checklist 該 Q 的 A/B/C;warn 題可空)、`badge`(連帶卡住數,如「連帶卡住 2 單元 · 1 規格」)、`blocks`(被卡的單元/規格清單)

> 可開工 {ready}/{total} 仍會出現在 **Step 7 對話摘要**;checklist 本身不再含圖與比例。

---

### Step 6：寫入檔案

用 filesystem MCP 寫入檔案至 `{repo}/ra-docs/{ISSUE_KEY}/`。**單一情境與複合情境的輸出結構不同**:

#### 6A:單一情境輸出

```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── jira.md                          (Step 2 Subagent A 已產出)
  ├── confluence-pdf-index.md          (Step 2 Subagent C-pdf 已產出,若有 Confluence PDF)
  ├── axure-pdf-index.md               (Step 2 Subagent B-pdf 已產出,若有 Axure PDF)
  ├── files/                           (Step 1A 複製的 Confluence/Axure PDF)
  ├── {ISSUE_KEY}-spec.md              ← Step 4B-1 產出
  ├── {ISSUE_KEY}-checkList.md         ← Step 5A 產出(純補問清單)
  └── {ISSUE_KEY}-overview.html        ← Step 5C 產出(整票阻塞總覽 + 可開工比例,獨立 HTML,離線可開)
```

#### 6B：複合情境輸出
複合情境的輸出檔案結構（含共用的 `{ISSUE_KEY}-overview.html`）見 `references/composite.md` §5。

---


### 6C：詢問是否產出 PO 友善 HTML

完成 .md 寫入後,**每次都要主動詢問使用者**:

> 「規格書 .md 已產出。是否要同時產出 PO 友善的 HTML 版本(可勾選 + 一鍵複製回 Jira)?」
>
> - **要** → 呼叫 `spec-md-to-po-html` skill,傳入 `{ISSUE_KEY}` 與 `{repo}`,流程接續
> - **不要** → 直接進入 Step 7 對話輸出摘要

呼叫 `spec-md-to-po-html` 時的傳遞:
- 不需要重新詢問 ISSUE_KEY / repo 路徑,沿用本次執行的值
- 該 skill 完成後會回傳 `html/` 目錄下的檔案列表,作為 Step 7 摘要的補充內容

**注意**:
- HTML 化是**選用**步驟,不強制執行;使用者明確說「不要」就跳過
- 若 `spec-md-to-po-html` 執行失敗,**不要回滾 .md 產物**,只在 Step 7 摘要中註記 HTML 化失敗即可
- 若使用者觸發語句已含「不要 HTML」「只要 md」等字眼,直接跳過此步驟,不再詢問

---

### Step 7：對話輸出摘要

**不在對話輸出完整 Markdown 內容**，只輸出以下摘要：

#### 7A:單一情境

```
✅ 規格書已產出

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/
   ├── jira.md                            （Jira 描述與留言）
   ├── confluence-pdf-index.md            （Confluence PDF 索引，若有 PDF）
   ├── axure-pdf-index.md                 （Axure PDF 索引，若有 PDF）
   ├── confluence-spec.md                 （Confluence fallback 規格，僅無 PDF 時出現）
   ├── confluence-sitemap.md              （Confluence 頁面樹，fallback 情境）
   ├── files/                             （Confluence/Axure PDF）
   ├── {ISSUE_KEY}-spec.md
   ├── {ISSUE_KEY}-checkList.md           （純 PO 補問清單）
   └── {ISSUE_KEY}-overview.html          （整票阻塞總覽 + 可開工比例，獨立 HTML，離線可開）

📊 規格書摘要
   scope: {scope} | type: {type}
   外部規格來源: {Confluence PDF / Axure PDF / Confluence PDF+Axure PDF / Confluence (fallback) / 無}
   填充 Section: {已填 Section 編號列表}
   ⚠️ 待確認項目: {N} 個（含 Blocker {X} 個）
   📈 可開工: {可}/{總} 單元（✅{可} 可開工 / 🔴{n} 卡住 / 🟡{n} 待確認）｜卡住=等決策，非規格未寫

{若有 Confluence PDF}
📘 Confluence PDF：files/confluence-spec.pdf （{N} 頁）
   實際參考頁碼：{p.X–Y, p.Z–W ...}

{若有 Axure PDF}
📖 Axure PDF：files/axure-spec.pdf （{N} 頁）
   實際參考頁碼：{p.X–Y, p.Z–W ...}

{若 Confluence 走 fallback (無 PDF)}
⚠️ Confluence 走 API fallback
   圖片未納入，規格可能不完整。
   建議改提供 Confluence PDF 後請我重跑，以補齊規格。

{若 axure_skip=true}
⚠️ Axure 規格未納入
   偵測到 Axure 連結（{axure_url}）但未提供 PDF，
   本規格書僅基於 Jira{若有 Confluence}/Confluence{/若} 內容，完成度可能不足。
   建議匯出 Axure PDF 後請我重跑，以補齊規格。

🔴 Blocker 摘要(需優先回答)
   {逐條列出 Blocker 問題,最多顯示 3 條}

{若 Step 0A 偵測到 template 更新}
📢 Template 有更新：{變動摘要一行}
```

#### 7B：複合情境
複合情境的對話摘要格式見 `references/composite.md` §6。

#### 7C：HTML 補充摘要(僅在 Step 6.5 使用者選擇要產出 HTML 時加上)

在 7A / 7B 摘要末尾追加:

```
🎨 PO 友善 HTML 已產出
   {repo}/ra-docs/{ISSUE_KEY}/html/
   ├── index.html        ← PO 從這裡開始(複合情境)
   ├── checkList.html    ← 互動式補問清單,可勾選 + 一鍵複製回 Jira
   ├── spec.html / NN-{topic}.spec.html
   ...

💡 給 PO 的話術:
   「{ISSUE_KEY} 的補問清單在 ra-docs/{ISSUE_KEY}/html/checkList.html,
    勾完選項按下方『複製 Jira 回覆格式』,把內容貼回這張票的 comment 即可。」
```

若 HTML 化失敗,改為:

```
⚠️ HTML 化失敗
   .md 檔案已正常產出可使用,HTML 步驟未完成。
   失敗原因:{錯誤訊息}
   可用以下指令重試:「{ISSUE_KEY} HTML 化」
```

---

## 注意事項

- 語言：**中文為主，技術術語 / 路徑 / 元件名稱維持原文**
- 資訊不足時標註 `⚠️`，**絕對不捏造**
- Section 只填有意義的，不填空殼
- Bug 類型 ticket → 提示「建議改用 jira-analyzer 分析」
- 複合情境的拆分以 (scope, type) 組合為依據,**不需要使用者確認**,直接執行
- 若使用者想要強制合併為單一 spec,可在觸發語句加上「合併產出」或「一份 spec」
- **HTML 化是選用步驟**:Step 6.5 每次主動詢問,使用者明確說「不要」則跳過;觸發語句已含「不要 HTML」「只要 md」也跳過
- HTML 產出失敗**不影響 .md 可用性**,後者已是完整交付物

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
