# AgentSkills — jira-to-spec

前端工程師用的 Claude skill，從 Jira ticket 自動產出規格書。

---

## 前置需求

在開始安裝之前，請先確認以下兩個 MCP 已在 Claude 啟用。

### 1. Atlassian MCP
Claude 用來讀取 Jira ticket 內容。

**設定方式：**
1. 開啟 Claude 設定 → Integrations（整合）
2. 找到 Atlassian → 點擊連結
3. 用你的 Atlassian 帳號授權

### 2. Filesystem MCP
Claude 用來在執行 skill 時讀取你本地的 `template.md`。

**設定方式：**
1. 開啟 Claude 設定 → Integrations（整合）
2. 找到 Filesystem → 設定允許存取的路徑
3. 加入你之後要 clone 這個 repo 的路徑，例如：
   ```
   /Users/yourname/AgentSkills
   ```

> ⚠️ Filesystem MCP 的路徑在 Claude 執行 skill 時一定要有存取權限才能讀到 template。
> 若讀取失敗，Claude 會自動 fallback 使用 SKILL.md 內建的備用模板繼續執行。

---

## 安裝步驟

### Step 1：Clone repo

```bash
git clone <repo-url> ~/AgentSkills
# 或者已有的話
cd ~/AgentSkills && git pull
```

### Step 2：一鍵安裝同步腳本

```bash
bash ~/AgentSkills/jira-to-spec/scripts/install.sh
```

安裝過程只會問你一個問題：**這個 repo 在你電腦上的完整路徑**。

例如輸入：`/Users/yourname/AgentSkills`

輸入完之後全自動，安裝程式會幫你：
- 建立 `~/.skill-sources/` 目錄
- 寫入你的個人設定檔 `~/.skill-sources/config`
- 部署同步腳本至 `~/.skill-sources/sync-template.sh`
- 設定 `~/.zshrc`，每天開 terminal 自動在背景同步
- 立即跑一次驗證確認正常

### Step 3：上傳 SKILL.md 到 Claude

1. 開啟 Claude 設定 → Skills
2. 上傳 `jira-to-spec/SKILL.md`

---

## 完成！

安裝完成後，整套機制會自動運作：

```
同事改了 template.md 並 push
        ↓
你每天第一次開 terminal，背景自動同步
        ↓
有更新 → 桌面通知 + 寫入 changelog
        ↓
你輸入 /jira-to-spec VIPOP-XXXXX
Claude 讀取最新 template → 告知今天有更新 → 產出規格書
```

---

## 目錄結構

```
AgentSkills/
└── jira-to-spec/
    ├── SKILL.md                ← 上傳到 Claude 的 skill 指令
    ├── references/
    │   └── template.md         ← 規格書模板（大家共同維護這份）
    └── scripts/
        ├── install.sh          ← 一鍵安裝（每人只需跑一次）
        └── sync-template.sh    ← 每日同步腳本（install.sh 自動部署）
```

---

## 更新說明

這套機制有兩種更新情境，行為不同：

| 改什麼 | push 後怎麼生效 | 需要通知其他人嗎？ |
|--------|---------------|----------------|
| `template.md` | 同步腳本自動處理，不用做任何事 | 不用，自動同步 |
| `SKILL.md` | **每個人都要手動重新上傳到 Claude** | ✅ 要，請通知隊友 |

### 改 template 格式（最常見）

```bash
vi jira-to-spec/references/template.md

# commit 格式建議（讓其他人從通知看懂改了什麼）
git commit -m "template: 新增 Section 17 PO 補問清單格式"
git commit -m "template: 調整 Section 16 例外情境欄位"

git push
# 完成，其他人自動同步
```

### 改 skill 執行邏輯（較少見）

```bash
vi jira-to-spec/SKILL.md

git commit -m "skill: 新增 Step 0 template 更新通知"
git push

# ⚠️ push 完要通知隊友：「SKILL.md 有更新，請重新上傳到 Claude skill 設定」
```

---

## 常用指令

```bash
# 手動觸發同步（不等明天自動跑）
bash ~/.skill-sources/sync-template.sh

# 查看同步紀錄
tail -30 ~/.skill-sources/sync.log

# 確認今天有沒有 template 更新（有更新才有這個檔案）
cat ~/.skill-sources/last-template-change.md

# 查看備份清單
ls ~/.skill-sources/backups/

# 從備份還原（若新版本有問題）
cp ~/.skill-sources/backups/template.md.YYYYMMDD_HHMMSS \
   ~/AgentSkills/jira-to-spec/references/template.md
```

---

## Troubleshooting

**Q：同步沒有自動跑？**
```bash
# 確認 zshrc 設定有沒有加進去
grep "skill-sync" ~/.zshrc

# 手動跑一次並查看 log
bash ~/.skill-sources/sync-template.sh
cat ~/.skill-sources/sync.log
```

**Q：Claude 說「無法讀取本地模板，使用內建備用版本」？**

確認 Filesystem MCP 的允許路徑有包含你的 AgentSkills repo 路徑，
且路徑與 `~/.skill-sources/config` 裡的 `SKILL_REPO` 一致。

```bash
cat ~/.skill-sources/config
```

**Q：桌面通知沒出現？**

macOS 設定 → 通知 → 找到 Terminal 或 Script Editor → 開啟允許通知。

**Q：換電腦或換路徑怎麼辦？**

重新跑一次安裝腳本，會覆蓋舊設定：

```bash
bash ~/AgentSkills/jira-to-spec/scripts/install.sh
```

**Q：想完全移除這套機制？**

```bash
# 1. 移除 zshrc 裡的設定（刪掉 # [skill-sync] 那幾行）
nano ~/.zshrc

# 2. 移除腳本、設定和 log
rm -rf ~/.skill-sources
```