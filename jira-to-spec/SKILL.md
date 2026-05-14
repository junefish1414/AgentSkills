---
name: jira-to-spec
description: >
  當使用者提到 Jira 任務單號並要求產出「規格書」時觸發。
  觸發語句包含但不限於：「幫 VIPOP-XXXXX 寫規格書」、「把 VIPOP-XXXXX 整理成規格書」、
  「VIPOP-XXXXX 的規格書」、「幫我產這張票的 spec」、「VIPOP-XXXXX spec」。
  自動透過 Atlassian MCP 讀取 Jira 任務內容，結合規格書標準模板，
  產出規格書 Markdown 與 HTML 檔案至 {repo}/ra-docs/{ISSUE_KEY}/。
  注意：若使用者只說「分析 VIPOP-XXXXX」而未提及規格書/spec，應觸發 jira-analyzer 而非此 skill。
compatibility: "需要 Atlassian MCP、filesystem MCP；若有 Axure 連結則需要 axure-to-md skill"
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
  ├─ Subagent A → 產出 jira.md + files/
  └─ Subagent B → 產出 spec.md + images/(僅在有 Axure 時)
                          ↓
                    【資料庫快照建立完成】
                          ↓
Step 3:判斷需求類型與情境組合
  ├─ 3-3A 單一情境 → Step 4B-1 → Step 5A → Step 6A
  └─ 3-3B 複合情境 → Step 4B-2 + 4C → Step 5B → Step 6B
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
mkdir -p {repo}/ra-docs/{ISSUE_KEY}/images
mkdir -p {repo}/ra-docs/{ISSUE_KEY}/files
```

---

**0C. 讀取最新模板**

用 filesystem MCP 讀取 `{SKILL_REPO}/jira-to-spec/references/template.md`：
- 成功 → 作為規格書結構
- 失敗 → 使用本檔末尾「內建備用模板」，並告知使用者

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
- `attachment`：下載所有 Jira 附件，存至 `{repo}/ra-docs/{ISSUE_KEY}/files/`
- `subtasks`：列出子任務清單，納入影響範圍

**偵測 Axure 連結（在 description 與所有 comment 中搜尋）**：

掃描 description 與所有 comment 的文字，尋找包含 `axshare.com` 的 URL。

- **有找到** → 記錄完整 URL（例如 `https://ng0704.axshare.com/`），進入 Step 1A
- **沒有找到** → 跳過 Step 1A，直接進入 Step 2

---

**Step 1A：詢問 Axure 密碼（僅在偵測到 axshare.com 連結時執行）**

在繼續之前，**先暫停詢問使用者**：

> 「偵測到 Axure 規格書：`{axure_url}`
> 請問這份 Axure 是否有設定存取密碼？有的話請提供。」

收到密碼（或確認無密碼）後，才繼續執行 Step 2。

---

### Step 2：兩階段派出 subagent

為避免 Axure 整本讀取浪費時間，流程拆成兩階段：先讓 Jira 整理與 Axure sitemap 讀取平行進行，再由主 agent 依 Jira 內容判斷要讀哪些 Axure 分頁，最後才實際抓內容。

---

#### Step 2-1：平行收集 Jira 內容與 Axure 分頁清單

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

2. 下載所有 Jira 附件，存至：
   ```
   {repo}/ra-docs/{ISSUE_KEY}/files/
   ```
   使用 `mcp-atlassian:jira_get_issue_images` 或附件 URL 下載。

**Subagent B-sitemap：只讀 Axure 分頁清單（僅在 Step 1 偵測到 axshare.com 連結時派出）**

任務：
- 使用 `axure-to-md` skill 的 `mode: sitemap-only`：開啟 Axure、輸入密碼、展開左側 sitemap、把所有分頁名稱（含層級）寫入：
  ```
  {repo}/ra-docs/{ISSUE_KEY}/axure-sitemap.md
  ```
- **不要讀任何分頁內容、不要截圖**，只要拿到完整分頁清單即可
- 傳入參數：Axure URL、密碼（若有）、repo 路徑、Jira 單號、`mode=sitemap-only`

若無 Axure 連結，**不派出 Subagent B-sitemap**，跳過 Step 2-2，直接進入 Step 4。

等 Subagent A 與 Subagent B-sitemap 都完成後，進入 Step 2-2。

---

#### Step 2-2：由主 agent 判斷需讀取的 Axure 分頁

主 agent 讀取：
1. `{repo}/ra-docs/{ISSUE_KEY}/jira.md`
2. `{repo}/ra-docs/{ISSUE_KEY}/axure-sitemap.md`

依 Jira 描述與留言中提及的頁面、功能、流程，與 sitemap 中的分頁名稱比對，產出兩份清單：

- **需讀取分頁**：分頁名稱與 Jira 內容語意相關（含父層必要的上下文頁）
- **略過分頁**：與本次修改範疇無關

判斷原則：
- 寧可多讀不要少讀；不確定時納入「需讀取」
- 父頁面若是子頁的必要上下文（例如「booking 流程」是子頁的入口），也納入
- Jira 沒明確提到頁名但有關鍵字（按鈕、欄位、流程名稱）→ 用關鍵字比對 sitemap 推斷
- 名稱含「不用看」的分頁一律放入略過

將兩份清單寫入：
```
{repo}/ra-docs/{ISSUE_KEY}/axure-pages-plan.md
```

格式：
```markdown
# Axure 分頁讀取計畫

## 需讀取（{N} 頁）
- 一般booking / 預約明細
- 一般booking / 曝光管道選擇
- ...

## 略過（{M} 頁）
- 版本紀錄（理由：與本次修改無關）
- 舊版流程（理由：非本次範疇）
- ...
```

**不向使用者確認**，直接進入 Step 2-3。讀取結果會在 Step 7 摘要中明確列出。

---

#### Step 2-3：派出 Axure 內容讀取 subagent

**Subagent B-content：依清單讀取 Axure 分頁內容**

任務：
- 使用 `axure-to-md` skill 的 `mode: pages-from-list`
- 傳入參數：Axure URL、密碼（若有）、repo 路徑、Jira 單號、`pages_file={repo}/ra-docs/{ISSUE_KEY}/axure-pages-plan.md`
- 僅讀取「需讀取」清單中的分頁，輸出至：
  ```
  {repo}/ra-docs/{ISSUE_KEY}/spec.md
  images/ 子目錄下存放說明圖片
  ```

Subagent B-content 完成後，繼續 Step 3。

---

### Step 3:判斷需求類型與情境組合

**輸入**:`{repo}/ra-docs/{ISSUE_KEY}/jira.md`(若有 `spec.md` 也一併參考)

#### 3-1:抽取改動單元(change units)

從 jira.md 和 spec.md 中識別所有獨立的改動點,每個改動點記錄:

```yaml
change_units:
  - id: U1
    scope: feature | patch | removal | tracking
    type: content | interaction | permission | ga | layout
    target: <短描述,例如「履歷投遞按鈕」>
    summary: <一句話描述這個改動>
    source_refs:
      - jira.md#<段落或留言錨點>
      - spec.md#<頁面或區段錨點>
```

**scope 判斷:**
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

> 註:舊版的 `mixed` type 已被 Step 3-2 的複合情境判斷取代,不再需要這個分類。

#### 3-2:判斷單一情境或複合情境

**單一情境條件**(滿足任一):
- 只有 1 個 change unit
- 多個 change unit 但 (scope, type) 組合相同(例:三個都是 feature × interaction)

→ 走 **3-3A 單一情境流程**

**複合情境條件**:
- 存在 2 個以上**不同的** (scope, type) 組合

→ 走 **3-3B 複合情境流程**

#### 3-3A:單一情境流程

依下表決定填充 Section:

| scope/type | 必填 | 選填 |
|------------|------|------|
| patch + content | 1, 3 | 15, 16 |
| patch + interaction | 1, 4, 5 | 15, 16 |
| patch + ga | 1, 12 | 16 |
| feature + interaction | 1, 2, 4, 5, 15, 16 | 6, 9, 10, 11, 12 |
| feature + permission | 1, 2, 4, 6, 15, 16 | 5, 7 |
| removal | 1, 8, 15 | 12, 13 |
| tracking | 1, 12 | 16 |

→ 進入 Step 4B-1 產出單一份 spec

#### 3-3B:複合情境流程

**將 change units 按 (scope, type) 組合分群**,輸出 `sub_specs` 結構:

```yaml
sub_specs:
  - id: 01
    scope: feature
    type: interaction
    topic: batch-submit              # Agent 生成短英文 slug
    topic_zh: 批次投遞互動           # 中文標題(用於 index)
    change_units: [U1, U2]
    sections: [1, 2, 4, 5, 15, 16]   # 依此組合查表決定

  - id: 02
    scope: patch
    type: permission
    topic: permission-control
    topic_zh: 權限控管
    change_units: [U3]
    sections: [1, 2, 6, 15, 16]

  - id: 03
    scope: feature
    type: ga
    topic: ga-tracking
    topic_zh: GA 追蹤
    change_units: [U4]
    sections: [1, 12, 16]
```

**排序原則**:
1. `change_units` 數量最多的子情境 → `01`(視為主軸)
2. 其他依 `change_units` 數量遞減排序
3. 同數量時,scope 為 `feature` 的優先

**topic slug 生成規則**:
- 純英文小寫 + 連字號,長度 ≤ 25 字元
- 取自 change unit 的 `target` 或 `summary` 主語
- 範例:`batch-submit` / `permission-control` / `ga-tracking` / `resume-list-filter`

→ 進入 Step 4B-2 + 4C 產出多份子 spec + 1 份 index

---

### Step 4：讀取來源資料並填充規格書

**Step 4A：讀取所有可用來源**

在填充前，依序讀取以下資料（全部讀完再開始寫）：

1. **`{repo}/ra-docs/{ISSUE_KEY}/jira.md`** — Jira 描述與規格留言
2. **`{repo}/ra-docs/{ISSUE_KEY}/spec.md`**（若存在）— Axure 規格書（僅含 Step 2-2 判斷為相關的分頁）
3. **`{repo}/ra-docs/{ISSUE_KEY}/axure-pages-plan.md`**（若存在）— 確認哪些分頁被讀取、哪些被略過，作為後續分析的範疇參考
4. **`{repo}/ra-docs/{ISSUE_KEY}/images/`** — 列出所有截圖檔名，了解有哪些 BEFORE/AFTER 對比圖可引用
5. **`{repo}/ra-docs/{ISSUE_KEY}/files/`** — 列出所有附件檔名（例如 PDF、Excel），在規格書中標注「參考附件：{檔名}」

```bash
# 列出 images/ 和 files/ 內容
ls {repo}/ra-docs/{ISSUE_KEY}/images/
ls {repo}/ra-docs/{ISSUE_KEY}/files/
```

**來源優先順序**：
- 有 `spec.md`（Axure 轉出）→ 以 `spec.md` 為主要規格來源，`jira.md` 作補充
- 無 `spec.md` → 僅參考 `jira.md`

**Step 4B：填充規格書**

##### 4B-1:單一情境填充

依 Step 3-3A 決定的 Section 清單填充,遵循以下原則:

1. **忠實呈現**：來源檔未提及用 `⚠️ 未提及，建議與 PM 確認` 標註，不捏造
2. **留言補充**：含「改為」「調整」「要補做」的留言內容納入對應 Section
3. **操作流程附流程圖**：Section 4 每個流程附 Mermaid `flowchart TD`
4. **狀態變化附狀態圖**：Section 7 狀態變化用 Mermaid `stateDiagram-v2`
5. **引用截圖**：`images/` 下的圖片若與該 Section 相關，以相對路徑引用（例如 `images/preLogin-BEFORE.png`），並加上說明文字
6. **引用附件**：`files/` 下的附件在相關 Section 標注「參考附件：{檔名}」
7. **Section 16 主動出題**：AI 依需求類型主動補充極端情境，每條標示「🤖 AI 建議」或「⚠️ 未定義」
8. **前端視角**：所有分析以前端工程師角度出發

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

##### 4B-2:複合情境填充(對每個子 spec 各填一份)

**對 Step 3-3B 輸出的每個 `sub_specs[i]`,各自產出一份子 spec**:

1. **建立子 spec 內容骨架**,使用該子情境的 `sections` 清單
2. **限定填充範圍**:只用該子情境的 `change_units` 對應的 jira.md / spec.md 內容
3. **跨子情境引用**:若某個 change unit 與其他子情境相關,用以下格式標註:
   ```markdown
   > 📎 此項與子情境 02(權限控管)相關,詳見 `VIPOP-1234-02-permission-control.spec.md`
   ```
4. **頂部加入 frontmatter**:
   ```markdown
   ---
   parent_issue: VIPOP-1234
   sub_id: 01
   scope: feature
   type: interaction
   topic: batch-submit
   topic_zh: 批次投遞互動
   sections_filled: [1, 2, 4, 5, 15, 16]
   depends_on: []            # 或 ["02"] 等
   generated_at: 2026-05-14T...
   ---
   ```

**填充原則(其餘)**:沿用 4B-1 的 1-8 條(包含 images/ 與 files/ 的引用方式)

#### Step 4C:複合情境的 index 檔內容(僅複合情境)

額外產出 `{ISSUE_KEY}-index.md`:

```markdown
---
issue_key: VIPOP-1234
type: composite
sub_spec_count: 3
generated_at: 2026-05-14T...
---

# VIPOP-1234 規格書索引

## 偵測結果
此票偵測到 3 個獨立 (scope, type) 組合,已拆分為 3 份子 spec。

## 拆分理由
- 子情境之間 scope × type 不同,合併會造成模板章節衝突
- 拆分後 SA 可依角色分配閱讀(例:後端工程師只看 02-permission)

## 子 spec 列表

| # | 主題 | scope × type | 主要章節 | 依賴 |
|---|------|-------------|---------|------|
| 01 | 批次投遞互動 | feature × interaction | §1, §2, §4, §5, §15, §16 | — |
| 02 | 權限控管 | patch × permission | §1, §2, §6, §15, §16 | 01 |
| 03 | GA 追蹤 | feature × ga | §1, §12, §16 | 01 |

## 共用資源
- Jira 來源快照:`./jira.md`
- Axure 規格快照:`./spec.md`
- 截圖資源:`./images/`
- 附件檔案:`./files/`
- PO 補問清單:`./VIPOP-1234-checkList.md`

## 子 spec 檔案
- [01 批次投遞互動](./VIPOP-1234-01-batch-submit.spec.md)
- [02 權限控管](./VIPOP-1234-02-permission-control.spec.md)
- [03 GA 追蹤](./VIPOP-1234-03-ga-tracking.spec.md)
```

---

### Step 5：在規格書中未明確的項目整理成 PO 補問清單

#### 5A:單一情境

將所有 ⚠️ 彙整,分三級,用選擇題格式,寫入 `{ISSUE_KEY}-checkList.md`:

```markdown
# VIPOP-1234 PO 補問清單

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

#### 5B:複合情境

整票一份 `{ISSUE_KEY}-checkList.md`,內部按子情境分組:

```markdown
# VIPOP-1234 PO 補問清單(複合情境)

> 此票拆為 3 份子 spec,問題依子情境分組。每題後標註對應的子 spec 編號。

## 🔴 Blocker — 全票阻塞問題(跨子情境)

**Q-001:{跨子情境的關鍵問題,例如命名規範、共用元件命名}**
- [ ] A. ...

---

## 子情境 01:批次投遞互動

### 🔴 Blocker
**Q-002:{問題}** `[子 spec 01]`
- [ ] A. ...

### 🟡 Warning
**Q-003:{問題}** `[子 spec 01]`

---

## 子情境 02:權限控管

### 🔴 Blocker
**Q-004:{問題}** `[子 spec 02]`

### 🟡 Warning
**Q-005:{問題}** `[子 spec 02]`

---

## 子情境 03:GA 追蹤

### 🟡 Warning
**Q-006:{問題}** `[子 spec 03]`

---

## 🟢 Info — 全票通用 AI 假設(無異議視為同意)
- A-001:{假設}
- A-002:{假設}
```

**分組原則**:
- Blocker 中跨子情境的問題放最前(整票阻塞)
- 子情境內部依 Blocker / Warning 兩級排列
- Info 因為通常影響面較廣,統一放最後
- 每個問題後標註 `` `[子 spec NN]` `` 方便對應

---

### Step 6：寫入檔案

用 filesystem MCP 寫入檔案至 `{repo}/ra-docs/{ISSUE_KEY}/`。**單一情境與複合情境的輸出結構不同**:

#### 6A:單一情境輸出

```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── jira.md                          (Step 2 Subagent A 已產出)
  ├── spec.md                          (Step 2 Subagent B 已產出,若有 Axure)
  ├── images/                          (Step 2 Subagent B 已產出,若有 Axure 截圖)
  ├── files/                           (Step 2 Subagent A 已下載 Jira 附件)
  ├── {ISSUE_KEY}-spec.md              ← Step 4B-1 產出
  └── {ISSUE_KEY}-checkList.md         ← Step 5A 產出
```

#### 6B:複合情境輸出

```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── jira.md                                   (共用)
  ├── spec.md                                   (共用,若有)
  ├── images/                                   (共用)
  ├── files/                                    (共用)
  ├── {ISSUE_KEY}-index.md                      ← Step 4C 產出
  ├── {ISSUE_KEY}-01-{topic}.spec.md            ← Step 4B-2 產出(子 spec 1)
  ├── {ISSUE_KEY}-02-{topic}.spec.md            ← Step 4B-2 產出(子 spec 2)
  ├── {ISSUE_KEY}-03-{topic}.spec.md            ← Step 4B-2 產出(子 spec 3)
  └── {ISSUE_KEY}-checkList.md                  ← Step 5B 產出(共用)
```

> 子 spec 數量取決於 Step 3-3B 偵測到的子情境數量,可能是 2 / 3 / 4 / ... 份。

---

### Step 7：對話輸出摘要

**不在對話輸出完整 Markdown 內容**，只輸出以下摘要：

#### 7A:單一情境

```
✅ 規格書已產出

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/
   ├── jira.md                （Jira 描述與留言）
   ├── axure-sitemap.md       （Axure 完整分頁清單，若有）
   ├── axure-pages-plan.md    （讀取/略過判斷，若有）
   ├── spec.md                （Axure 規格，僅含已讀分頁）
   ├── images/                  (Axure 截圖)
   ├── files/                 （Jira 附件）
   ├── {ISSUE_KEY}-spec.md
   └── {ISSUE_KEY}-checkList.md（僅 PO 補問清單）

📊 規格書摘要
   scope: {scope} | type: {type}
   填充 Section: {已填 Section 編號列表}
   ⚠️ 待確認項目: {N} 個（含 Blocker {X} 個）

{若有 Axure}
📖 Axure 分頁讀取狀況
   ✅ 已讀取 ({N} 頁)：
      - {分頁名稱 1}
      - {分頁名稱 2}
      - ...
   ⏭️ 略過 ({M} 頁)：
      - {分頁名稱}（理由）
      - ...
   ⚠️ 若發現遺漏，請告知需要補讀的分頁，將重新執行

🔴 Blocker 摘要(需優先回答)
   {逐條列出 Blocker 問題,最多顯示 3 條}
```

#### 7B:複合情境

```
✅ 複合情境規格書已產出(共 N 份子 spec)

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/
   ├── jira.md / spec.md / images/ / files/    (來源資料庫,共用)
   ├── {ISSUE_KEY}-index.md                    ← 從這裡開始閱讀
   ├── {ISSUE_KEY}-01-{topic}.spec.md
   ├── {ISSUE_KEY}-02-{topic}.spec.md
   ├── {ISSUE_KEY}-03-{topic}.spec.md
   └── {ISSUE_KEY}-checkList.md                (PO 補問清單,共用)

📊 拆分摘要
   偵測到 3 個獨立 (scope, type) 組合,已拆為 3 份子 spec:
   01. {topic_zh}  ({scope} × {type})  → §{sections}
   02. {topic_zh}  ({scope} × {type})  → §{sections}
   03. {topic_zh}  ({scope} × {type})  → §{sections}

   ⚠️ 待確認項目: {N} 個(含 Blocker {X} 個)

🔴 Blocker 摘要(需優先回答)
   {逐條列出 Blocker 問題,最多顯示 3 條,每條標註所屬子 spec}
```

---

## 注意事項

- 語言：**中文為主，技術術語 / 路徑 / 元件名稱維持原文**
- 資訊不足時標註 `⚠️`，**絕對不捏造**
- Section 只填有意義的，不填空殼
- Bug 類型 ticket → 提示「建議改用 jira-analyzer 分析」
- 複合情境的拆分以 (scope, type) 組合為依據,**不需要使用者確認**,直接執行
- 若使用者想要強制合併為單一 spec,可在觸發語句加上「合併產出」或「一份 spec」

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
