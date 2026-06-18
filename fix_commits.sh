#!/bin/bash
# ============================================================
#   fix_commits.sh  v5.0
#   Git Commit Email Fix Tool — multi-repo
#   Features:
#   • Dry Run
#   • Detailed Report (TXT + JSON)              [Feature 2]
#   • Allowlist for valid extra emails/users
#   • Skip forked/cloned repos
#   • Uses git-filter-repo
#   • GitHub API repo verification              [Feature 3]
#   • Streak safety warning before rewriting    [Feature 5]
#   • Auto UTC analysis after fix               [Feature 6]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/report.sh"
source "$SCRIPT_DIR/github_api.sh"
source "$SCRIPT_DIR/streak.sh"
source "$SCRIPT_DIR/utc_analysis.sh"

header "fix_commits.sh  v5.0" "Git Commit Email Fix Tool"

# ── Check git-filter-repo ─────────────────────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  fail "git-filter-repo not found."
  echo -e "   Install using:"
  echo -e "   ${DIM}sudo apt install git-filter-repo${RESET}"
  exit 1
fi

# ── Inputs ────────────────────────────────────────────────────
read -rp "  Enter base directory path: "        BASE_PATH
read -rp "  Enter your GitHub username: "       GITHUB_USERNAME
read -rp "  Enter correct GitHub email: "       CORRECT_EMAIL
read -rp "  Enter correct Git author name: "    CORRECT_NAME

echo ""
echo -e "  ${DIM}Old email to replace (leave blank to fix ALL emails):${RESET}"
read -rp "  Old email: " OLD_EMAIL

# ── GitHub API ────────────────────────────────────────────────
section "GITHUB API VERIFICATION"
github_prompt_token
github_verify_email "$CORRECT_EMAIL" "$GITHUB_USERNAME"
github_rate_limit

# ── Allowlist ─────────────────────────────────────────────────
echo ""
read -rp "  Add trusted emails/users to allowlist? (y/n): " ADD_ALLOW

ALLOWLIST_EMAILS=()
ALLOWLIST_NAMES=()

if [ "$ADD_ALLOW" = "y" ]; then
  echo -e "\n  ${CYAN}Enter trusted identities.${RESET}"
  while true; do
    read -rp "  Trusted author name (blank to stop): " TMP_NAME
    [ -z "$TMP_NAME" ] && break
    read -rp "  Trusted email: " TMP_EMAIL
    ALLOWLIST_NAMES+=("$TMP_NAME")
    ALLOWLIST_EMAILS+=("$TMP_EMAIL")
    ok "Added to allowlist"
  done
fi

# ── Options ───────────────────────────────────────────────────
echo ""
read -rp "  Skip forked/cloned repos not owned by you? (y/n): " SKIP_FOREIGN
echo ""
read -rp "  Dry run first? (y/n): " DRY_RUN_INPUT

if [ "$DRY_RUN_INPUT" = "y" ]; then
  DRY_RUN=true
  warn "Dry-run mode enabled — no changes will be made"
else
  DRY_RUN=false
fi

BASE_PATH="${BASE_PATH%/}"

# ── Feature 5: Streak safety before destructive ops ──────────
streak_safety_check "$BASE_PATH" "$CORRECT_EMAIL"
echo ""
read -rp "  Proceed with fix? (y/n): " PROCEED
[ "$PROCEED" != "y" ] && { echo "Aborted."; exit 0; }

# ── Feature 2: Init dual report ──────────────────────────────
report_init "fix_commits" "$BASE_PATH"

{
  echo "fix_commits Report  v5.0"
  echo "Generated       : $(date)"
  echo "Base Path       : $BASE_PATH"
  echo "GitHub Username : $GITHUB_USERNAME"
  echo "Correct Email   : $CORRECT_EMAIL"
  echo "Correct Name    : $CORRECT_NAME"
  echo "Dry Run         : $DRY_RUN"
  echo ""
  echo "Trusted Allowlist:"
  for i in "${!ALLOWLIST_EMAILS[@]}"; do
    echo "  ${ALLOWLIST_NAMES[$i]} <${ALLOWLIST_EMAILS[$i]}>"
  done
  echo ""
  echo "=================================================="
  echo ""
} >> "$REPORT_TXT"

# ── Check global Git config ───────────────────────────────────
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null)
if [ "$CURRENT_EMAIL" != "$CORRECT_EMAIL" ]; then
  warn "Global Git email mismatch"
  echo -e "  Current : ${CURRENT_EMAIL:-not set}"
  echo -e "  Expected: $CORRECT_EMAIL"
  read -rp "  Update global Git config? (y/n): " UPDATE_GLOBAL
  if [ "$UPDATE_GLOBAL" = "y" ]; then
    git config --global user.email "$CORRECT_EMAIL"
    git config --global user.name  "$CORRECT_NAME"
    ok "Global Git config updated"
  else
    fail "Aborted — global config not updated"
    exit 1
  fi
fi

cd "$BASE_PATH" || exit 1

FIXED=0; CLEAN=0; SKIPPED=0; FAILED=0; TOTAL_COMMITS_FIXED=0

# ════════════════════════════════════════════════════════════
# PROCESS REPOS
# ════════════════════════════════════════════════════════════
for repo in */; do
  repo="${repo%/}"
  [ ! -d "$repo/.git" ] && continue

  echo ""
  step "$repo"

  cd "$repo" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  CURRENT_BRANCH=$(git branch --show-current)

  rtxt "Repo   : $repo"
  rtxt "Remote : $REMOTE_URL"
  rtxt "Branch : $CURRENT_BRANCH"

  report_repo_start "$repo" "$REMOTE_URL" "$CURRENT_BRANCH"

  # ── Feature 3: API check per repo ────────────────────────
  REPO_SLUG=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[/:]([^/]+/[^/.]+)(\.git)?$|\1|')
  REPO_ONLY=$(echo "$REPO_SLUG" | cut -d'/' -f2)
  [ -n "$REPO_ONLY" ] && github_check_repo "$GITHUB_USERNAME" "$REPO_ONLY"

  # ── Skip foreign repos ────────────────────────────────────
  if [ "$SKIP_FOREIGN" = "y" ] && [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then
    info "Skipped (not owned by $GITHUB_USERNAME)"
    rtxt "STATUS : SKIPPED (foreign repo)"
    rtxt "--------------------------------------------------"
    rtxt ""
    report_repo_set STATUS "SKIPPED"
    report_repo_commit
    ((SKIPPED++))
    cd ..
    continue
  fi

  # ── Count invalid commits ─────────────────────────────────
  TEMP_ALLOWED=$(mktemp)
  echo "$CORRECT_EMAIL" >> "$TEMP_ALLOWED"
  for em in "${ALLOWLIST_EMAILS[@]}"; do echo "$em" >> "$TEMP_ALLOWED"; done

  if [ -n "$OLD_EMAIL" ]; then
    COUNT=$(git log --pretty=format:"%ae" | grep -cxF "$OLD_EMAIL")
  else
    COUNT=0
    while read -r email; do
      grep -qxF "$email" "$TEMP_ALLOWED" || ((COUNT++))
    done < <(git log --pretty=format:"%ae")
  fi

  TOTAL_C=$(git rev-list --count HEAD)

  EMAIL_DIST_JSON="[]"
  while IFS= read -r line; do
    cnt=$(echo "$line" | awk '{print $1}')
    em=$(echo  "$line" | awk '{$1=""; print $0}' | xargs)
    em_json=$(json_str "$em"); obj="{\"email\":${em_json},\"count\":${cnt}}"
    EMAIL_DIST_JSON=$(json_append "$EMAIL_DIST_JSON" "$obj")
  done < <(git log --pretty=format:"%ae" | sort | uniq -c | sort -rn)

  rtxt "Total Commits  : $TOTAL_C"
  rtxt "Commits to Fix : $COUNT"
  rtxt "Email Distribution:"
  git log --pretty=format:"%ae" | sort | uniq -c >> "$REPORT_TXT"

  report_repo_set TOTAL  "$TOTAL_C"
  report_repo_set WRONG  "$COUNT"
  report_repo_set EMAILS "$EMAIL_DIST_JSON"

  if [ "$COUNT" -eq 0 ]; then
    ok "No issues found"
    rtxt "STATUS : CLEAN"
    rtxt "--------------------------------------------------"
    rtxt ""
    report_repo_set STATUS "CLEAN"
    report_repo_commit
    ((CLEAN++))
    rm -f "$TEMP_ALLOWED"
    cd ..
    continue
  fi

  warn "$COUNT commit(s) need fixing"
  ((TOTAL_COMMITS_FIXED += COUNT))

  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}[DRY RUN] Would rewrite $COUNT commit(s) and force-push${RESET}"
    rtxt "STATUS : DRY RUN"
    report_repo_set STATUS "DRY_RUN"
    report_repo_commit
    rm -f "$TEMP_ALLOWED"
    cd ..
    continue
  fi

  # ── Rewrite history ───────────────────────────────────────
  info "Rewriting history..."

  MAILMAP_FILE=$(mktemp)
  if [ -n "$OLD_EMAIL" ]; then
    echo "$CORRECT_NAME <$CORRECT_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"
  else
    git log --pretty=format:"%ae" | sort -u | while read -r bad_email; do
      grep -qxF "$bad_email" "$TEMP_ALLOWED" || \
        echo "$CORRECT_NAME <$CORRECT_EMAIL> <$bad_email>"
    done > "$MAILMAP_FILE"
  fi

  git filter-repo --mailmap "$MAILMAP_FILE" --force > /tmp/gitfix_output.txt 2>&1
  rm -f "$MAILMAP_FILE" "$TEMP_ALLOWED"

  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

  info "Force pushing..."
  if git push --force 2>&1; then
    ok "Fixed & pushed"
    rtxt "STATUS : FIXED ($COUNT commits rewritten)"
    report_repo_set STATUS "FIXED"
    ((FIXED++))
  else
    fail "Push failed"
    rtxt "STATUS : PUSH FAILED"
    report_repo_set STATUS "PUSH_FAILED"
    ((FAILED++))
  fi

  report_repo_commit
  rtxt "--------------------------------------------------"
  rtxt ""
  cd ..
  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
done

# ── Final summary ─────────────────────────────────────────────
section "SUMMARY"
echo -e "  ${GREEN}Fixed   : $FIXED${RESET}"
echo -e "  ${GREEN}Clean   : $CLEAN${RESET}"
echo -e "  ${DIM}Skipped : $SKIPPED${RESET}"
echo -e "  ${RED}Failed  : $FAILED${RESET}"
echo -e "  ${CYAN}Commits Fixed : $TOTAL_COMMITS_FIXED${RESET}"
[ "$DRY_RUN" = true ] && warn "Dry run only — no changes made."

{
  echo ""
  echo "=================================================="
  echo "SUMMARY"
  echo "=================================================="
  echo "Repos Fixed         : $FIXED"
  echo "Repos Clean         : $CLEAN"
  echo "Repos Skipped       : $SKIPPED"
  echo "Repos Failed        : $FAILED"
  echo "Total Commits Fixed : $TOTAL_COMMITS_FIXED"
  echo "Dry Run             : $DRY_RUN"
} >> "$REPORT_TXT"

report_set_summary "$((FIXED+CLEAN+SKIPPED+FAILED))" "$FAILED" "$CLEAN" "$TOTAL_COMMITS_FIXED" "0"
report_finalize

# ── Feature 6: Post-fix UTC analysis ─────────────────────────
if [ "$FIXED" -gt 0 ] && [ "$DRY_RUN" = false ]; then
  echo ""
  auto_utc_analysis "$BASE_PATH" "$CORRECT_EMAIL"
fi

echo ""
