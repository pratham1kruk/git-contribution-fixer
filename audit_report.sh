#!/bin/bash
# ============================================================
#   audit_report.sh  v2.0
#   Git Email Audit Tool
#   Part of: git-identity-fixer toolkit
#
#   Features added:
#   [1] Colored CLI output        (via colors.sh)
#   [2] TXT + JSON report export  (via report.sh)
#   [3] GitHub API verification   (via github_api.sh)
#   [4] Contribution prediction   (via streak.sh)
#   [5] Streak safety warning     (via streak.sh)
#   [6] Auto UTC analysis         (via utc_analysis.sh)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/report.sh"
source "$SCRIPT_DIR/utc_analysis.sh"
source "$SCRIPT_DIR/streak.sh"
source "$SCRIPT_DIR/github_api.sh"

header "audit_report.sh  v2.0" "Git Email Audit Tool"

# ── Inputs ───────────────────────────────────────────────────
read -rp "  Enter base directory path (e.g. /mnt/d/git): " BASE_PATH
read -rp "  Enter your correct GitHub email: "              CORRECT_EMAIL
read -rp "  Enter your GitHub username: "                   GITHUB_USERNAME

echo ""
echo -e "  ${DIM}Optional: GitHub API token for live verification${RESET}"
github_prompt_token

BASE_PATH="${BASE_PATH%/}"

if [ ! -d "$BASE_PATH" ]; then
  echo -e "${RED}❌ ERROR: Directory does not exist${RESET}"
  exit 1
fi

# ── Feature 2: Init dual report ──────────────────────────────
report_init "audit_report" "$BASE_PATH"

{
  echo "Git Email Audit Report  v2.0"
  echo "Generated      : $(date)"
  echo "Base Path      : $BASE_PATH"
  echo "Expected Email : $CORRECT_EMAIL"
  echo "Username       : $GITHUB_USERNAME"
  echo "=========================="
  echo ""
} >> "$REPORT_TXT"

# ── Feature 3: GitHub API verification ───────────────────────
section "GITHUB API VERIFICATION"
github_verify_email "$CORRECT_EMAIL" "$GITHUB_USERNAME"
github_rate_limit

# ── Feature 6: Auto UTC analysis (pre-scan) ──────────────────
auto_utc_analysis "$BASE_PATH" "$CORRECT_EMAIL"

# ── Feature 5: Streak safety warning ─────────────────────────
streak_safety_check "$BASE_PATH" "$CORRECT_EMAIL"

echo ""
section "SCANNING REPOSITORIES"

TOTAL_REPOS=0
REPOS_WITH_ISSUES=0
TOTAL_COMMITS=0
TOTAL_WRONG_COMMITS=0

# Use absolute paths — never rely on cd .. to track position
for repo_dir in "$BASE_PATH"/*/; do
  [ -d "$repo_dir/.git" ] || continue

  ((TOTAL_REPOS++))
  rname=$(basename "$repo_dir")

  step "$rname"

  # All git commands use -C so working directory never changes
  REMOTE_URL=$(git -C "$repo_dir" remote get-url origin 2>/dev/null)
  BRANCH=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
  COMMIT_COUNT=$(git -C "$repo_dir" log --pretty=format:"%ae" 2>/dev/null | wc -l | tr -d ' ')
  WRONG_COUNT=$(git -C "$repo_dir" log --pretty=format:"%ae" 2>/dev/null | grep -cv "^${CORRECT_EMAIL}$")

  ((TOTAL_COMMITS      += COMMIT_COUNT))
  ((TOTAL_WRONG_COMMITS += WRONG_COUNT))

  # ── TXT: identical layout to v1 ──────────────────────────
  {
    echo "Repo: $rname/"
    echo "Remote: $REMOTE_URL"
    echo "Current Branch: $BRANCH"
    echo "Latest Commit:"
    git -C "$repo_dir" log -1 \
      --pretty=format:"  Hash  : %h%n  Author: %an%n  Email : %ae%n  ISO   : %ad" \
      --date=iso 2>/dev/null
    echo ""
    echo "Latest Commit UTC Time:"
    git -C "$repo_dir" log -1 --pretty=format:"  %ad" --date=utc 2>/dev/null
    echo ""
    echo ""
    echo "Total Commits: $COMMIT_COUNT"
    echo "Commit Email Distribution:"
    git -C "$repo_dir" log --pretty=format:"%ae" 2>/dev/null | sort | uniq -c | sort -rn
  } >> "$REPORT_TXT"

  # ── Feature 1: Colored status + TXT flag ─────────────────
  if [ "$WRONG_COUNT" -gt 0 ]; then
    ((REPOS_WITH_ISSUES++))
    fail "$WRONG_COUNT commit(s) with wrong email"
    echo "❌ WARNING: $WRONG_COUNT commits with wrong email" >> "$REPORT_TXT"
    STATUS="ISSUES"
  else
    ok "All commits valid"
    echo "✅ All commits valid" >> "$REPORT_TXT"
    STATUS="CLEAN"
  fi

  # ── Feature 6: Per-repo UTC scan (runs in subshell, no cd) ──
  (cd "$repo_dir" && utc_scan_repo)

  # Git status in TXT
  {
    echo ""
    echo "Git Status:"
    git -C "$repo_dir" status -sb 2>/dev/null
    echo ""
    echo "-----------------------------"
    echo ""
  } >> "$REPORT_TXT"

  # ── Feature 2: JSON email distribution ───────────────────
  EMAIL_DIST_JSON="[]"
  while IFS= read -r dist_line; do
    cnt=$(echo "$dist_line" | awk '{print $1}')
    em=$(echo  "$dist_line" | awk '{$1=""; print $0}' | xargs)
    em_json=$(json_str "$em")
    obj="{\"email\":${em_json},\"count\":${cnt}}"
    EMAIL_DIST_JSON=$(json_append "$EMAIL_DIST_JSON" "$obj")
  done < <(git -C "$repo_dir" log --pretty=format:"%ae" 2>/dev/null | sort | uniq -c | sort -rn)

  report_repo_start "$rname" "$REMOTE_URL" "$BRANCH"
  report_repo_set STATUS "$STATUS"
  report_repo_set TOTAL  "$COMMIT_COUNT"
  report_repo_set WRONG  "$WRONG_COUNT"
  report_repo_set EMAILS "$EMAIL_DIST_JSON"
  report_repo_commit

  # ── Feature 3: GitHub repo API check ─────────────────────
  REPO_SLUG=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[/:]([^/]+/[^/.]+)(\.git)?$|\1|')
  REPO_NAME_ONLY=$(echo "$REPO_SLUG" | cut -d'/' -f2)
  [ -n "$REPO_NAME_ONLY" ] && github_check_repo "$GITHUB_USERNAME" "$REPO_NAME_ONLY"

done

# ── Final summary: TXT ───────────────────────────────────────
{
  echo ""
  echo "=================================================="
  echo "SUMMARY"
  echo "=================================================="
  echo "Repos Scanned        : $TOTAL_REPOS"
  echo "Repos With Issues    : $REPOS_WITH_ISSUES"
  echo "Clean Repos          : $((TOTAL_REPOS - REPOS_WITH_ISSUES))"
  echo "Total Commits Scanned: $TOTAL_COMMITS"
  echo "Wrong Commits Found  : $TOTAL_WRONG_COMMITS"
} >> "$REPORT_TXT"

section "SUMMARY"
echo -e "  Repos Scanned         : ${BOLD}$TOTAL_REPOS${RESET}"
echo -e "  ${RED}Repos With Issues  : $REPOS_WITH_ISSUES${RESET}"
echo -e "  ${GREEN}Clean Repos        : $((TOTAL_REPOS - REPOS_WITH_ISSUES))${RESET}"
echo -e "  Total Commits Scanned : $TOTAL_COMMITS"
echo -e "  ${RED}Wrong Commits Found: $TOTAL_WRONG_COMMITS${RESET}"

# ── Feature 2: JSON summary ──────────────────────────────────
report_set_summary "$TOTAL_REPOS" "$REPOS_WITH_ISSUES" \
  "$((TOTAL_REPOS - REPOS_WITH_ISSUES))" "$TOTAL_COMMITS" "$TOTAL_WRONG_COMMITS"
report_finalize

echo ""

# ── Feature 4: Contribution prediction ───────────────────────
predict_contributions "$BASE_PATH" "$CORRECT_EMAIL" 30

echo ""