# 複合情境處理 — composite.md

> 前提：由主檔 Step 3-2 判定為「複合情境」（存在 2 個以上不同的 (scope, type) 組合）時進入。
> 職責：拆分結構 → 各子 spec 填充 → index 檔 → 複合補問清單 → 輸出結構 → 對話摘要，全程涵蓋。
> 依賴：scope / type 詞彙與「(scope, type) → Section 對照表」見 `requirement-types.md`。

## 1. 拆分結構（sub_specs）

將 change units 按 (scope, type) 組合分群，輸出 `sub_specs` 結構：

```yaml
sub_specs:
  - id: 01
    scope: feature
    type: interaction
    topic: batch-submit              # Agent 生成短英文 slug
    topic_zh: 批次投遞互動           # 中文標題（用於 index）
    change_units: [U1, U2]
    sections: [1, 2, 4, 5, 15, 16]   # 依 requirement-types.md 對照表決定（依此 sub 的 scope×type）

  - id: 02
    scope: patch
    type: permission
    topic: permission-control
    topic_zh: 權限控管
    change_units: [U3]
    sections: [...]                  # 同上，依對照表決定

  - id: 03
    scope: feature
    type: ga
    topic: ga-tracking
    topic_zh: GA 追蹤
    change_units: [U4]
    sections: [...]                  # 同上
```

**排序原則：**
1. `change_units` 數量最多的子情境 → `01`（視為主軸）
2. 其他依 `change_units` 數量遞減排序
3. 同數量時，scope 為 `feature` 的優先

**topic slug 生成規則：**
- 純英文小寫 + 連字號，長度 ≤ 25 字元
- 取自 change unit 的 `target` 或 `summary` 主語
- 範例：`batch-submit` / `permission-control` / `ga-tracking` / `resume-list-filter`

→ 進入第 2 節，對每個 sub_spec 各填一份

## 2. 各子 spec 填充

對上一節輸出的每個 `sub_specs[i]`，各自產出一份子 spec：

1. **建立子 spec 內容骨架**，使用該子情境的 `sections` 清單
2. **限定填充範圍**：只用該子情境的 `change_units` 對應的 jira.md / 外部規格（PDF 指定頁或 confluence-spec.md）內容
3. **跨子情境引用**：若某個 change unit 與其他子情境相關，用以下格式標註：
   ```markdown
   > 📎 此項與子情境 02（權限控管）相關，詳見 `VIPOP-1234-02-permission-control.spec.md`
   ```
4. **頂部加入 frontmatter**：
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

**填充原則（其餘）**：沿用主檔 Step 4B-1 的 7 條共通原則（忠實呈現、留言補充、流程圖、狀態圖、引用附件、Section 16 主動出題、前端視角，含 files/ 的引用方式）。

## 3. index 檔（{ISSUE_KEY}-index.md）

額外產出 `{ISSUE_KEY}-index.md`：

```markdown
---
issue_key: VIPOP-1234
type: composite
sub_spec_count: 3
generated_at: 2026-05-14T...
---

# VIPOP-1234 規格書索引

## 偵測結果
此票偵測到 3 個獨立 (scope, type) 組合，已拆分為 3 份子 spec。

## 拆分理由
- 子情境之間 scope × type 不同，合併會造成模板章節衝突
- 拆分後 SA 可依角色分配閱讀（例：後端工程師只看 02-permission）

## 子 spec 列表

| # | 主題 | scope × type | 主要章節 | 依賴 |
|---|------|-------------|---------|------|
| 01 | 批次投遞互動 | feature × interaction | §1, §2, §4, §5, §15, §16 | — |
| 02 | 權限控管 | patch × permission | §1, §2, §6, §15, §16 | 01 |
| 03 | GA 追蹤 | feature × ga | §1, §12, §16 | 01 |

## 共用資源
- Jira 來源快照：`./jira.md`
- 外部規格 PDF：`./files/`（confluence-spec.pdf / axure-spec.pdf，若有）
- PDF 索引：`./confluence-pdf-index.md` / `./axure-pdf-index.md`（若有）
- PO 補問清單：`./VIPOP-1234-checkList.md`

## 子 spec 檔案
- [01 批次投遞互動](./VIPOP-1234-01-batch-submit.spec.md)
- [02 權限控管](./VIPOP-1234-02-permission-control.spec.md)
- [03 GA 追蹤](./VIPOP-1234-03-ga-tracking.spec.md)
```

## 4. PO 補問清單（複合版）

> 每個 🔴 Blocker / 🟡 Warning 都要標 `🔗 影響` 與 `背景` 兩行——規則見主檔 Step 5
> 「影響與背景標註總則」，是主檔 Step 5C overview 圖與詳述卡片的資料源頭。

整票一份 `{ISSUE_KEY}-checkList.md`，內部按子情境分組：

```markdown
# VIPOP-1234 PO 補問清單（複合情境）

> 此票拆為 3 份子 spec，問題依子情境分組。每題後標註對應的子 spec 編號。

## 🔴 Blocker — 全票阻塞問題（跨子情境）

**Q-001：{跨子情境的關鍵問題，例如命名規範、共用元件命名}**
- 🔗 影響：U1、U2、U3（跨 3 個子情境）
- 背景：{前後文}
- [ ] A. ...

---

## 子情境 01：批次投遞互動

### 🔴 Blocker
**Q-002：{問題}** `[子 spec 01]`
- 🔗 影響：U1、§4、§16
- 背景：{前後文}
- [ ] A. ...

### 🟡 Warning
**Q-003：{問題}** `[子 spec 01]`
- 🔗 影響：§5
- 背景：{前後文}

---

## 子情境 02：權限控管

### 🔴 Blocker
**Q-004：{問題}** `[子 spec 02]`
- 🔗 影響：Q-005、U3、§2、§15
- 背景：{前後文}

### 🟡 Warning
**Q-005：{問題}** `[子 spec 02]`
- 🔗 影響：§15
- 背景：{前後文}

---

## 子情境 03：GA 追蹤

### 🟡 Warning
**Q-006：{問題}** `[子 spec 03]`
- 🔗 影響：§12
- 背景：{前後文}

---

## 🟢 Info — 全票通用 AI 假設（無異議視為同意）
- A-001：{假設}
- A-002：{假設}
```

**分組原則：**
- Blocker 中跨子情境的問題放最前（整票阻塞）
- 子情境內部依 Blocker / Warning 兩級排列
- Info 因為通常影響面較廣，統一放最後
- 每個問題後標註 `` `[子 spec NN]` `` 方便對應

→ 補問清單完成後，回主檔跑 **Step 5C**（整票 overview 圖與可開工比例，單一 / 複合共用），再進入第 5 節輸出。

## 5. 輸出結構

```
{repo}/ra-docs/{ISSUE_KEY}/
  ├── jira.md                                   （共用）
  ├── confluence-pdf-index.md / axure-pdf-index.md  （共用，若有 PDF）
  ├── files/                                    （共用）
  ├── {ISSUE_KEY}-index.md                      ← 第 3 節產出
  ├── {ISSUE_KEY}-01-{topic}.spec.md            ← 第 2 節產出（子 spec 1）
  ├── {ISSUE_KEY}-02-{topic}.spec.md            ← 第 2 節產出（子 spec 2）
  ├── {ISSUE_KEY}-03-{topic}.spec.md            ← 第 2 節產出（子 spec 3）
  ├── {ISSUE_KEY}-checkList.md                  ← 第 4 節產出（共用，純補問清單）
  └── {ISSUE_KEY}-overview.html                 ← 主檔 Step 5C 產出（整票阻塞總覽 + 可開工比例，獨立 HTML，共用）
```

> 子 spec 數量取決於偵測到的子情境數量，可能是 2 / 3 / 4 / ... 份。

## 6. 對話輸出摘要（複合版）

```
✅ 複合情境規格書已產出（共 N 份子 spec）

📁 檔案位置
   {repo}/ra-docs/{ISSUE_KEY}/
   ├── jira.md / *-pdf-index.md / files/       （來源資料庫，共用）
   ├── {ISSUE_KEY}-index.md                    ← 從這裡開始閱讀
   ├── {ISSUE_KEY}-01-{topic}.spec.md
   ├── {ISSUE_KEY}-02-{topic}.spec.md
   ├── {ISSUE_KEY}-03-{topic}.spec.md
   ├── {ISSUE_KEY}-checkList.md                （純 PO 補問清單，共用）
   └── {ISSUE_KEY}-overview.html               （整票阻塞總覽 + 可開工比例，獨立 HTML，共用）

📊 拆分摘要
   偵測到 3 個獨立 (scope, type) 組合，已拆為 3 份子 spec：
   01. {topic_zh}  ({scope} × {type})  → §{sections}
   02. {topic_zh}  ({scope} × {type})  → §{sections}
   03. {topic_zh}  ({scope} × {type})  → §{sections}

   ⚠️ 待確認項目: {N} 個（含 Blocker {X} 個）
   📈 可開工: {可}/{總} 單元（✅{可} 可開工 / 🔴{n} 卡住 / 🟡{n} 待確認）｜卡住=等決策，非規格未寫

🔴 Blocker 摘要（需優先回答）
   {逐條列出 Blocker 問題，最多顯示 3 條，每條標註所屬子 spec}

{若 axure_skip=true}
⚠️ Axure 規格未納入
   偵測到 Axure 連結但未提供 PDF，所有子 spec 僅基於 Jira{若有 Confluence}/Confluence{/若} 內容，
   完成度可能不足。建議匯出 Axure PDF 後請我重跑。
```

> HTML 補充摘要（7C）為單一 / 複合共用，仍由主檔 Step 7C 處理，不在本檔。
