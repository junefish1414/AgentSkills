# AgentSkills — jira-to-spec

前端工程師用的 Claude skill，從 Jira ticket 自動產出規格書。

## 快速開始

### 1. Clone 這個 repo

```bash
git clone <repo-url> ~/AgentSkills
# 或者已有的話
git pull
```

### 2. 一鍵安裝同步腳本

```bash
bash ~/AgentSkills/jira-to-spec/scripts/install.sh
```

安裝過程會問你一個問題：**這個 repo 在你電腦上的路徑是哪裡**（例如 `/Users/yourname/AgentSkills`）。輸入完之後全自動，不需要再做任何事。

### 3. 把 SKILL.md 加入你的 Claude

把 `jira-to-spec/SKILL.md` 上傳到你的 Claude skill 設定中。

---

## 這套機制做了什麼

```
同事改 GitHub 上的 template.md
        ↓
你每天第一次開 terminal，背景自動 git fetch 比對
        ↓
有更新 → 自動套用 + 桌面通知 + 寫入 changelog
        ↓
你執行 /jira-to-spec
Claude 讀取最新 template → 告知你今天有更新 → 產出規格書
```

---

## 目錄結構

```
AgentSkills/
└── jira-to-spec/
    ├── SKILL.md                ← 上傳到 Claude 的 skill 指令
    ├── references/
    │   └── template.md         ← 規格書模板（大家共同維護）
    └── scripts/
        ├── install.sh          ← 一鍵安裝（每人只需跑一次）
        └── sync-template.sh    ← 每日同步腳本（install.sh 會自動部署）
```

---

## 常用指令

```bash
# 手動觸發同步（不等明天自動跑）
bash ~/.skill-sources/sync-template.sh

# 查看同步紀錄
tail -30 ~/.skill-sources/sync.log

# 查看今天有沒有更新
cat ~/.skill-sources/last-template-change.md   # 有更新才有這個檔案

# 查看備份
ls ~/.skill-sources/backups/
```

---

## 修改 template

1. 直接編輯 `jira-to-spec/references/template.md`
2. commit & push
3. 其他人下次開 terminal 就會自動同步

```bash
# 建議的 commit 格式（讓大家的通知訊息看得懂）
git commit -m "template: 新增 Section 17 PO 補問清單格式"
git commit -m "template: 調整 Section 16 例外情境欄位"
```

---

## 重新安裝 / 更新設定

如果換電腦、換路徑，或同步出現問題，重跑安裝腳本即可：

```bash
bash ~/AgentSkills/jira-to-spec/scripts/install.sh
```

---

## Troubleshooting

**Q：同步沒有跑？**
```bash
# 確認 zshrc 設定有沒有加進去
grep "skill-sync" ~/.zshrc

# 手動跑一次看 log
bash ~/.skill-sources/sync-template.sh
cat ~/.skill-sources/sync.log
```

**Q：桌面通知沒出現？**
macOS 設定 → 通知 → 找 Script Editor 或 Terminal → 開啟通知權限

**Q：想移除這套機制？**
```bash
# 移除 zshrc 設定（刪掉 # [skill-sync] 那幾行）
nano ~/.zshrc

# 移除腳本和設定
rm -rf ~/.skill-sources
```
