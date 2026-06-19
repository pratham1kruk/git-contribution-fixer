#!/bin/bash
# ============================================================
#   report.sh  — Shared TXT + JSON report helpers
#   Feature 2: txt file AND JSON report export
#   Source this file:  source "$(dirname "$0")/report.sh"
# ============================================================

# ── Init ─────────────────────────────────────────────────────
# Call once at script start:
#   report_init "audit_report" "$BASE_PATH"
# Sets:  REPORT_TXT  REPORT_JSON  _JSON_REPOS (array)

report_init() {
  local script_name="$1"
  local base_path="$2"
  local ts; ts=$(date +%Y%m%d_%H%M%S)

  # Resolve to absolute path; fall back to current directory if empty or non-existent
  if [ -d "$base_path" ]; then
    base_path="$(cd "$base_path" && pwd)"
  else
    base_path="$(pwd)"
    echo -e "  ${YELLOW}⚠️  Report path invalid — saving reports to current directory: $base_path${RESET}"
  fi

  REPORT_TXT="${base_path}/${script_name}_${ts}.txt"
  REPORT_JSON="${base_path}/${script_name}_${ts}.json"

  _JSON_META_SCRIPT="$script_name"
  _JSON_META_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  _JSON_META_PATH="$base_path"
  _JSON_REPOS=()          # accumulates per-repo JSON objects
  _JSON_SUMMARY="{}"      # filled by report_finalize
}

# ── Log a plain line to TXT only ─────────────────────────────
rtxt() { echo -e "$*" | strip_color >> "$REPORT_TXT"; }

# ── Per-repo data accumulation ───────────────────────────────
# Start a new repo JSON block
report_repo_start() {
  _RJSON_NAME="$1"
  _RJSON_REMOTE="$2"
  _RJSON_BRANCH="$3"
  _RJSON_STATUS=""
  _RJSON_TOTAL=0
  _RJSON_WRONG=0
  _RJSON_EMAILS="[]"
  _RJSON_ISSUES="[]"
  _RJSON_NOTES="[]"
}

report_repo_set()   { eval "_RJSON_${1}=\"\$2\""; }   # STATUS TOTAL WRONG EMAILS ISSUES
report_repo_note()  { _RJSON_NOTES=$(json_append "$_RJSON_NOTES" "$(json_str "$1")"); }

# Commit the current repo block to the accumulator
report_repo_commit() {
  local obj
  obj=$(cat <<JSON
    {
      "repo": $(json_str "$_RJSON_NAME"),
      "remote": $(json_str "$_RJSON_REMOTE"),
      "branch": $(json_str "$_RJSON_BRANCH"),
      "status": $(json_str "$_RJSON_STATUS"),
      "total_commits": $_RJSON_TOTAL,
      "wrong_commits": $_RJSON_WRONG,
      "email_distribution": $_RJSON_EMAILS,
      "issues": $_RJSON_ISSUES,
      "notes": $_RJSON_NOTES
    }
JSON
)
  _JSON_REPOS+=("$obj")
}

# ── Summary ──────────────────────────────────────────────────
report_set_summary() {
  # Args: total_repos repos_with_issues clean_repos total_commits wrong_commits
  _JSON_SUMMARY=$(cat <<JSON
  {
    "repos_scanned": $1,
    "repos_with_issues": $2,
    "clean_repos": $3,
    "total_commits_scanned": $4,
    "wrong_commits_found": $5
  }
JSON
)
}

# ── Finalize: write both files ────────────────────────────────
report_finalize() {
  # Build JSON array of repos
  local repos_json
  repos_json=$(IFS=,; echo "[${_JSON_REPOS[*]}]")

  cat > "$REPORT_JSON" <<JSON
{
  "meta": {
    "script": $(json_str "$_JSON_META_SCRIPT"),
    "generated": "$_JSON_META_DATE",
    "base_path": $(json_str "$_JSON_META_PATH")
  },
  "summary": $_JSON_SUMMARY,
  "repos": $repos_json
}
JSON

  echo -e "\n  📄 TXT  → ${BOLD}$REPORT_TXT${RESET}"
  echo -e "  📋 JSON → ${BOLD}$REPORT_JSON${RESET}"
}

# ── JSON helpers ──────────────────────────────────────────────
json_str()    { printf '"%s"' "${1//\"/\\\"}"; }
json_append() {
  # json_append "[]" '"item"'  →  '["item"]'
  local arr="$1" item="$2"
  if [ "$arr" = "[]" ]; then echo "[$item]"
  else echo "${arr%]},$item]"; fi
}