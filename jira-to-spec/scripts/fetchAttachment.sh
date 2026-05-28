#!/usr/bin/env bash
# ============================================================
# fetchAttachment.sh
# 從 Jira Cloud 下載 ticket 的所有附件 binary
#
# 為什麼只支援 Jira：
#   實測 Confluence Cloud 的 /wiki/download/attachments/ endpoint
#   無論 Basic Auth + API Token 怎麼包裝都會回 401。Atlassian 對該 endpoint
#   只接受 OAuth Bearer Token，不接受 API Token。本腳本不處理 Confluence，
#   請使用者改在瀏覽器開啟 Confluence 頁面手動下載附件。
#
# 設計原則：
#   - Token 只在 runtime 從 env var 或互動式輸入取得，腳本不持久化
#   - 不接觸 AI / LLM；使用者自行掌控 token 生命週期
#   - 失敗時 echo 明確原因（401/403/404/network），不靜默
#
# 認證準備：
#   1. 申請 Atlassian API Token: https://id.atlassian.com/manage-profile/security/api-tokens
#   2. export ATLASSIAN_EMAIL="your-email@company.com"
#   3. export ATLASSIAN_API_TOKEN="ATATT3..."
#   （或執行時互動式輸入，token 不會回寫到 history）
#
# 使用方式：
#   # 1. 下載單一 Jira 附件（已知 attachment id）
#   ./fetchAttachment.sh jira <attachmentId> [--out <path>] [--site <site>]
#
#   # 2. 下載某張 Jira ticket 的所有附件（用 issue key）
#   ./fetchAttachment.sh issue <ISSUE_KEY> [--out <dir>] [--site <site>]
#
#   # 3. 從規格書資料夾自動推斷 issue key 並下載所有附件
#   #    自動解析資料夾名稱（例如 .../VIPOP-45198 → VIPOP-45198）
#   ./fetchAttachment.sh all <ra-docs-path> [--site <site>]
#
# 範例：
#   export ATLASSIAN_EMAIL=steven.chen@104.com.tw
#   export ATLASSIAN_API_TOKEN=ATATT3xFfGF0...
#   ./fetchAttachment.sh jira 608356 --out ./files
#   ./fetchAttachment.sh issue VIPOP-45198 --out ./files
#   ./fetchAttachment.sh all ./ra-docs/VIPOP-45198
# ============================================================

set -euo pipefail

# ---------- 顏色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

print_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
print_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_err()  { echo -e "${RED}✗ $1${NC}" >&2; }
print_info() { echo -e "${GRAY}  $1${NC}"; }

# ---------- 預設值 ----------
DEFAULT_SITE="104corp.atlassian.net"
SITE="$DEFAULT_SITE"

# ---------- 工具函式 ----------

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

require_cmd() {
  if ! command -v "$1" &> /dev/null; then
    print_err "找不到必要指令: $1"
    print_info "請先安裝：brew install $1"
    exit 1
  fi
}

require_creds() {
  if [[ -z "${ATLASSIAN_EMAIL:-}" ]]; then
    print_warn "ATLASSIAN_EMAIL 未設定"
    read -r -p "  請輸入 Atlassian email: " ATLASSIAN_EMAIL
    export ATLASSIAN_EMAIL
  fi

  if [[ -z "${ATLASSIAN_API_TOKEN:-}" ]]; then
    print_warn "ATLASSIAN_API_TOKEN 未設定"
    print_info "申請網址: https://id.atlassian.com/manage-profile/security/api-tokens"
    read -r -s -p "  請貼上 API Token (輸入後不會顯示): " ATLASSIAN_API_TOKEN
    echo
    export ATLASSIAN_API_TOKEN
  fi

  # 移除前後空白與換行符（貼上 token 時最常見的 bug 來源）
  ATLASSIAN_EMAIL="${ATLASSIAN_EMAIL#"${ATLASSIAN_EMAIL%%[![:space:]]*}"}"
  ATLASSIAN_EMAIL="${ATLASSIAN_EMAIL%"${ATLASSIAN_EMAIL##*[![:space:]]}"}"
  ATLASSIAN_API_TOKEN="${ATLASSIAN_API_TOKEN#"${ATLASSIAN_API_TOKEN%%[![:space:]]*}"}"
  ATLASSIAN_API_TOKEN="${ATLASSIAN_API_TOKEN%"${ATLASSIAN_API_TOKEN##*[![:space:]]}"}"

  if [[ -z "${ATLASSIAN_EMAIL}" || -z "${ATLASSIAN_API_TOKEN}" ]]; then
    print_err "未提供認證資訊，無法繼續"
    exit 1
  fi

  local token_len=${#ATLASSIAN_API_TOKEN}
  if (( token_len < 100 )); then
    print_warn "Token 長度只有 ${token_len} 字元，明顯小於 Atlassian API Token 正常長度（~192）"
    print_warn "可能是貼上時被截斷，若後續出現 401 請重新申請或重新貼上"
  fi
}

# Usage: curl_auth <url> <output-path>
# Returns: HTTP status code (echo)
curl_auth() {
  local url="$1"
  local out="$2"
  curl -sS -L \
    --max-redirs 5 \
    -u "${ATLASSIAN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
    -H "Accept: */*" \
    -w "%{http_code}" \
    -o "$out" \
    "$url"
}

verify_not_login_page() {
  local file="$1"
  local mime
  mime=$(file -b --mime-type "$file" 2>/dev/null || echo "unknown")
  [[ "$mime" != "text/html" ]]
}

handle_response() {
  local code="$1"
  local file="$2"
  local label="$3"

  case "$code" in
    200)
      if verify_not_login_page "$file"; then
        local size
        size=$(du -h "$file" | cut -f1)
        print_ok "$label  ($size)"
        return 0
      else
        print_err "$label  下載成功但內容是 HTML（多半是 token 無效，被導向登入頁）"
        rm -f "$file"
        return 1
      fi
      ;;
    401) print_err "$label  HTTP 401 — token 錯誤或過期"; rm -f "$file"; return 1 ;;
    403) print_err "$label  HTTP 403 — 沒有權限存取此資源"; rm -f "$file"; return 1 ;;
    404) print_err "$label  HTTP 404 — 資源不存在（id 錯誤）"; rm -f "$file"; return 1 ;;
    000) print_err "$label  網路錯誤（無法連線）"; rm -f "$file"; return 1 ;;
    *)   print_err "$label  HTTP $code — 未預期狀態"; rm -f "$file"; return 1 ;;
  esac
}

# ---------- Jira 附件下載 ----------

# 下載單一 attachment id 到指定目錄
# Usage: fetch_jira_attachment <attachmentId> <out-dir>
fetch_jira_attachment() {
  local att_id="$1"
  local out_dir="$2"

  mkdir -p "$out_dir"

  local meta_file
  meta_file=$(mktemp)
  local code
  code=$(curl_auth \
    "https://${SITE}/rest/api/3/attachment/${att_id}" \
    "$meta_file")

  if [[ "$code" != "200" ]]; then
    print_err "metadata 查詢失敗 HTTP $code (id=$att_id)"
    rm -f "$meta_file"
    return 1
  fi

  local filename
  filename=$(jq -r '.filename // empty' "$meta_file" 2>/dev/null || echo "")
  rm -f "$meta_file"

  if [[ -z "$filename" ]]; then
    filename="jira-attachment-${att_id}"
  fi

  local out_path="${out_dir}/${filename}"

  code=$(curl_auth \
    "https://${SITE}/rest/api/3/attachment/content/${att_id}" \
    "$out_path")

  handle_response "$code" "$out_path" "  → $filename"
}

# 列出 issue 的所有附件並下載
# Usage: fetch_jira_issue_attachments <issueKey> <out-dir>
fetch_jira_issue_attachments() {
  local issue_key="$1"
  local out_dir="$2"

  mkdir -p "$out_dir"

  print_step "查詢 Jira issue $issue_key 的附件清單"
  local issue_file
  issue_file=$(mktemp)
  local code
  code=$(curl_auth \
    "https://${SITE}/rest/api/3/issue/${issue_key}?fields=attachment" \
    "$issue_file")

  if [[ "$code" != "200" ]]; then
    print_err "issue 查詢失敗 HTTP $code (key=$issue_key)"
    rm -f "$issue_file"
    return 1
  fi

  local count
  count=$(jq '.fields.attachment | length' "$issue_file" 2>/dev/null || echo 0)
  print_info "找到 $count 個附件"

  if [[ "$count" -eq 0 ]]; then
    print_warn "此 issue 沒有附件"
    rm -f "$issue_file"
    return 0
  fi

  local success=0 failed=0
  while IFS= read -r row; do
    local att_id filename
    att_id=$(echo "$row" | jq -r '.id')
    filename=$(echo "$row" | jq -r '.filename')

    local out_path="${out_dir}/${filename}"
    local dl_code
    dl_code=$(curl_auth \
      "https://${SITE}/rest/api/3/attachment/content/${att_id}" \
      "$out_path")

    if handle_response "$dl_code" "$out_path" "  → $filename"; then
      ((success++)) || true
    else
      ((failed++)) || true
    fi
  done < <(jq -c '.fields.attachment[]' "$issue_file")

  rm -f "$issue_file"
  print_info "完成：$success 成功 / $failed 失敗"
}

# ---------- All 模式：從規格書目錄推斷 issue key ----------

# Usage: fetch_all <ra-docs-issue-path>
fetch_all() {
  local docs_dir="$1"

  if [[ ! -d "$docs_dir" ]]; then
    print_err "目錄不存在: $docs_dir"
    return 1
  fi

  # 從資料夾名稱推斷 issue key（例如 ra-docs/VIPOP-45198 → VIPOP-45198）
  local issue_key
  issue_key=$(basename "$docs_dir")

  if [[ ! "$issue_key" =~ ^[A-Z]+-[0-9]+$ ]]; then
    print_err "無法從資料夾名稱推斷 issue key: $issue_key"
    print_info "請改用：fetchAttachment.sh issue <ISSUE_KEY> --out $docs_dir/files"
    return 1
  fi

  print_info "從資料夾名稱推斷 issue key: $issue_key"

  local files_dir="${docs_dir}/files"
  mkdir -p "$files_dir"

  fetch_jira_issue_attachments "$issue_key" "$files_dir"

  echo
  print_warn "Confluence 附件無法經由 API Token 下載（Atlassian Cloud 限制）"
  print_info "請至 Confluence 頁面手動下載圖片到：${docs_dir}/images/"
  print_info "頁面清單參考：${docs_dir}/confluence-sitemap.md"
}

# ---------- 主流程 ----------

main() {
  require_cmd curl
  require_cmd jq
  require_cmd file

  if [[ $# -lt 1 ]]; then
    usage
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    -h|--help|help)
      usage
      ;;
  esac

  local positional=()
  local OUT_OVERRIDE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --site)
        SITE="$2"
        shift 2
        ;;
      --out)
        OUT_OVERRIDE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  require_creds

  print_info "站台: ${SITE}"
  print_info "認證: ${ATLASSIAN_EMAIL}"

  case "$cmd" in
    jira)
      if [[ ${#positional[@]} -lt 1 ]]; then
        print_err "需要 attachmentId"
        usage
      fi
      local out_dir="${OUT_OVERRIDE:-./files}"
      fetch_jira_attachment "${positional[0]}" "$out_dir"
      ;;
    issue)
      if [[ ${#positional[@]} -lt 1 ]]; then
        print_err "需要 issue key（例如 VIPOP-45198）"
        usage
      fi
      local out_dir="${OUT_OVERRIDE:-./files}"
      fetch_jira_issue_attachments "${positional[0]}" "$out_dir"
      ;;
    all)
      if [[ ${#positional[@]} -lt 1 ]]; then
        print_err "需要規格書資料夾路徑（例如 ra-docs/VIPOP-45198）"
        usage
      fi
      fetch_all "${positional[0]}"
      ;;
    confluence)
      print_err "confluence 模式已移除"
      print_info "原因：Atlassian Cloud 的 Confluence download endpoint 不接受 API Token 認證"
      print_info "請至 Confluence 頁面用瀏覽器手動下載圖片"
      exit 1
      ;;
    *)
      print_err "未知指令: $cmd"
      usage
      ;;
  esac
}

main "$@"
