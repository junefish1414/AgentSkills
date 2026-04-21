#!/bin/bash
# ============================================================
# sync-template.sh
# 每日同步 jira-to-spec/references/template.md 從 GitHub 共管 repo
#
# 由 install.sh 安裝，請勿手動修改路徑設定
# 如需調整設定，請修改 ~/.skill-sources/config
# ============================================================

set -e

# ============================================================
# 讀取設定檔（由 install.sh 產生）
# ============================================================
CONFIG=~/.skill-sources/config

if [ ! -f "$CONFIG" ]; then
  echo "[ERROR] 找不到設定檔：$CONFIG"
  echo "        請重新執行 install.sh 進行設定"
  exit 1
fi

source "$CONFIG"

# ============================================================
# 變數
# ============================================================
LOG_DIR=~/.skill-sources
LOG=$LOG_DIR/sync.log
CHANGELOG_OUT=$LOG_DIR/last-template-change.md
BACKUP_DIR=$LOG_DIR/backups

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# 補齊 launchd / cron 缺少的 PATH
export PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

exec >> "$LOG" 2>&1
echo ""
echo "================================================================"
echo "[$TIMESTAMP] Sync started (user: $(whoami))"

# ============================================================
# 安全檢查
# ============================================================
if [ -z "$SKILL_REPO" ] || [ -z "$TEMPLATE_REL_PATH" ]; then
  echo "[ERROR] 設定檔缺少必要變數 SKILL_REPO 或 TEMPLATE_REL_PATH"
  exit 1
fi

if [ ! -d "$SKILL_REPO/.git" ]; then
  echo "[ERROR] $SKILL_REPO 不是 git repo"
  echo "        請確認 config 檔案中的 SKILL_REPO 路徑正確"
  exit 1
fi

cd "$SKILL_REPO"

TARGET_FILE="$SKILL_REPO/$TEMPLATE_REL_PATH"

# 若本地 template 有未 commit 的修改，跳過以免覆蓋
if ! git diff --quiet "$TEMPLATE_REL_PATH" 2>/dev/null; then
  echo "[WARN] 本地 $TEMPLATE_REL_PATH 有未 commit 的修改，跳過同步"
  osascript -e 'display notification "本地 template 有未 commit 的修改，跳過同步" with title "Skill Sync (skipped)"' 2>/dev/null || true
  exit 0
fi

# ============================================================
# Fetch & 比對
# ============================================================
echo "Fetching $REMOTE/$BRANCH..."
git fetch "$REMOTE" "$BRANCH" --quiet

REMOTE_CONTENT=$(git show "$REMOTE/$BRANCH:$TEMPLATE_REL_PATH" 2>/dev/null || echo "__FILE_NOT_ON_REMOTE__")

if [ "$REMOTE_CONTENT" = "__FILE_NOT_ON_REMOTE__" ]; then
  echo "[ERROR] $TEMPLATE_REL_PATH 在 $REMOTE/$BRANCH 上找不到"
  exit 1
fi

LOCAL_HASH=$(git hash-object "$TARGET_FILE" 2>/dev/null || echo "none")
REMOTE_HASH=$(echo "$REMOTE_CONTENT" | git hash-object --stdin)

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
  echo "No update. Local matches remote."
  rm -f "$CHANGELOG_OUT"
  exit 0
fi

# ============================================================
# 有更新，執行同步
# ============================================================
echo "Update detected!"
echo "  Local  hash: $LOCAL_HASH"
echo "  Remote hash: $REMOTE_HASH"

# 備份舊檔
if [ -f "$TARGET_FILE" ]; then
  BACKUP_FILE="$BACKUP_DIR/template.md.$(date +%Y%m%d_%H%M%S)"
  cp "$TARGET_FILE" "$BACKUP_FILE"
  echo "  Backed up to: $BACKUP_FILE"
fi

# 套用新版
echo "$REMOTE_CONTENT" > "$TARGET_FILE"
echo "  Updated: $TARGET_FILE"

# ============================================================
# 產出 changelog 供 Claude 讀取
# ============================================================
RECENT_COMMITS=$(git log "$REMOTE/$BRANCH" -5 --pretty=format:"- %s (%an, %ad)" --date=short -- "$TEMPLATE_REL_PATH")
LATEST_COMMIT_MSG=$(git log "$REMOTE/$BRANCH" -1 --pretty=format:"%s" -- "$TEMPLATE_REL_PATH")

cat > "$CHANGELOG_OUT" <<EOF
# Template 更新通知

**同步時間**: $TIMESTAMP
**Hash**: $LOCAL_HASH → $REMOTE_HASH
**檔案**: $TEMPLATE_REL_PATH

## 最近 5 次影響此檔案的 commit

$RECENT_COMMITS

## 備份位置

$BACKUP_FILE

---
*此檔案由 sync-template.sh 自動產出*
*如果今天沒有更新，此檔案會被刪除*
EOF

echo "  Changelog written to: $CHANGELOG_OUT"

# macOS 桌面通知
osascript -e "display notification \"$LATEST_COMMIT_MSG\" with title \"jira-to-spec template 已更新\" sound name \"Glass\"" 2>/dev/null || true

echo "[$TIMESTAMP] Sync completed successfully"
exit 0
