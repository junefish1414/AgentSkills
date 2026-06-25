# 需求類型判斷 — scope / type 分類與 Section 對照

> 本檔由 jira-to-spec 的 Step 3 引用。
> 職責：定義 change unit 的分類詞彙（scope / type）、change_unit 結構，
> 以及「(scope, type) → 要填哪些 Section」的對照表。
> 單一情境與複合情境兩條路都會用到本檔。

## change_unit 結構

從 jira.md 與外部規格來源（PDF 索引 / confluence-spec.md）中，
識別所有獨立的改動點，每個改動點記錄為一個 change_unit：

```yaml
change_units:
  - id: U1
    scope: feature | patch | removal | tracking
    type: content | interaction | permission | ga
    target: <短描述，例如「履歷投遞按鈕」>
    summary: <一句話描述這個改動>
    source_refs:
      - jira.md#<段落或留言錨點>
      - files/{confluence|axure}-spec.pdf#p.<頁碼>   # 或 confluence-spec.md#<區段錨點>（fallback 情境）
```

## scope 判斷

| scope | 條件 |
|-------|------|
| `patch` | 修改文案 / 小幅 UI |
| `feature` | 新增功能 / 大幅改動 |
| `removal` | 移除功能 |
| `tracking` | 純埋點 |

## type 判斷

| type | 條件 |
|------|------|
| `content` | 純文案 / 版面（含純版面重排） |
| `interaction` | 操作流程、按鈕 |
| `permission` | 角色權限 |
| `ga` | 純 GA / NCC |

> 註：
> - 舊版的 `mixed` type 已被「單一 / 複合判斷」取代（見 composite.md），不再使用。
> - 舊版的 `layout` type 已移除，純版面重排併入 `content`。

## (scope, type) → Section 對照表

| scope / type | 必填 Section | 選填 Section |
|--------------|-------------|-------------|
| patch + content | 1, 3 | 15, 16 |
| patch + interaction | 1, 4, 5 | 15, 16 |
| patch + ga | 1, 12 | 16 |
| feature + interaction | 1, 2, 4, 5, 15, 16 | 6, 9, 10, 11, 12 |
| feature + permission | 1, 2, 4, 6, 15, 16 | 5, 7 |
| removal | 1, 8, 15 | 12, 13 |
| tracking | 1, 12 | 16 |

> 對照規則：
> - `removal` 與 `tracking` 以 **scope 單獨比對**（不分 type）。
> - 其餘以 (scope, type) 組合比對。
> - Section 的實際內容定義在 `references/template.md`，本表只決定「填哪幾號」。
> - **本表為常見組合，非全列舉**。未列出的 (scope, type) 由 agent 依 type 語意挑選相關 Section，
>   並在該 Section 標註 `⚠️ 對照表未定義此組合，建議與 PM 確認`，不靜默亂填。
