---
name: spec-reviewer
description: >
  當使用者要求「審查 / review / 驗證 / 檢查」已產出的規格書時觸發。
  觸發語句包含但不限於：「review VIPOP-XXXXX 規格書」、「審查 VIPOP-XXXXX 規格書」、
  「驗證 VIPOP-XXXXX 可不可以進 SA」、「檢查 VIPOP-XXXXX 規格書品質」、
  「VIPOP-XXXXX 規格書 review」、「VIPOP-XXXXX 可以進 SA 了嗎」。
  讀取 {repo}/ra-docs/{ISSUE_KEY}/ 下已產出的規格書,套用雙軸 rubric:
  Readiness(就緒度,硬門檻)+ Readability(可讀性,軟指標),
  產出 review-report.md 至同一目錄。預設兩軸同時跑。
  注意:若使用者尚未產出規格書(目錄不存在),提示改用 jira-to-spec。
compatibility: "僅需 filesystem MCP;不依賴 Atlassian / Playwright,執行快且離線可跑"
---

# Spec Reviewer — 規格書進入 SA 前的雙軸 Review

## 與其他 skill 的分工

| Skill | 觸發條件 | 產出物 | 階段 |
|-------|---------|--------|------|
| jira-to-spec | 「寫規格書」「spec」 | `.spec.md` | RA 產出 |
| jira-to-spec-iterate | 「更新規格書」「PO 回覆了」 | `.spec.md` v2 | RA 迭代 |
| **spec-reviewer** | **「review」「審查」「可以進 SA 了嗎」** | **`review-report.md`** | **RA → SA 把關** |
| spec-md-to-po-html | 「PO 版」「HTML 化」 | `.html` | PO 交付 |

---

## 核心定位

這個 skill 不是「評論規格書寫得好不好」,而是回答兩個明確問題:

1. **Readiness**:SA 在不回頭問 RA 的情況下,能不能據此開工?(硬門檻,pass/fail)
2. **Readability**:人(PO / reviewer / 新進 SA)能不能快速讀懂、不誤解?(軟指標,計分)

**重要原則**:Readiness 是 gate,Readability 是 score。兩者衝突時(資訊完備但難讀),**保留資訊、優化呈現**,絕不為可讀性刪除 SA 需要的內容。

---

## 執行步驟總覽

```
Step 0:收集資訊與前置作業
Step 1:讀取規格書與相關檔案
Step 2:判斷情境(單一 / 複合)與決定應有 sections
Step 3:執行 Readiness Review(硬門檻)
Step 4:執行 Readability Review(軟指標)
Step 5:合併輸出 review-report.md
Step 6:對話輸出摘要
```

預設 `--mode both`(Readiness + Readability 都跑)。可選 `--mode readiness` 或 `--mode readability` 跑單軸。

---

### Step 0:收集資訊與前置作業

**0A. 向使用者收集必要資訊**

若對話中尚未提供,請同時詢問:
1. **Jira 單號**(例如 VIPOP-44376)
2. **repo 在本機的絕對路徑**(例如 `/Users/yourname/projects/my-repo`)

**0B. 確認目錄存在**

```bash
ls {repo}/ra-docs/{ISSUE_KEY}/
```

- 目錄存在且有 `.spec.md` → 繼續
- 目錄不存在 → 回覆使用者:

  > 「未找到 `{repo}/ra-docs/{ISSUE_KEY}/`,似乎尚未為此票產出規格書。
  >  建議先用 `jira-to-spec` 產出規格書後,再執行 review。」

  並停止執行。

**0C. 確認 review 模式**

預設 `--mode both`。若使用者明確指定:
- 「只看可不可以進 SA」「只看完整度」 → `--mode readiness`
- 「只看可讀性」「只看好不好讀」 → `--mode readability`

---

### Step 1:讀取規格書與相關檔案

依序讀取以下檔案(用 filesystem MCP):

1. **`{ISSUE_KEY}-spec.md`**(單一情境)
   或
   **`{ISSUE_KEY}-index.md` + 所有 `{ISSUE_KEY}-NN-{topic}.spec.md`**(複合情境)
2. **`jira.md`**(原始 Jira 內容,作為對照基準)
3. **`{ISSUE_KEY}-checkList.md`**(PO 補問清單,review 時要考慮已知未決問題)

**判斷單一 vs 複合情境**:
- 存在 `{ISSUE_KEY}-index.md` → 複合情境,逐份子 spec 各跑一次 review,最後合併報告
- 不存在 → 單一情境,跑一次 review

**不讀取**:`spec.md`(Axure 原始)、`images/`、`files/` — 本 skill 範圍僅限規格書產出本身,不回頭核對外部來源(若需深度核對,屬未來 `--verify-sources` 擴充)。

---

### Step 2:判斷情境與決定應有 sections

從規格書的 frontmatter 讀取:

```yaml
issue_key: VIPOP-1234
scope: feature
type: interaction
sections_filled: [1, 2, 4, 5, 15, 16]
```

依 `jira-to-spec` 的 section 選擇邏輯查表(對照下方「Section 應有性參考表」),推導 **「應有 sections」**,與 `sections_filled` 比對,得出:

- **缺失 sections**:應有但未填(Readiness Blocker 線索)
- **多餘 sections**:不應有但填了(通常不擋,記 Info)

#### Section 應有性參考表(對照 jira-to-spec)

| scope/type | 必填 | 選填 |
|------------|------|------|
| patch + content | 1, 3 | 15, 16 |
| patch + interaction | 1, 4, 5 | 15, 16 |
| patch + ga | 1, 12 | 16 |
| feature + interaction | 1, 2, 4, 5, 15, 16 | 6, 9, 10, 11, 12 |
| feature + permission | 1, 2, 4, 6, 15, 16 | 5, 7 |
| removal | 1, 8, 15 | 12, 13 |
| tracking | 1, 12 | 16 |

**必填缺失** → Readiness Blocker
**選填缺失** → 不擋,通常不記

---

### Step 3:執行 Readiness Review(硬門檻)

針對每一項 Blocker / Warning,逐項判定 yes/no。判定時採 **adversarial cold-read**:扮演一個沒參與這張票的 SA,凡是「必須自行假設才能往下」就記為缺口。

#### 3A. Blocker(不能進 SA — 必須補)

| 檢查項 | 判定方式 |
|--------|---------|
| **該有的 section 都在** | Step 2 結果無「必填缺失」 |
| **驗收條件能被驗證** | 掃描所有驗收條件,標記含「快速 / 友善 / 穩定 / 適當 / 合理」等無法測措辭者 |
| **主流程從頭走到尾不斷線** | §4(操作流程)每步輸入/輸出明確,無黑盒「系統處理」字眼 |
| **重要欄位看得出從哪來、被誰用** | §10(表單)/§3(文案版面)中關鍵欄位有來源描述(誰產生、從哪讀、誰寫入) |
| **章節之間說法不打架** | 核心假設(登入狀態、權限、資料來源)跨 section 一致,無 §X 假設 A、§Y 假設 non-A |
| **引用的設計稿真的打得開** | 規格書中所有 Axure/Figma 連結格式合法(URL 結構完整、無 `TODO` / `待補`)— 注意:本 skill 不實際開啟連結驗證 |

#### 3B. Warning(可進 SA 但有風險 — 建議補)

| 檢查項 | 判定方式 |
|--------|---------|
| **邊界與例外** | §15 / §16 有定義錯誤、空值、逾時、權限不足、併發等行為 |
| **狀態轉換完整** | 若有 §7 狀態機,所有狀態都有合法轉換,無孤立狀態 |
| **依賴明示** | §1 影響範圍有列出外部系統 / API / 既有功能依賴 |
| **權限與角色** | §2 不同角色可見 / 可操作範圍有界定 |
| **非功能性需求** | 若 scope=feature,效能 / 容量 / 相容性適用時有具體目標值 |

#### 3C. Info(優化建議 — 不影響進度)

| 檢查項 | 判定方式 |
|--------|---------|
| **範例資料** | 是否提供範例情境 / 範例資料 |
| **out-of-scope 明示** | §1 是否列出「這次不改」 |
| **PO 補問同步** | `checkList.md` 中的 Blocker 是否在 spec 中以 ⚠️ 標註 |

#### Gate 判定規則

- 任一 Blocker 未通過 → **FAIL**(不可進 SA)
- 全部 Blocker 通過、存在 Warning → **CONDITIONAL PASS**(可進,附風險清單)
- 全部 Blocker 通過、無 Warning → **PASS**

---

### Step 4:執行 Readability Review(軟指標)

採 **cold-read 模擬**:扮演一個沒參與這張票的人,從頭讀一遍,標記每一處認知摩擦。
**重要原則**:Readability 不得靠刪減資訊加分,只能靠重組、分層、補圖、定義術語。

每個子項以 0/1/2 計分(0=明顯問題、1=可接受、2=良好)。

#### 4A. 結構 (Structure) — 總分 6

| 子項 | 0 / 1 / 2 |
|------|----------|
| 每個 section 開頭有「這段在解決什麼」的定位句 | 0=多數沒有 / 1=部分有 / 2=幾乎都有 |
| 資訊由整體到細節分層,無突兀跳躍 | 0=多處跳躍 / 1=偶有跳躍 / 2=流暢 |
| 巢狀層級不超過 3 層 | 0=多處超過 / 1=少數超過 / 2=未超過 |

#### 4B. 語言 (Language) — 總分 6

| 子項 | 0 / 1 / 2 |
|------|----------|
| 專有名詞 / 縮寫首次出現即有定義或連結 | 0=多數沒有 / 1=部分有 / 2=幾乎都有 |
| 指代清楚(無懸空的「它 / 該功能 / 上述」) | 0=多處懸空 / 1=少數懸空 / 2=清楚 |
| 段落聚焦單一概念,過長段落(> 5 句)有拆分 | 0=多處過長 / 1=少數過長 / 2=適當 |

#### 4C. 視覺與可掃描性 (Visual & Scannability) — 總分 6

| 子項 | 0 / 1 / 2 |
|------|----------|
| 複雜流程 / 狀態 / 關係有圖輔助 | 0=純文字 / 1=部分有圖 / 2=該有圖的都有 |
| 表格用於結構化資料,而非長串條列 | 0=結構化資料用條列 / 1=部分 / 2=適當 |
| 關鍵結論 / 數值可被快速掃描 | 0=埋在段落中 / 1=部分 / 2=易掃描 |

#### 4D. 可追蹤性 (Traceability) — 總分 6

| 子項 | 0 / 1 / 2 |
|------|----------|
| 跨 section 引用可被追蹤(「見 §8」指向存在且相關內容) | 0=多處斷裂 / 1=少數 / 2=完整 |
| 對外部來源連結有上下文說明(讀者知道點進去看到什麼) | 0=多數無說明 / 1=部分 / 2=完整 |

#### 4E. 計分換算

- 各維度合計 24 分,換算為 100 分制:`總分 = (得分 / 24) × 100`
- 輸出**不是 pass/fail**,而是:總分 + 各維度分數 + **每個維度最弱的前 3 個具體改善建議**

---

### Step 5:合併輸出 review-report.md

寫入 `{repo}/ra-docs/{ISSUE_KEY}/review-report.md`,結構如下:

```markdown
---
issue_key: VIPOP-1234
review_mode: both
readiness_result: CONDITIONAL_PASS    # PASS | CONDITIONAL_PASS | FAIL
readability_score: 76
reviewed_at: 2026-05-29T...
---

# Review Report — VIPOP-1234

## 摘要
- **Readiness**: CONDITIONAL PASS(2 Warning,0 Blocker)
- **Readability**: 76 / 100
- **一句話結論**:可進 SA,但建議優先補強 §15 例外處理、優化 §3 與 §8 的可讀性。

---

## A. Readiness(就緒度 — 硬門檻)

### 🔴 Blocker(n)
*無 / 或逐條列出缺口,每條包含:檢查項、所在 section、具體問題、建議補充內容*

### 🟡 Warning(n)
*逐條列出*

### 🟢 Info(n)
*逐條列出*

---

## B. Readability(可讀性 — 軟指標)

### 各維度分數

| 維度 | 得分 | 滿分 |
|------|------|------|
| 結構 (Structure) | 5 | 6 |
| 語言 (Language) | 4 | 6 |
| 視覺與可掃描性 | 4 | 6 |
| 可追蹤性 | 5 | 6 |
| **總分** | **18 / 24 → 76 / 100** | |

### 優先改善建議(Top 3)

1. **§3 文案版面**:段落過長(8 句),建議拆分為「現狀 / 調整後 / 影響」三段。
2. **§8 功能移除**:首次出現「會員資料保留策略」未定義,建議在段首加註或連結至 §2。
3. **§4 操作流程**:純文字描述條件分支,建議改用 Mermaid flowchart。

---

## C. 附錄:逐項檢查明細

*完整列出每個檢查項的判定結果與依據(讓 SA / PO 可追溯為什麼被判 pass 或 fail)*
```

**複合情境**:若是複合情境,在「A. Readiness」與「B. Readability」下,**先給整票摘要,再依子 spec 編號分區**,每份子 spec 各列一份結果。檔名仍為單一 `review-report.md`。

---

### Step 6:對話輸出摘要

**不在對話輸出完整報告內容**,只輸出:

```
✅ Review 已完成

📁 報告位置
   {repo}/ra-docs/{ISSUE_KEY}/review-report.md

🚦 Readiness:{PASS | CONDITIONAL PASS | FAIL}
   - Blocker:{X} 個
   - Warning:{Y} 個
   - Info:{Z} 個

📖 Readability:{score} / 100
   - 結構 {a}/6 | 語言 {b}/6 | 視覺 {c}/6 | 可追蹤 {d}/6

🔴 若 Readiness = FAIL,逐條列出 Blocker(最多 3 條),建議先用 jira-to-spec-iterate 補強後再 review

📝 一句話結論:{一句話總結}
```

---

## 注意事項

- **語言**:中文為主,技術術語 / 路徑 / Section 編號維持原文。
- **不捏造**:若某項檢查因規格書本身結構不清而無法判定,標 `⚠️ 無法判定(原因)`,**不要為了給結論而硬猜**。
- **不修改規格書**:本 skill 唯讀輸入,只寫 `review-report.md`,絕不動既有 `.spec.md`。
- **不回頭核對外部來源**:Axure/Figma 連結只檢查格式合法,不實際開啟(未來 `--verify-sources` 擴充)。
- **複合情境**:每份子 spec 各跑一次 review,整份報告依子 spec 分區呈現。
- **Readability 不擋關**:即使 Readability 0 分,只要 Readiness PASS 就可進 SA(僅建議優化)。
- **與 PO checkList 的關係**:本 skill 的 Blocker 對應「SA 視角的缺口」,checkList 的 Blocker 對應「PO 視角待回答」— 兩者語意不同,不互相取代。

---

## 範例觸發語句

應觸發此 skill:
- `review VIPOP-44376 規格書`
- `審查 VIPOP-567 的規格書`
- `VIPOP-111 可以進 SA 了嗎`
- `驗證 VIPOP-890 規格書品質`
- `檢查 VIPOP-1234 規格書`

不應觸發:
- `分析 VIPOP-1234` → jira-analyzer
- `幫 VIPOP-1234 寫規格書` → jira-to-spec
- `更新 VIPOP-1234 規格書` → jira-to-spec-iterate
- `VIPOP-1234 PO 版 HTML` → spec-md-to-po-html
