---
name: jira-to-spec-iterate
description: >
  當使用者要求「更新」已產出的規格書時觸發。
  觸發語句包含但不限於：「更新 VIPOP-XXXXX 規格書」、「VIPOP-XXXXX 迭代」、
  「VIPOP-XXXXX PO 回覆了」、「重新整理 VIPOP-XXXXX 規格書」、
  「VIPOP-XXXXX 規格書 v2」。
  與 jira-to-spec 的差別：本 skill 用於「已有規格書產物後的迭代更新」，
  支援增量爬取、PO 答案整合、單點 Section 更新，避免每次都從零重跑。
  前置條件：{repo}/ra-docs/{ISSUE_KEY}/ 目錄需已存在（即已跑過 jira-to-spec）。
  若不存在 → 提示使用者改用 jira-to-spec 做首次產出。
compatibility: "需要 Atlassian MCP、filesystem MCP；專案模式下需要 axure-to-md skill 與 Playwright MCP"
---

# Jira to Spec Iterate — 規格書迭代更新

## 與 jira-to-spec 的分工

| Skill | 觸發條件 | 核心邏輯 |
|-------|---------|---------|
| jira-to-spec | 首次產出規格書 | 完整爬取 + 全新產出 |
| jira-to-spec-iterate | 已有規格書,需更新 | 增量爬取 + 單點更新 |

**前置檢查**:執行前必先確認 `{repo}/ra-docs/{ISSUE_KEY}/` 存在,且含 `.meta.json`。
- 不存在 → 告知使用者「此 ticket 尚未產出過規格書,請改用 jira-to-spec」
- 存在但無 `.meta.json`(舊版產出) → 告知使用者「偵測到舊版產物無迭代資訊,建議重跑 jira-to-spec 重建基線」

---

## 核心設計原則

1. **情境感知**:依 Jira 票性質(維運/專案)決定爬取策略,不一視同仁
2. **增量優先**:能不重爬就不重爬,token 成本是首要考量
3. **單點更新**:Spec 只重寫被影響的 Section,其他保留
4. **PO 答案整合,不污染來源**:Jira/Axure 是真相,checkList 是工作清單,不要求 PO 在 checkList 填答

---

## 執行步驟

### Step 0:前置作業與基線載入

**0A. 收集資訊**

若對話中尚未提供,詢問:
1. **Jira 單號**(例如 VIPOP-44376)
2. **repo 在本機的絕對路徑**

**0B. 驗證前置條件**

```bash
# 檢查目錄與 meta 檔
ls {repo}/ra-docs/{ISSUE_KEY}/.meta.json
```

- 目錄不存在 → 終止並提示「請先用 jira-to-spec 做首次產出」
- 目錄存在但無 `.meta.json` → 終止並提示「建議用 jira-to-spec 重建基線」
- 都存在 → 載入 `.meta.json`,進入 Step 1

**0C. 載入既有產物**

讀取以下檔案(只讀,先不修改):
- `{repo}/ra-docs/{ISSUE_KEY}/.meta.json` — 上輪狀態
- `{repo}/ra-docs/{ISSUE_KEY}/{ISSUE_KEY}-spec.md` — 現有規格
- `{repo}/ra-docs/{ISSUE_KEY}/{ISSUE_KEY}-checkList.md` — 現有問題清單

---

### Step 1:情境模式判斷

抓取 Jira 最新狀態(輕量呼叫,只取必要欄位):

```
工具:mcp-atlassian:jira_get_issue
參數:
  issue_key: "{ISSUE_KEY}"
  fields: "issuetype,parent,labels,description,comment"
  comment_limit: 50
```

**多訊號加權判斷**:

| 訊號 | 強度 | 判定 |
|------|------|------|
| parent = VIPOP-524(專案 parent) | 強 | → 專案模式 +2 分 |
| parent = VIPOP-60(維運 parent) | 強 | → 維運模式 +2 分 |
| description/comment 含 `axshare.com` 連結 | 強 | → 專案模式 +2 分 |
| issuetype = Story / Epic | 弱 | → 專案模式 +1 分 |
| issuetype = Task / Bug | 弱 | → 維運模式 +1 分 |
| labels 含「專案」「project」 | 弱 | → 專案模式 +1 分 |

**判定規則**:
- 專案分數 > 維運分數 → **專案模式**(Axure 為規格真相)
- 維運分數 > 專案分數 → **維運模式**(Jira 為規格真相)
- **衝突情境**(例:parent=維運 但 有 Axure 連結) → **暫停詢問使用者**:
  > 「偵測到這是維運單(parent: VIPOP-60),但內含 Axure 連結 `{axure_url}`。
  > 請問要把 Axure 當作:
  > A. 規格真相(走專案模式)
  > B. 參考資料(走維運模式,Axure 僅供查閱不重爬)」

**模式紀錄**:本輪判定結果寫入 `.meta.json` 的 `mode` 欄位,後續使用。

---

### Step 2:增量偵測(依模式分流)

#### 2A. Jira 增量偵測(兩種模式都做)

**比對方式**:

1. **整票更新時間**:取 Jira 回應的 `updated` 欄位,與 `.meta.json.jira.updated_at` 比對
   - 沒變 → **整個 Jira 都跳過**,直接進入 Step 2B 或 Step 3
   - 有變 → 進入下一步

2. **新留言過濾**:取所有 comments,過濾 `created > .meta.json.last_run` 的留言
   - 解析每則新留言開頭的 `[RA-Q-XXX]` 標記
   - 有標記 → 對應到上輪未答問題,標記為「PO 已回答」
   - 無標記但內容含「改為」「調整」「要補做」等規格關鍵字 → 標記為「PO 補規格」,需整合進 spec

3. **維運模式專屬**:`description` 變更不做 hash 偵測(依使用者決定:維運靠留言討論)
   - 若 PO 在維運單直接改 description,以「使用者明確告知」為觸發,本 skill 不主動偵測

#### 2B. Axure 增量偵測(僅專案模式)

**策略 1:頁面層級 Last-Modified 偵測**

讀取 `.meta.json.axure.pages`,對每個記錄過的頁面:

```
工具:Playwright MCP(輕量 HEAD-like request)
動作:
  1. 對每個 page URL,只取 Last-Modified header(不下載內容)
  2. 比對 .meta.json 中該頁的 last_modified
  3. 沒變 → 標記「skip」
  4. 有變 → 標記「需重爬」
```

**策略 2:checkList 綁定節點精準爬取**

讀取現有 `checkList.md`,解析所有 A 類問題的「對應 Axure 節點」欄位:
- 整理出「有未答 A 類問題的頁面清單」(集合 P_pending)
- 整理出「Last-Modified 偵測到變動的頁面清單」(集合 P_changed)

**重爬決策**:

| 頁面狀態 | 行為 |
|---------|------|
| 在 P_pending ∩ P_changed | **必爬**(有問題且有變動) |
| 只在 P_pending | **必爬**(有未答問題,需要找答案) |
| 只在 P_changed | **詢問使用者**:「偵測到 `p=XXX` 頁面有變動但無對應的未答問題,要重爬整合進 spec 嗎?」 |
| 都不在 | **skip**(無事可做) |

**新頁面偵測**:若 Axure 主入口 sitemap 出現新頁面(`.meta.json` 沒記錄過的),全部視為需重爬,並提示使用者。

**爬取失敗處理**(沿用 jira-to-spec 的 fail-loudly 原則):
- HTTP 失敗 / 認證失敗 → 中斷流程,告知使用者並提供重試/略過選擇
- 內容為空 → 標記該頁,繼續但在最終輸出註記

---

### Step 3:答案比對與整合

**3A. B 類問題比對(Jira 留言 → 答案)**

對每個 `.meta.json.pending_questions` 中標註為 B 類的問題:
- 在新留言中搜尋 `[RA-Q-XXX]` 標記
- 找到 → 解析答案內容(允許自由文字,但需識別 A/B/C 選項或自由補充)
- 找不到 → 維持「未答」狀態

**3B. A 類問題比對(Axure 變更 → 答案)**

對每個 `.meta.json.pending_questions` 中標註為 A 類的問題:
- 取出該問題的「AI 偵測錨點」(例如關鍵字「上限」「最多」)
- 在對應頁面的新爬取內容中搜尋這些關鍵字
- 找到相關內容 → 標記「PO 可能已補,需 AI 判讀」,將該段落納入下一步整合
- 找不到 → 維持「未答」狀態,但若該頁面有重爬,標註「頁面已更新但未明確回答此問題」

**3C. 衝突偵測**

若 PO 同一個 Q-XXX 在 Jira 和 Axure 都有回應且內容不一致 → 中斷流程,呈現衝突點請使用者裁示。

---

### Step 4:單點 Spec 更新

**4A. 識別受影響 Section**

依據以下訊號整理「需更新 Section 清單」:
- 已答問題的「影響 Section」欄位
- Axure 重爬頁面對應的 Section(從 `.meta.json.axure.pages.affected_sections` 查)
- Jira 新留言中「改為/調整/要補做」涉及的內容對應的 Section

**4B. Section 錨點定位**

現有 `{ISSUE_KEY}-spec.md` 中每個 Section 應有 HTML 錨點:

```markdown
<!-- section-start:4 -->
## §4 操作流程
...內容...
<!-- section-end:4 -->
```

若現有 spec **沒有錨點**(舊版產出):
- 第一次迭代時自動補上錨點,並提示使用者「已為相容性補上 Section 錨點」
- 補錨點時用標題正規表達式定位(`^## §\d+`)

**4C. 單點重寫**

只重新生成「需更新 Section 清單」中的 Section:
- 讀取相關來源(該 Section 對應的 Jira 留言、Axure 頁面)
- 套用 PO 答案
- 重寫該 Section 內容,用 `<!-- section-start:N -->...<!-- section-end:N -->` 整段替換
- 在被 PO 答案填上的位置,加上來源註記:
  ```markdown
  無數量上限。 <!-- source: PO@Q-001 (2026-05-13) -->
  ```

**4D. 未受影響 Section**

保持原樣,連 AI 之前的判斷都不重做(避免漂移)。

---

### Step 5:checkList 更新

**5A. 已答問題處理**

- 從 checkList 移除(不保留歷史,符合「不保留 history」決策)
- 但在 `.meta.json.answered_questions` 記錄問題 ID 與答案來源(Jira comment ID 或 Axure 頁面),供追溯

**5B. 仍未答問題**

- 保留在 checkList 中
- 若該題在 `.meta.json` 中已存在超過 N 輪(預設 3 輪),在問題前加上 ⏰ 標記,提示使用者「此問題已多輪未獲回答」

**5C. 新發現問題**

迭代過程可能因為 PO 答案衍生新問題(例:Q-001 選 B「有上限」→ 衍生 Q-006「上限是多少」):
- 用新編號加入 checkList
- 在問題描述標註「(由 Q-001 衍生)」

**5D. checkList 格式**(新版,A/B 分類 + 結構化錨點)

```markdown
## 📋 PO 補問清單

### 🔴 Blocker(必須回答才能開工)

<!-- question-start:Q-001 -->
**Q-001**: 已收藏項目是否有數量上限?
- 分類: 🟦 A 類(規格內容)
- 影響 Section: §4
- 對應 Axure 節點: `p=收藏頁`
- AI 偵測錨點: 此頁面文字含「上限」「最多」「數量限制」等關鍵字

**選項:**
- A. 無上限(建議)
- B. 上限 N 筆,超過時顯示錯誤
- C. 其他

**📝 PO 回填位置**: 請在 Axure 的「收藏頁」補上上限說明
<!-- question-end:Q-001 -->

<!-- question-start:Q-002 -->
**Q-002**: 這次改動是否包含 App 端?
- 分類: 🟨 B 類(需求意圖)
- 影響 Section: §1
- 回填位置: Jira 留言

**📝 PO 回填範本(可直接複製到 Jira 留言):**
\`\`\`
[RA-Q-002] 是 / 否,補充:___
\`\`\`
<!-- question-end:Q-002 -->

### 🟡 Warning(強烈建議回答)
(同上格式)

### 🟢 Info(AI 預設假設,無異議視為同意)
- A-001:{假設}
```

---

### Step 6:`.meta.json` 更新

寫入本輪狀態,供下輪迭代使用:

```json
{
  "schema_version": "1.0",
  "last_run": "2026-05-13T14:20:00Z",
  "iteration_count": 2,
  "mode": "project",
  "jira": {
    "updated_at": "2026-05-13T13:45:00Z",
    "last_comment_id": "comment-12345"
  },
  "axure": {
    "base_url": "https://ng0704.axshare.com/",
    "pages": {
      "p=收藏頁": {
        "last_modified": "2026-05-13T13:30:00Z",
        "content_hash": "abc123...",
        "affected_sections": ["§4"]
      }
    }
  },
  "answered_questions": [
    {
      "id": "Q-001",
      "answered_at": "2026-05-13T13:30:00Z",
      "source": "axure:p=收藏頁",
      "answer_summary": "無上限"
    }
  ],
  "pending_questions": ["Q-002", "Q-004"],
  "stale_questions": []
}
```

---

### Step 7:對話輸出迭代摘要

```
🔄 規格書迭代完成(第 N 輪)

📊 本輪變動
   模式: {project/maintenance}
   解決問題: {X} 個(Blocker {a}, Warning {b}, Info {c})
   新發現問題: {Y} 個
   仍未解決: {Z} 個(其中 ⏰ 多輪未答: {W} 個)

📝 Spec 變動 Section
   - §4 操作流程(整合 Q-001 答案:無上限)
   - §15 錯誤處理(因 §4 變動連動更新)

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/
   ├── {ISSUE_KEY}-spec.md(已更新)
   ├── {ISSUE_KEY}-checkList.md(已更新)
   └── .meta.json(已更新)

💰 Token 節省
   Jira: {跳過/重抓 N 則新留言}
   Axure: 重爬 {M} 頁(共 {K} 頁,節省 ~{P}%)

⚠️ 需要關注
   - Q-002 已連續 3 輪未答(Blocker),建議當面與 PO 確認
   - {其他警示}
```

---

## 注意事項

### 失敗處理(沿用 fail-loudly 原則)

- **Jira API 失敗** → 中斷,提供重試
- **Axure 爬取失敗** → 中斷,提供重試/略過該頁/略過 Axure
- **PO 答案無法解析**(例:留言格式不符 + 自由文字無法歸類) → 標記「需人工判讀」,在輸出摘要中提示
- **內容矛盾**(Jira vs Axure 同一問題答案不同) → 中斷,呈現衝突請使用者裁示

### Token 經濟原則

- 任何重爬都應有明確理由(來自 Last-Modified、checkList 綁定、或使用者明確要求)
- 不確定是否要爬時,**先問使用者**,而非預設爬
- 每輪結束在摘要中報告 token 節省比例,讓使用者有資源使用感

### PO 心理摩擦原則

- checkList 是「給你(RA)的工作清單」,不是「給 PO 的作業」
- PO 永遠在他既有的工具(Jira / Axure)中工作,不要求他打開 Markdown 編輯器
- 提供「可直接複製」的留言範本,降低 PO 思考成本
- 已答問題從 checkList 移除,讓 PO/RA 視覺上感受「進度在前進」

---

## 公司專案分類規則(可配置區)

> 此區塊集中放置依公司組織結構而變動的設定,未來規則變更時只需改這裡。

- **專案 parent**: `VIPOP-524`(專案管理)
- **維運 parent**: `VIPOP-60`(營運維護)
- **強訊號 labels**: `專案`, `project`(專案模式)
- **預設模式**(無法判定時): 詢問使用者,不預設

---

## 範例觸發語句

**應觸發此 skill**:
- `更新 VIPOP-44376 規格書`
- `VIPOP-567 PO 回覆了`
- `VIPOP-111 迭代`
- `重新整理 VIPOP-890 規格書`

**不應觸發(應觸發其他 skill)**:
- `幫 VIPOP-XXX 寫規格書`(首次) → `jira-to-spec`
- `分析 VIPOP-XXX` → `jira-analyzer`

---

## 與 jira-to-spec 的相容性需求

為了讓 jira-to-spec 的產出能被本 skill 順利迭代,**jira-to-spec 也需要做以下調整**:

1. **產出時建立 `.meta.json`** 作為基線
2. **每個 Section 加上 HTML 錨點**(`<!-- section-start:N -->`)
3. **checkList 採用新格式**(A/B 分類、Axure 節點綁定、HTML 錨點)
4. **首次爬 Axure 時記錄每頁的 Last-Modified 與 content_hash**

> 若 jira-to-spec 尚未更新,本 skill 第一次跑時會自動補上錨點與基本 meta,但建議盡快同步更新 jira-to-spec 以保一致性。
