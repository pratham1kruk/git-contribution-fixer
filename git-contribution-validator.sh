#!/bin/bash

# ============================================================
#   git-contribution-validator.sh  v2.0
#   Full GitHub Contribution & Streak Diagnostics Tool
#   Supports: single repo OR parent folder with multiple repos
#   Part of: git-identity-fixer toolkit
# ============================================================

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
pass()    { echo -e "  ${GREEN}✅ PASS${RESET}  $1"; ((R_PASS++)); ((G_PASS++)); }
warn()    { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $1"; ((R_WARN++)); ((G_WARN++)); }
fail()    { echo -e "  ${RED}❌ FAIL${RESET}  $1"; ((R_FAIL++)); ((G_FAIL++)); }
info()    { echo -e "  ${CYAN}ℹ️  INFO${RESET}  $1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────────────────${RESET}"; }
log()     { echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"; }

# ════════════════════════════════════════════════════════════
# VALIDATE A SINGLE REPO
# ════════════════════════════════════════════════════════════
validate_repo() {
  local REPO_PATH="$1"
  local REPO_NAME
  REPO_NAME=$(basename "$REPO_PATH")

  # Per-repo counters
  R_PASS=0; R_WARN=0; R_FAIL=0

  cd "$REPO_PATH" || return

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║  Repo: ${RESET}${BOLD}$REPO_NAME${RESET}"
  echo -e "${BOLD}${CYAN}║  Path: ${RESET}${DIM}$REPO_PATH${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"

  {
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  REPO: $REPO_NAME"
    echo "  PATH: $REPO_PATH"
    echo "════════════════════════════════════════════════════════"
  } >> "$OUTPUT_FILE"

  # ── 1. IDENTITY CHECKS ──────────────────────────────────
  section "1. IDENTITY CHECKS"
  log "── 1. IDENTITY CHECKS ──"

  GLOBAL_NAME=$(git config --global user.name 2>/dev/null)
  if [ -n "$GLOBAL_NAME" ]; then
    pass "Global git username: ${BOLD}$GLOBAL_NAME${RESET}"
    log "PASS  Global username: $GLOBAL_NAME"
  else
    fail "Global git username NOT set  →  git config --global user.name \"Your Name\""
    log "FAIL  Global username not set"
  fi

  GLOBAL_EMAIL=$(git config --global user.email 2>/dev/null)
  if [ "$GLOBAL_EMAIL" = "$CORRECT_EMAIL" ]; then
    pass "Global git email matches GitHub: ${BOLD}$GLOBAL_EMAIL${RESET}"
    log "PASS  Global email: $GLOBAL_EMAIL"
  else
    fail "Global email mismatch  →  found: '${GLOBAL_EMAIL:-not set}'  expected: '$CORRECT_EMAIL'"
    log "FAIL  Global email: found=$GLOBAL_EMAIL expected=$CORRECT_EMAIL"
  fi

  LOCAL_NAME=$(git config user.name 2>/dev/null)
  if [ -n "$LOCAL_NAME" ]; then
    info "Local repo username: ${BOLD}$LOCAL_NAME${RESET}"
    log "INFO  Local username: $LOCAL_NAME"
  else
    warn "Local repo username not set (inheriting global)"
    log "WARN  Local username not set"
  fi

  LOCAL_EMAIL=$(git config user.email 2>/dev/null)
  if [ -z "$LOCAL_EMAIL" ]; then
    info "Local repo email not set (inheriting global: $GLOBAL_EMAIL)"
    log "INFO  Local email: inheriting global"
  elif [ "$LOCAL_EMAIL" = "$CORRECT_EMAIL" ]; then
    pass "Local repo email matches GitHub: ${BOLD}$LOCAL_EMAIL${RESET}"
    log "PASS  Local email: $LOCAL_EMAIL"
  else
    fail "Local repo email mismatch  →  found: '$LOCAL_EMAIL'  expected: '$CORRECT_EMAIL'"
    log "FAIL  Local email: $LOCAL_EMAIL"
  fi

  # ── 2. COMMIT IDENTITY CHECKS ───────────────────────────
  section "2. COMMIT IDENTITY CHECKS"
  log ""; log "── 2. COMMIT IDENTITY CHECKS ──"

  echo -e "\n  ${DIM}Commit email distribution:${RESET}"
  EMAIL_DIST=$(git log --pretty=format:"%ae" 2>/dev/null | sort | uniq -c | sort -rn)
  echo "$EMAIL_DIST" | while read -r line; do echo -e "    $line"; done
  log "Email distribution:"; echo "$EMAIL_DIST" >> "$OUTPUT_FILE"

  # Email check — respect OLD_EMAIL mode vs fix-all mode
  if [ -n "$OLD_EMAIL" ]; then
    # Targeted: only flag commits matching OLD_EMAIL
    WRONG_EMAIL_COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -c "^$OLD_EMAIL$")
    if [ "$WRONG_EMAIL_COUNT" -eq 0 ]; then
      pass "No commits found with old email '$OLD_EMAIL'"
      log "PASS  No commits with old email: $OLD_EMAIL"
    else
      fail "$WRONG_EMAIL_COUNT commit(s) with old email '$OLD_EMAIL'  →  run fix_commits.sh"
      log "FAIL  $WRONG_EMAIL_COUNT commits with old email: $OLD_EMAIL"
    fi
  else
    # Fix-all: flag anything that isn't the correct email
    WRONG_EMAIL_COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cv "^$CORRECT_EMAIL$")
    if [ "$WRONG_EMAIL_COUNT" -eq 0 ]; then
      pass "All commits use the correct email"
      log "PASS  All commits use correct email"
    else
      fail "$WRONG_EMAIL_COUNT commit(s) with wrong email (any email ≠ '$CORRECT_EMAIL')  →  run fix_commits.sh"
      log "FAIL  $WRONG_EMAIL_COUNT commits with wrong email"
    fi
  fi

  echo -e "\n  ${DIM}Author name distribution:${RESET}"
  NAME_DIST=$(git log --pretty=format:"%an" 2>/dev/null | sort | uniq -c | sort -rn)
  echo "$NAME_DIST" | while read -r line; do echo -e "    $line"; done
  UNIQUE_NAMES=$(echo "$NAME_DIST" | grep -c .)
  if [ "$UNIQUE_NAMES" -gt 1 ]; then
    warn "Multiple author names detected ($UNIQUE_NAMES distinct names)"
    log "WARN  Multiple author names: $UNIQUE_NAMES"
  else
    pass "Single consistent author name"
    log "PASS  Author name consistent"
  fi

  echo -e "\n  ${DIM}Last 10 commit author map:${RESET}"
  git log --pretty=format:"%h | %an | %ae" -10 2>/dev/null | \
    while read -r line; do echo -e "    ${DIM}$line${RESET}"; done
  log "Last 10 commits (hash | name | email):"
  git log --pretty=format:"%h | %an | %ae" -10 >> "$OUTPUT_FILE" 2>/dev/null

  # ── 3. BRANCH VALIDATION ────────────────────────────────
  section "3. BRANCH VALIDATION"
  log ""; log "── 3. BRANCH VALIDATION ──"

  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$CURRENT_BRANCH" ]; then
    fail "Detached HEAD state  →  checkout a branch first"
    log "FAIL  Detached HEAD"
  elif [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    pass "On default branch: ${BOLD}$CURRENT_BRANCH${RESET}"
    log "PASS  Branch: $CURRENT_BRANCH"
  else
    warn "Not on main/master  →  current: '$CURRENT_BRANCH'"
    log "WARN  Branch: $CURRENT_BRANCH"
  fi

  echo -e "\n  ${DIM}Remote branches:${RESET}"
  git branch -r 2>/dev/null | while read -r b; do echo -e "    $b"; done
  log "Remote branches:"; git branch -r >> "$OUTPUT_FILE" 2>/dev/null

  DEFAULT_REMOTE_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
  if [ -n "$DEFAULT_REMOTE_BRANCH" ]; then
    info "Default remote branch: ${BOLD}$DEFAULT_REMOTE_BRANCH${RESET}"
    log "INFO  Default remote: $DEFAULT_REMOTE_BRANCH"
  else
    warn "Could not detect default remote branch"
    log "WARN  Default remote unknown"
  fi

  # ── 4. PUSH / SYNC VALIDATION ───────────────────────────
  section "4. PUSH / SYNC VALIDATION"
  log ""; log "── 4. PUSH / SYNC VALIDATION ──"

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  if [ -z "$REMOTE_URL" ]; then
    fail "No remote origin configured"
    log "FAIL  No remote origin"
  else
    info "Remote URL: ${BOLD}$REMOTE_URL${RESET}"
    log "INFO  Remote: $REMOTE_URL"

    if echo "$REMOTE_URL" | grep -q "$GITHUB_USERNAME"; then
      pass "Repo belongs to your GitHub account"
      log "PASS  Ownership confirmed"
    else
      warn "Remote URL doesn't contain '$GITHUB_USERNAME'  →  may be fork/org repo"
      log "WARN  Possible fork or org: $REMOTE_URL"
    fi

    if echo "$REMOTE_URL" | grep -qiE "fork|upstream"; then
      warn "Repo name suggests it may be a fork"
      log "WARN  Fork heuristic triggered"
    fi
  fi

  REMOTE_LATEST=$(git log "origin/${DEFAULT_REMOTE_BRANCH:-main}" -1 --pretty=format:"%h | %ae | %ad" --date=short 2>/dev/null)
  if [ -n "$REMOTE_LATEST" ]; then
    info "Remote HEAD: $REMOTE_LATEST"
    log "INFO  Remote latest: $REMOTE_LATEST"
  else
    warn "Could not fetch remote commit info (try: git fetch)"
    log "WARN  Remote commit info unavailable"
  fi

  LOCAL_LATEST=$(git log -1 --pretty=format:"%h | %ae | %ad" --date=short 2>/dev/null)
  info "Local HEAD:  $LOCAL_LATEST"
  log "INFO  Local latest: $LOCAL_LATEST"

  SYNC_STATUS=$(git status -sb 2>/dev/null | head -1)
  if echo "$SYNC_STATUS" | grep -q "ahead"; then
    warn "Local is ahead of remote  →  unpushed commits won't appear on GitHub"
    log "WARN  Unpushed commits: $SYNC_STATUS"
  elif echo "$SYNC_STATUS" | grep -q "behind"; then
    warn "Local is behind remote  →  pull recommended"
    log "WARN  Behind remote: $SYNC_STATUS"
  else
    pass "Local and remote are in sync"
    log "PASS  In sync"
  fi

  # ── 5. TIME & CONTRIBUTION CHECKS ───────────────────────
  section "5. TIME & CONTRIBUTION CHECKS"
  log ""; log "── 5. TIME & CONTRIBUTION CHECKS ──"

  echo -e "\n  ${DIM}Last 5 commits — ISO timestamps:${RESET}"
  git log --pretty=format:"%h | %ad | %ae" --date=iso -5 2>/dev/null | \
    while read -r line; do echo -e "    $line"; done

  echo -e "\n  ${DIM}Last 5 commits — UTC timestamps:${RESET}"
  git log --pretty=format:"%h | %ad | %ae" --date=utc -5 2>/dev/null | \
    while read -r line; do echo -e "    $line"; done

  echo -e "\n  ${DIM}Relative commit times:${RESET}"
  git log --pretty=format:"%h | %ar | %ae" -5 2>/dev/null | \
    while read -r line; do echo -e "    $line"; done

  log "Last 5 commits (ISO):"
  git log --pretty=format:"%h | %ad | %ae" --date=iso -5 >> "$OUTPUT_FILE" 2>/dev/null

  info "Local: $(date '+%H:%M %Z')  |  UTC: $(date -u '+%H:%M UTC')"
  log "INFO  Time: $(date)  UTC: $(date -u)"

  UTC_HOUR=$(date -u +%H)
  if [ "$UTC_HOUR" -ge 22 ] || [ "$UTC_HOUR" -le 1 ]; then
    warn "Near UTC midnight  →  commits may be attributed to wrong day"
    log "WARN  Near UTC midnight"
  else
    pass "Commit time safely within UTC day boundary"
    log "PASS  UTC time safe"
  fi

  # ── 6. CONTRIBUTION STATS ───────────────────────────────
  section "6. CONTRIBUTION STATS"
  log ""; log "── 6. CONTRIBUTION STATS ──"

  echo -e "\n  ${DIM}Commits per day (last 14 days):${RESET}"
  git log --date=short --pretty=format:"%ad" --since="14 days ago" 2>/dev/null | \
    sort | uniq -c | \
    while read -r count day; do
      BAR=$(printf '█%.0s' $(seq 1 $((count > 20 ? 20 : count))))
      printf "    %s  %s %s\n" "$day" "$BAR" "$count"
    done

  log "Commits per day (last 14 days):"
  git log --date=short --pretty=format:"%ad" --since="14 days ago" 2>/dev/null | \
    sort | uniq -c >> "$OUTPUT_FILE"

  MAIN_BRANCH=${DEFAULT_REMOTE_BRANCH:-main}
  MAIN_COMMIT_COUNT=$(git log "$MAIN_BRANCH" --oneline 2>/dev/null | wc -l | tr -d ' ')
  info "Total commits on ${BOLD}$MAIN_BRANCH${RESET}: $MAIN_COMMIT_COUNT"
  log "INFO  Commits on $MAIN_BRANCH: $MAIN_COMMIT_COUNT"

  # ── 7. ADVANCED DIAGNOSTICS ─────────────────────────────
  section "7. ADVANCED DIAGNOSTICS"
  log ""; log "── 7. ADVANCED DIAGNOSTICS ──"

  REFLOG_COUNT=$(git reflog 2>/dev/null | wc -l | tr -d ' ')
  info "Reflog entries: $REFLOG_COUNT"
  if git reflog 2>/dev/null | grep -q "filter-branch\|rebase\|amend"; then
    warn "History rewrite detected in reflog (filter-branch/rebase/amend)"
    log "WARN  History rewrite in reflog"
  else
    pass "No history rewrites in reflog"
    log "PASS  Clean reflog"
  fi

  echo -e "\n  ${DIM}Running git fsck...${RESET}"
  FSK_RESULT=$(git fsck --no-progress 2>&1)
  if echo "$FSK_RESULT" | grep -qi "error\|corrupt\|missing"; then
    fail "Repo integrity issues found  →  run 'git fsck' for details"
    log "FAIL  git fsck errors"
  else
    pass "Repository integrity check passed"
    log "PASS  git fsck clean"
  fi

  HEAD_STATE=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$HEAD_STATE" ]; then
    fail "Detached HEAD  →  commits won't contribute to branch history"
    log "FAIL  Detached HEAD"
  else
    pass "HEAD attached to branch: ${BOLD}$HEAD_STATE${RESET}"
    log "PASS  HEAD: $HEAD_STATE"
  fi

  # ── Per-repo summary ─────────────────────────────────────
  local R_TOTAL=$((R_PASS + R_WARN + R_FAIL))
  echo -e "\n  ${DIM}────────────────────────────────────────────────${RESET}"
  echo -e "  ${BOLD}Repo result:${RESET}  ${GREEN}✅ $R_PASS${RESET}  ${YELLOW}⚠️  $R_WARN${RESET}  ${RED}❌ $R_FAIL${RESET}  (of $R_TOTAL checks)"

  {
    echo ""
    echo "Repo result: PASS=$R_PASS  WARN=$R_WARN  FAIL=$R_FAIL  TOTAL=$R_TOTAL"
    echo "────────────────────────────────────────────────────────"
  } >> "$OUTPUT_FILE"

  SUMMARY_TABLE+=("$(printf '%-35s  ✅ %-4s  ⚠️  %-4s  ❌ %-4s' "$REPO_NAME" "$R_PASS" "$R_WARN" "$R_FAIL")")

  cd "$BASE_PATH" || exit
}

# ════════════════════════════════════════════════════════════
# MAIN — INPUT & MODE DETECTION
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     git-contribution-validator  v2.0                 ║"
echo "║     Full GitHub Contribution Diagnostics             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

read -p "  Enter path (single repo OR parent folder with multiple repos): " INPUT_PATH
read -p "  Enter your correct GitHub email: " CORRECT_EMAIL
read -p "  Enter your GitHub username: " GITHUB_USERNAME

echo ""
echo -e "  ${DIM}Old email to check (leave blank to flag ALL emails ≠ correct one):${RESET}"
read -p "  Old email [Enter to skip]: " OLD_EMAIL

if [ -n "$OLD_EMAIL" ]; then
  echo -e "  ${CYAN}ℹ️  Mode: Targeted — flagging commits with old email: ${BOLD}$OLD_EMAIL${RESET}"
else
  echo -e "  ${CYAN}ℹ️  Mode: Fix-all — flagging any commit not using: ${BOLD}$CORRECT_EMAIL${RESET}"
fi

INPUT_PATH="${INPUT_PATH%/}"

# ── Detect single vs multi-repo ──────────────────────────────
if [ -d "$INPUT_PATH/.git" ]; then
  MODE="single"
  echo -e "\n  ${GREEN}Scan mode: Single repo${RESET}"
  REPOS=("$INPUT_PATH")
  BASE_PATH=$(dirname "$INPUT_PATH")
else
  REPOS=()
  while IFS= read -r -d '' dir; do
    REPOS+=("${dir%/.git}")
  done < <(find "$INPUT_PATH" -maxdepth 2 -name ".git" -type d -print0 2>/dev/null)

  if [ ${#REPOS[@]} -eq 0 ]; then
    echo -e "\n${RED}❌ ERROR: No Git repositories found at: $INPUT_PATH${RESET}"
    exit 1
  fi

  MODE="multi"
  BASE_PATH="$INPUT_PATH"
  echo -e "\n  ${GREEN}Scan mode: Multi-repo — found ${#REPOS[@]} repositories${RESET}"
  for r in "${REPOS[@]}"; do echo -e "    ${DIM}→ $(basename "$r")${RESET}"; done
fi

OUTPUT_FILE="$INPUT_PATH/contribution_report_$(date +%Y%m%d_%H%M%S).txt"

# Global counters
G_PASS=0; G_WARN=0; G_FAIL=0
SUMMARY_TABLE=()

{
  echo "git-contribution-validator Report  v2.0"
  echo "Generated  : $(date)"
  echo "Path       : $INPUT_PATH"
  echo "Mode       : $MODE"
  echo "Email      : $CORRECT_EMAIL"
  echo "Username   : $GITHUB_USERNAME"
  if [ -n "$OLD_EMAIL" ]; then
    echo "Old Email  : $OLD_EMAIL  (targeted check)"
  else
    echo "Old Email  : (not set — flagging all non-matching emails)"
  fi
  echo "Repos      : ${#REPOS[@]}"
  echo "=================================================="
} > "$OUTPUT_FILE"

# ── Run checks on each repo ──────────────────────────────────
REPO_COUNT=${#REPOS[@]}
CURRENT_REPO=0

for REPO in "${REPOS[@]}"; do
  ((CURRENT_REPO++))
  echo -e "\n${DIM}[$CURRENT_REPO/$REPO_COUNT]${RESET}"
  validate_repo "$REPO"
done

# ════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════
echo -e "\n\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║              FINAL SUMMARY                           ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e "\n  ${DIM}Repos scanned: $REPO_COUNT${RESET}\n"

echo -e "  ${BOLD}Repo                                 Pass  Warn  Fail${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────────────────${RESET}"
for row in "${SUMMARY_TABLE[@]}"; do
  echo -e "  $row"
done

echo ""
echo -e "  ${BOLD}Overall totals:${RESET}"
echo -e "  ${GREEN}✅ Passed  : $G_PASS${RESET}"
echo -e "  ${YELLOW}⚠️  Warnings: $G_WARN${RESET}"
echo -e "  ${RED}❌ Failed  : $G_FAIL${RESET}"
echo ""

{
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "FINAL SUMMARY"
  echo "Repos scanned : $REPO_COUNT"
  echo "Total PASS    : $G_PASS"
  echo "Total WARN    : $G_WARN"
  echo "Total FAIL    : $G_FAIL"
  echo ""
  echo "Per-repo breakdown:"
  for row in "${SUMMARY_TABLE[@]}"; do echo "  $row"; done
} >> "$OUTPUT_FILE"

if [ "$G_FAIL" -eq 0 ] && [ "$G_WARN" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}🎉 All repos passed! Everything is contribution-ready.${RESET}"
  log "RESULT: All checks passed"
elif [ "$G_FAIL" -eq 0 ]; then
  echo -e "  ${YELLOW}${BOLD}🟡 No failures — review warnings above.${RESET}"
  log "RESULT: Warnings only"
else
  echo -e "  ${RED}${BOLD}🚨 Issues found. Fix failures so your commits count on GitHub.${RESET}"
  echo -e "\n  ${DIM}Suggested fixes:${RESET}"
  echo -e "    → Run ${BOLD}fix_commits.sh${RESET} to correct commit email history"
  echo -e "    → Run ${BOLD}audit_report.sh${RESET} for a full multi-repo email scan"
  log "RESULT: Failures detected"
fi

echo ""
echo -e "  📄 Full report saved to: ${BOLD}$OUTPUT_FILE${RESET}"
echo ""