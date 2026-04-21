#!/bin/bash
# ============================================================
# install.sh
# jira-to-spec template 自動同步 — 一鍵安裝腳本
#
# 使用方式：
#   bash install.sh
#
# 會做的事：
#   1. 詢問你的 AgentSkills repo 本地路徑
#   2. 建立 ~/.skill-sources/ 目錄結構
#   3. 寫入個人設定檔 ~/.skill-sources/config
#   4. 安裝同步腳本
#   5. 設定 zshrc 每日自動觸發
#   6. 立即跑一次同步確認正常
# ============================================================

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
print_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_err()  { echo -e "${RED}✗ $1${NC}"; }

# install.sh 與 sync-template.sh 放在同一目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT_SRC="$SCRIPT_DIR/sync-template.sh"

echo ""
echo "=================================================="
echo "  jira-to-spec template 自動同步 — 安裝程式"
echo "=================================================="

# ============================================================
# Step 1：確認 sync-template.sh 存在
# ============================================================
print_step "Step 1：確認安裝檔案"

if [ ! -f "$SYNC_SCRIPT_SRC" ]; then
  print_err "找不到 sync-template.sh，請確認它與 install.sh 在同一個目錄"
  exit 1
fi
print_ok "sync-template.sh 找到了：$SYNC_SCRIPT_SRC"

# ============================================================
# Step 2：詢問設定
# ============================================================
print_step "Step 2：設定你的環境路徑"

echo ""
echo "請輸入你的 AgentSkills repo 本地路徑"
echo "（就是包含 jira-to-spec/references/template.md 的那個 repo 根目錄）"
echo ""
read -rp "路徑：" INPUT_SKILL_REPO

# 展開 ~ 符號
SKILL_REPO="${INPUT_SKILL_REPO/#\~/$HOME}"

# 驗證路徑
if [ ! -d "$SKILL_REPO" ]; then
  print_err "路徑不存在：$SKILL_REPO"
  exit 1
fi

if [ ! -d "$SKILL_REPO/.git" ]; then
  print_err "$SKILL_REPO 不是一個 git repo（找不到 .git 資料夾）"
  exit 1
fi

# 自動偵測 template.md 位置
TEMPLATE_REL_PATH=""
POSSIBLE_PATHS=(
  "jira-to-spec/references/template.md"
  "references/template.md"
  "template.md"
)
for p in "${POSSIBLE_PATHS[@]}"; do
  if [ -f "$SKILL_REPO/$p" ]; then
    TEMPLATE_REL_PATH="$p"
    break
  fi
done

if [ -z "$TEMPLATE_REL_PATH" ]; then
  print_warn "無法自動找到 template.md，請手動輸入相對路徑"
  read -rp "template.md 的相對路徑（相對於 repo 根目錄）：" TEMPLATE_REL_PATH
fi

print_ok "Repo 路徑：$SKILL_REPO"
print_ok "Template 路徑：$TEMPLATE_REL_PATH"

# 確認 remote 和 branch
cd "$SKILL_REPO"
REMOTE=$(git remote | head -1)
BRANCH=$(git remote show "$REMOTE" 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
if [ -z "$BRANCH" ]; then
  BRANCH="main"
fi

print_ok "Git remote：$REMOTE"
print_ok "Git branch：$BRANCH"

# ============================================================
# Step 3：建立目錄結構
# ============================================================
print_step "Step 3：建立目錄結構"

mkdir -p ~/.skill-sources/backups
print_ok "建立 ~/.skill-sources/backups/"

# ============================================================
# Step 4：寫入設定檔
# ============================================================
print_step "Step 4：寫入個人設定檔"

cat > ~/.skill-sources/config <<EOF
# jira-to-spec 同步設定
# 由 install.sh 自動產生，可手動修改
# 安裝時間：$(date '+%Y-%m-%d %H:%M:%S')

SKILL_REPO=$SKILL_REPO
TEMPLATE_REL_PATH=$TEMPLATE_REL_PATH
REMOTE=$REMOTE
BRANCH=$BRANCH
EOF

print_ok "設定檔寫入：~/.skill-sources/config"

# ============================================================
# Step 5：安裝同步腳本
# ============================================================
print_step "Step 5：安裝同步腳本"

cp "$SYNC_SCRIPT_SRC" ~/.skill-sources/sync-template.sh
chmod +x ~/.skill-sources/sync-template.sh
print_ok "腳本安裝至：~/.skill-sources/sync-template.sh"

# ============================================================
# Step 6：設定 zshrc 每日自動觸發
# ============================================================
print_step "Step 6：設定每日自動同步"

ZSHRC=~/.zshrc
MARKER="# [skill-sync] jira-to-spec template 自動同步"

if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
  print_warn "~/.zshrc 已有同步設定，跳過（避免重複）"
else
  cat >> "$ZSHRC" <<'EOF'

# [skill-sync] jira-to-spec template 自動同步
# 每天第一次開 terminal 時，在背景自動同步 template
_SKILL_SYNC_FLAG="/tmp/.skill-synced-$(date +%Y%m%d)"
if [ ! -f "$_SKILL_SYNC_FLAG" ]; then
  /bin/bash ~/.skill-sources/sync-template.sh > /dev/null 2>&1 &
  touch "$_SKILL_SYNC_FLAG"
fi
EOF
  print_ok "已加入 ~/.zshrc"
fi

# ============================================================
# Step 7：立即跑一次驗證
# ============================================================
print_step "Step 7：立即執行一次同步驗證"

echo ""
bash ~/.skill-sources/sync-template.sh
echo ""

# 看結果
LAST_LOG=$(tail -5 ~/.skill-sources/sync.log)
if echo "$LAST_LOG" | grep -q "Sync completed successfully\|No update"; then
  print_ok "同步執行成功！"
else
  print_warn "同步可能有問題，請查看 log："
  echo "$LAST_LOG"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo "=================================================="
echo -e "${GREEN}  安裝完成！${NC}"
echo "=================================================="
echo ""
echo "  設定檔    ~/.skill-sources/config"
echo "  同步腳本  ~/.skill-sources/sync-template.sh"
echo "  Log       ~/.skill-sources/sync.log"
echo "  備份      ~/.skill-sources/backups/"
echo ""
echo "  每天第一次開 terminal 會自動在背景同步"
echo "  手動觸發：bash ~/.skill-sources/sync-template.sh"
echo ""
echo "  若 template 有更新，會出現桌面通知"
echo "  Claude 執行 jira-to-spec 時也會自動告知變動"
echo ""
