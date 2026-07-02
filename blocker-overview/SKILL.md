---
name: blocker-overview
description: >
  把「待決問題 → 改動單元」的阻塞影響關係 + 可開工比例，
  渲染成一張獨立、離線可開的總覽 HTML（兩欄關係圖 + 狀態色 + 連線 + 待決問題詳述卡片）。
  主要由 jira-to-spec 的 Step 5C 程式化呼叫；也可獨立使用——當使用者已有
  一組「問題/單元 + 影響連線 + 可開工比例」資料並要求「畫成阻塞總覽圖 / overview HTML」時觸發。
  本 skill 是純 renderer：不判斷誰卡誰、不算比例，那些由呼叫端決定後傳入。
compatibility: "純前端產物，無外部相依；輸出單一 self-contained HTML（不依賴任何 CDN）"
---

# Blocker Overview — 阻塞影響總覽 HTML 產生器

把結構化的阻塞關係資料套進固定範本，輸出一張**離線可開、不依賴 CDN** 的總覽 HTML。

## 角色定位

- **純 renderer**：只負責「資料 → 漂亮 HTML」。
- **不做語意判斷**：誰卡住誰（state）、可開工比例（X/Y）由呼叫端（如 jira-to-spec Step 5C）算好傳入。
- 範本：`{SKILL_REPO}/blocker-overview/references/overview-template.html`，**CSS / JS 不要改**，只替換 4 個區塊。

---

## 輸入介面

呼叫端提供以下結構化資料（缺 summary 可省）：

```yaml
issue_key: VIPOP-1234
summary: 批次投遞 / 權限 / GA          # 標題副標，可空
out_path: {repo}/ra-docs/VIPOP-1234/VIPOP-1234-overview.html

ready:                                 # 可開工 X/Y（呼叫端算好）
  total: 4                             # 分母 = 改動單元「個數」
  ready: 1                             # ✅ 可開工
  stuck: 2                             # 🔴 卡住
  soft:  1                             # 🟡 待確認
  # 工時加權（gauge-weight 用）：各單元 size 中值加總。S≈0.5 · M≈1.5 · L≈4 · XL≈8（人/天）
  days_total: 6.5                      # 全票人/天
  days_ready: 0.5                      # ✅ 可開工單元人/天和
  days_stuck: 5.5                      # 🔴 卡住單元人/天和
  days_soft:  0.5                      # 🟡 待確認單元人/天和

# 兩欄節點：col 固定 decide / units（受影響規格章節不畫欄，改寫進 details 的 blocks 文字）
# title=完整問句/完整名稱（主管不查編號就懂）；desc=一行白話影響
# size=T-shirt 規模，只「units」欄要給（AI 依描述粗估：純文案=S、新 API＋狀態機=L…）
nodes:
  - { id: Q001, col: decide, qid: "🔴 Q-001 · 根決策", state: root,
      title: "列表要完整改版，還是只縮限現有範圍？", desc: "方向未定，半數單元範圍跟著未定" }
  - { id: U1,   col: units,  qid: "U1",  state: stuck, size: L, title: "批次投遞按鈕", desc: "等 Q-001 列表範疇拍板" }
  - { id: U4,   col: units,  qid: "U4",  state: free,  size: S, title: "GA 埋點",      desc: "無人阻擋，可直接開工" }

# 邊：只連 Q→Q（決策鏈）與 Q→U；不連規格章節
edges:
  - [Q001, U1, r]      # r=🔴  a=🟡  g=可開工/中性

# 待決問題詳述（每個 Blocker/Warning 一張卡）：主管讀懂前後文用
# 內容來自 checklist 該 Q 的完整描述 + 選項 + 🔗 影響
# ⚠️ blocks 要同時列「被卡的改動單元 + 受影響規格章節 §N」——圖上已無規格欄，§ 只在這裡出現
details:
  - qid: "🔴 Q-001 · 根決策"
    state: root                        # s-root / s-blk / s-warn
    badge: "連帶卡住 2 單元 · 1 規格"
    question: "列表要完整改版，還是只縮限現有範圍？"
    background: "這票要改投遞紀錄列表，PO 規格內同時出現整頁重做與只動現有欄位兩種描述，未指定採哪版。"
    options: ["A 完整改版（重做列表元件，工期大）", "B 只縮限（沿用版型微調，風險低）"]
    blocks: "U3 後台管理頁、§2 權限設計"
  - qid: "🟡 Q-004"
    state: warn
    badge: "不擋開工"
    question: "投遞結果的 toast 文案怎麼寫？"
    background: "投遞成功/失敗會跳 toast，規格只寫給提示未給確切文案，可先用暫定文案開工。"
    options: []                        # warn 題可空，範本就省「選項」列
    blocks: "§5 提示與文案（僅文字）"
```

### state ↔ class 對照（範本已定義樣式）

| 欄 | state | 意義 | class |
|----|-------|------|-------|
| decide | `root` | 被其他問題依賴的根決策（粗紅圈） | `n-root` |
| decide | `blk` | 🔴 Blocker | `n-blk` |
| decide | `warn` | 🟡 Warning | `n-warn` |
| units | `stuck` | 被未答 🔴 卡住 | `n-stuck` |
| units | `soft` | 只被 🟡 影響 | `n-soft` |
| units | `free` | ✅ 沒人擋、可開工 | `n-free` |

> 下方「待決問題詳述」卡片（`details`）用 `s-root` / `s-blk` / `s-warn`（同色系，只控卡片左邊框與編號色）。

---

## 執行步驟

1. 讀取範本 `{SKILL_REPO}/blocker-overview/references/overview-template.html`。
2. 替換範本頂部註解標示的 5 個區塊：
   - **〔1〕`.head`**：`{issue_key}` 填 `.key`，`規格總覽 — {summary}` 填 `<h1>`。
   - **〔2〕`.gauge`**（分數呈現，非百分比）：
     - `.gauge-pct` = `ready`（分子）；`.deno` = ` / {total}`（分母）
     - 標題那句「個改動單元 可立即開工（其餘卡在未決決策，非規格未寫）」**固定保留**——這句是避免被誤讀成 PO 規格分數的關鍵
     - `.bar` 三段 `width` = 各 `ready/stuck/soft ÷ total × 100`%（順序 green→red→amber）
     - `.legend` 三個 `<b>` = `ready` / `stuck` / `soft`
   - **〔2b〕`.gauge-weight`**（工時加權，讓嚴重性有感）：
     - `.wbar` 三段 `width` = 各 `days_ready/days_stuck/days_soft ÷ days_total × 100`%（順序同上）
     - `.wtext` = 「卡住 ~{days_stuck} 人/天（{days_stuck/days_total}%）　待確認 ~{days_soft} 人/天　可開工 ~{days_ready} 人/天」
     - `.wlabel` 的 `est` 免責句（size 為 AI 粗估、待 SA 校正 + S/M/L/XL 對應）**固定保留**
   - **〔3〕`.cols`**：依 `nodes` 每節點輸出（**units 欄的 node class 要多帶一個 `sz-{size}`**）：
     `<div class="node n-{state}{units 欄再加 " sz-"+size}" id="{id}"><span class="qid">{qid}</span>{units 欄加 <span class="nsize z-{size}" title="AI 粗估，待 SA 校正">{size}</span>}<div class="ntitle">{title}</div>{有 desc 才加 <div class="ndesc">{desc}</div>}</div>`，
     放進對應欄（decide=①/units=②）。同欄順序：問題欄 root 在最上、warn 在最下；單元欄 stuck → soft → free。
     - **size 只放 units 欄**（問題/規格欄不放），要**兩處都寫**：
       - node class 加 `sz-{S|M|L|XL}` → 範本依此**放大卡片高度＋字級**（越大越重）
       - 角落 span `nsize z-{S|M|L|XL}` → 範本依此**上色**（S 灰→M 藍→L 橙→XL 紅）
   - **〔4〕`EDGES`**：把 `edges` 轉成 JS 陣列 `['from','to','color']`。
   - **〔5〕`.detail`**：依 `details` 每筆輸出一張
     `<div class="dcard s-{state}">`，內含 head（`dcard-qid`=qid + `dcard-badge`=badge）、`dcard-q`=question，
     再依序輸出「背景 / 選項 / 卡住」三個 `dcard-row`（`options` 為空就**省略選項列**；`blocks` 填進「卡住」列）。
3. 寫出到 `out_path`。
4. 回報：HTML 絕對路徑 + 「可開工 {ready}/{total} 單元」一行。

---

## 注意事項

- 只替換註解標的 5 區塊（含 2b 工時），**CSS 與 `draw()` / `bindHover()` 一律保留**——佈局、連線、size 色、工時 bar 都靠它。
- **hover 高亮降噪、卡片大小隨 size 自動放大、點問題節點跳詳述** 全是範本內建互動：只要 `size` 的 `z-{S/M/L/XL}` class 給對、node `id` 與 `edges` 一致，就自動生效，AI 不用寫任何 JS。
- node `id` 必須與 `edges` 兩端完全一致，否則該線不畫（`draw()` 已對缺失節點容錯略過）。
- 邊只能連 `nodes` 內實際存在的 id（封閉集合，呼叫端已保證）。
- 產物為單檔 HTML，可直接 `open` 或附進 Jira / 寄給 PM；不需網路。
- 若呼叫端未提供 `ready`，可由 `nodes` 中 `col=units` 的 state 統計（free→ready / stuck→stuck / soft→soft）。
