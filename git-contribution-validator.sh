#!/bin/bash

# ============================================================
#   git-contribution-validator.sh
#   Full GitHub Contribution & Streak Diagnostics Tool
#   Part of: git-identity-fixer toolkit
# ============================================================

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Counters ─────────────────────────────────────────────────
PASS=0
WARN=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────
pass()  { echo -e "  ${GREEN}✅ PASS${RESET}  $1"; ((PASS++)); }
warn()  { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $1"; ((WARN++)); }
fail()  { echo -e "  ${RED}❌ FAIL${RESET}  $1"; ((FAIL++)); }
info()  { echo -e "  ${CYAN}ℹ️  INFO${RESET}  $1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────────────────${RESET}"; }

# ── Inputs ───────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║       git-contribution-validator  v1.0               ║"
echo "║       Full GitHub Contribution Diagnostics           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

read -p "  Enter repo path to validate (e.g. /mnt/d/git/my-repo): " REPO_PATH
read -p "  Enter your correct GitHub email: " CORRECT_EMAIL
read -p "  Enter your GitHub username: " GITHUB_USERNAME

OUTPUT_FILE="contribution_report_$(date +%Y%m%d_%H%M%S).txt"

# ── Validate repo path ───────────────────────────────────────
if [ ! -d "$REPO_PATH/.git" ]; then
  echo -e "\n${RED}❌ ERROR: Not a valid Git repository: $REPO_PATH${RESET}"
  exit 1
fi

cd "$REPO_PATH" || exit 1
echo -e "\n${DIM}Scanning: $REPO_PATH${RESET}\n"

# ── Begin report ─────────────────────────────────────────────
{
  echo "git-contribution-validator Report"
  echo "Generated: $(date)"
  echo "Repo: $REPO_PATH"
  echo "Expected Email: $CORRECT_EMAIL"
  echo "GitHub Username: $GITHUB_USERNAME"
  echo "=================================================="
  echo ""
} > "$OUTPUT_FILE"

log() { echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"; }

# ════════════════════════════════════════════════════════════
section "1. IDENTITY CHECKS"
log "── 1. IDENTITY CHECKS ──"

# Check 1: Global username
GLOBAL_NAME=$(git config --global user.name 2>/dev/null)
if [ -n "$GLOBAL_NAME" ]; then
  pass "Global git username set: ${BOLD}$GLOBAL_NAME${RESET}"
  log "PASS  Global git username: $GLOBAL_NAME"
else
  fail "Global git username is NOT set  →  run: git config --global user.name \"Your Name\""
  log "FAIL  Global git username not set"
fi

# Check 2: Global email
GLOBAL_EMAIL=$(git config --global user.email 2>/dev/null)
if [ "$GLOBAL_EMAIL" = "$CORRECT_EMAIL" ]; then
  pass "Global git email matches GitHub: ${BOLD}$GLOBAL_EMAIL${RESET}"
  log "PASS  Global email: $GLOBAL_EMAIL"
else
  fail "Global git email mismatch  →  found: '${GLOBAL_EMAIL:-not set}'  expected: '$CORRECT_EMAIL'"
  log "FAIL  Global email mismatch: found=$GLOBAL_EMAIL expected=$CORRECT_EMAIL"
fi

# Check 3: Local repo username
LOCAL_NAME=$(git config user.name 2>/dev/null)
if [ -n "$LOCAL_NAME" ]; then
  info "Local repo username: ${BOLD}$LOCAL_NAME${RESET}"
  log "INFO  Local username: $LOCAL_NAME"
else
  warn "Local repo username not set (will inherit global)"
  log "WARN  Local username not set"
fi

# Check 4: Local repo email
LOCAL_EMAIL=$(git config user.email 2>/dev/null)
if [ -z "$LOCAL_EMAIL" ]; then
  info "Local repo email not set (inheriting global: $GLOBAL_EMAIL)"
  log "INFO  Local email not set, using global"
elif [ "$LOCAL_EMAIL" = "$CORRECT_EMAIL" ]; then
  pass "Local repo email matches GitHub: ${BOLD}$LOCAL_EMAIL${RESET}"
  log "PASS  Local email: $LOCAL_EMAIL"
else
  fail "Local repo email mismatch  →  found: '$LOCAL_EMAIL'  expected: '$CORRECT_EMAIL'"
  log "FAIL  Local email mismatch: $LOCAL_EMAIL"
fi

# ════════════════════════════════════════════════════════════
section "2. COMMIT IDENTITY CHECKS"
log ""
log "── 2. COMMIT IDENTITY CHECKS ──"

# Check 5: Email distribution
echo -e "\n  ${DIM}Commit email distribution:${RESET}"
EMAIL_DIST=$(git log --pretty=format:"%ae" 2>/dev/null | sort | uniq -c | sort -rn)
echo "$EMAIL_DIST" | while read -r line; do echo -e "    $line"; done
log "Email distribution:"
echo "$EMAIL_DIST" >> "$OUTPUT_FILE"

WRONG_EMAIL_COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cv "^$CORRECT_EMAIL$")
if [ "$WRONG_EMAIL_COUNT" -eq 0 ]; then
  pass "All commits use the correct email"
  log "PASS  All commits use correct email"
else
  fail "$WRONG_EMAIL_COUNT commit(s) found with wrong email  →  run fix_commits.sh to repair"
  log "FAIL  $WRONG_EMAIL_COUNT commits with wrong email"
fi

# Check 6: Author name distribution
echo -e "\n  ${DIM}Author name distribution:${RESET}"
NAME_DIST=$(git log --pretty=format:"%an" 2>/dev/null | sort | uniq -c | sort -rn)
echo "$NAME_DIST" | while read -r line; do echo -e "    $line"; done
UNIQUE_NAMES=$(echo "$NAME_DIST" | wc -l | tr -d ' ')
if [ "$UNIQUE_NAMES" -gt 1 ]; then
  warn "Multiple author names detected ($UNIQUE_NAMES distinct names)"
  log "WARN  Multiple author names: $UNIQUE_NAMES"
else
  pass "Single consistent author name across all commits"
  log "PASS  Author name consistent"
fi

# Check 7: Full author mapping (last 10 commits)
echo -e "\n  ${DIM}Last 10 commit author map:${RESET}"
git log --pretty=format:"%h | %an | %ae" -10 2>/dev/null | while read -r line; do
  echo -e "    ${DIM}$line${RESET}"
done
log "Last 10 commits (hash | name | email):"
git log --pretty=format:"%h | %an | %ae" -10 >> "$OUTPUT_FILE" 2>/dev/null

# ════════════════════════════════════════════════════════════
section "3. BRANCH VALIDATION"
log ""
log "── 3. BRANCH VALIDATION ──"

# Check 8: Current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$CURRENT_BRANCH" ]; then
  fail "Detached HEAD state detected  →  checkout a branch first"
  log "FAIL  Detached HEAD"
elif [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  pass "On default branch: ${BOLD}$CURRENT_BRANCH${RESET}"
  log "PASS  Branch: $CURRENT_BRANCH"
else
  warn "Not on main/master  →  current branch: '$CURRENT_BRANCH'  (GitHub only counts commits merged to default branch)"
  log "WARN  Branch: $CURRENT_BRANCH (not main/master)"
fi

# Check 9: Remote branches
echo -e "\n  ${DIM}Remote branches:${RESET}"
git branch -r 2>/dev/null | while read -r b; do echo -e "    $b"; done
log "Remote branches:"
git branch -r >> "$OUTPUT_FILE" 2>/dev/null

# Check 10: Default remote branch
DEFAULT_REMOTE_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
if [ -n "$DEFAULT_REMOTE_BRANCH" ]; then
  info "Default remote branch: ${BOLD}$DEFAULT_REMOTE_BRANCH${RESET}"
  log "INFO  Default remote branch: $DEFAULT_REMOTE_BRANCH"
else
  warn "Could not detect default remote branch"
  log "WARN  Default remote branch unknown"
fi

# ════════════════════════════════════════════════════════════
section "4. PUSH / SYNC VALIDATION"
log ""
log "── 4. PUSH / SYNC VALIDATION ──"

# Check 11: Remote URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [ -z "$REMOTE_URL" ]; then
  fail "No remote origin configured  →  GitHub won't track this repo's contributions"
  log "FAIL  No remote origin"
else
  info "Remote URL: ${BOLD}$REMOTE_URL${RESET}"
  log "INFO  Remote: $REMOTE_URL"

  # Check 21 (here for context): Repo ownership
  if echo "$REMOTE_URL" | grep -q "$GITHUB_USERNAME"; then
    pass "Repo belongs to your GitHub account"
    log "PASS  Repo ownership confirmed"
  else
    warn "Remote URL does not contain your username '$GITHUB_USERNAME'  →  may be a fork or org repo"
    log "WARN  Repo may not belong to user: $REMOTE_URL"
  fi

  # Fork detection (heuristic)
  if echo "$REMOTE_URL" | grep -qiE "fork|upstream"; then
    warn "Repo name suggests it may be a fork  →  contributions to forks may not count"
    log "WARN  Possible fork detected"
  fi
fi

# Check 12: Latest remote commit
echo -e "\n  ${DIM}Latest remote commit:${RESET}"
REMOTE_LATEST=$(git log "origin/${DEFAULT_REMOTE_BRANCH:-main}" -1 --pretty=format:"%h | %ae | %ad" --date=short 2>/dev/null)
if [ -n "$REMOTE_LATEST" ]; then
  info "Remote HEAD: $REMOTE_LATEST"
  log "INFO  Remote latest: $REMOTE_LATEST"
else
  warn "Could not fetch remote commit info (try: git fetch)"
  log "WARN  Remote commit info unavailable"
fi

# Check 13: Latest local commit
LOCAL_LATEST=$(git log -1 --pretty=format:"%h | %ae | %ad" --date=short 2>/dev/null)
info "Local HEAD:  $LOCAL_LATEST"
log "INFO  Local latest: $LOCAL_LATEST"

# Check 14: Sync status
SYNC_STATUS=$(git status -sb 2>/dev/null | head -1)
if echo "$SYNC_STATUS" | grep -q "ahead"; then
  warn "Local is ahead of remote  →  unpushed commits won't appear on GitHub"
  log "WARN  Unpushed commits: $SYNC_STATUS"
elif echo "$SYNC_STATUS" | grep -q "behind"; then
  warn "Local is behind remote  →  pull recommended"
  log "WARN  Behind remote: $SYNC_STATUS"
else
  pass "Local and remote are in sync"
  log "PASS  In sync with remote"
fi

# ════════════════════════════════════════════════════════════
section "5. TIME & CONTRIBUTION CHECKS"
log ""
log "── 5. TIME & CONTRIBUTION CHECKS ──"

# Check 15 & 16: ISO + UTC timestamps (last 5)
echo -e "\n  ${DIM}Last 5 commits — ISO timestamps:${RESET}"
git log --pretty=format:"%h | %ad | %ae" --date=iso -5 2>/dev/null | \
  while read -r line; do echo -e "    $line"; done

echo -e "\n  ${DIM}Last 5 commits — UTC timestamps:${RESET}"
git log --pretty=format:"%h | %ad | %ae" --date=utc -5 2>/dev/null | \
  while read -r line; do echo -e "    $line"; done

log "Last 5 commits (ISO):"
git log --pretty=format:"%h | %ad | %ae" --date=iso -5 >> "$OUTPUT_FILE" 2>/dev/null

# Check 17: Relative timestamps
echo -e "\n  ${DIM}Relative commit times:${RESET}"
git log --pretty=format:"%h | %ar | %ae" -5 2>/dev/null | \
  while read -r line; do echo -e "    $line"; done

# UTC boundary warning
UTC_HOUR=$(date -u +%H)
LOCAL_HOUR=$(date +%H)
info "Current time — Local: $(date '+%H:%M %Z')  |  UTC: $(date -u '+%H:%M UTC')"
log "INFO  Local time: $(date)  UTC: $(date -u)"

if [ "$UTC_HOUR" -ge 22 ] || [ "$UTC_HOUR" -le 1 ]; then
  warn "Commits made now are near UTC midnight  →  may be attributed to wrong day on GitHub"
  log "WARN  Near UTC midnight boundary"
else
  pass "Commit time is safely within UTC day boundary"
  log "PASS  UTC time safe"
fi

# ════════════════════════════════════════════════════════════
section "6. CONTRIBUTION STATS"
log ""
log "── 6. CONTRIBUTION STATS ──"

# Check 18: Commits per day
echo -e "\n  ${DIM}Commits per day:${RESET}"
git log --date=short --pretty=format:"%ad" 2>/dev/null | sort | uniq -c | tail -14 | \
  while read -r count day; do
    BAR=$(printf '█%.0s' $(seq 1 $((count > 20 ? 20 : count))))
    printf "    %s  %s %s\n" "$day" "$BAR" "$count"
  done

log "Commits per day (last 14 days):"
git log --date=short --pretty=format:"%ad" --since="14 days ago" | sort | uniq -c >> "$OUTPUT_FILE" 2>/dev/null

# Check 19: Commits on main/master
MAIN_BRANCH=${DEFAULT_REMOTE_BRANCH:-main}
MAIN_COMMIT_COUNT=$(git log "$MAIN_BRANCH" --oneline 2>/dev/null | wc -l | tr -d ' ')
info "Total commits on ${BOLD}$MAIN_BRANCH${RESET}: $MAIN_COMMIT_COUNT"
log "INFO  Commits on $MAIN_BRANCH: $MAIN_COMMIT_COUNT"

# ════════════════════════════════════════════════════════════
section "7. ADVANCED DIAGNOSTICS"
log ""
log "── 7. ADVANCED DIAGNOSTICS ──"

# Check 22: Rewritten history detection
REFLOG_COUNT=$(git reflog 2>/dev/null | wc -l | tr -d ' ')
info "Reflog entries: $REFLOG_COUNT"
if git reflog 2>/dev/null | grep -q "filter-branch\|rebase\|amend"; then
  warn "Rewritten history detected in reflog (filter-branch / rebase / amend)"
  log "WARN  History rewrite detected in reflog"
else
  pass "No history rewrites detected in reflog"
  log "PASS  Clean reflog"
fi

# Check 23: Repo integrity
echo -e "\n  ${DIM}Running git fsck (integrity check)...${RESET}"
FSK_RESULT=$(git fsck --no-progress 2>&1)
if echo "$FSK_RESULT" | grep -qi "error\|corrupt\|missing"; then
  fail "Repo integrity issues found  →  run 'git fsck' for details"
  log "FAIL  git fsck errors detected"
else
  pass "Repository integrity check passed"
  log "PASS  git fsck clean"
fi

# Check 24: Detached HEAD
HEAD_STATE=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$HEAD_STATE" ]; then
  fail "Detached HEAD state  →  commits in this state won't contribute to branch history"
  log "FAIL  Detached HEAD"
else
  pass "HEAD is attached to branch: ${BOLD}$HEAD_STATE${RESET}"
  log "PASS  HEAD attached: $HEAD_STATE"
fi

# ════════════════════════════════════════════════════════════
section "SUMMARY"

TOTAL=$((PASS + WARN + FAIL))

echo ""
echo -e "  ${GREEN}✅ Passed : $PASS${RESET}"
echo -e "  ${YELLOW}⚠️  Warnings: $WARN${RESET}"
echo -e "  ${RED}❌ Failed : $FAIL${RESET}"
echo -e "  ${DIM}────────────────${RESET}"
echo -e "  Total checks: $TOTAL"
echo ""

{
  echo ""
  echo "── SUMMARY ──"
  echo "PASS:     $PASS"
  echo "WARN:     $WARN"
  echo "FAIL:     $FAIL"
  echo "TOTAL:    $TOTAL"
} >> "$OUTPUT_FILE"

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}🎉 All checks passed! This repo is contribution-ready.${RESET}"
  log "RESULT: All checks passed"
elif [ "$FAIL" -eq 0 ]; then
  echo -e "  ${YELLOW}${BOLD}🟡 No failures, but review warnings above.${RESET}"
  log "RESULT: Warnings present"
else
  echo -e "  ${RED}${BOLD}🚨 Issues found. Fix failures before your commits will count on GitHub.${RESET}"
  echo -e "\n  ${DIM}Suggested fixes:${RESET}"
  [ "$FAIL" -gt 0 ] && echo -e "    → Run ${BOLD}fix_commits.sh${RESET} to correct commit email history"
  echo -e "    → Run ${BOLD}audit_report.sh${RESET} across all repos for a full picture"
  log "RESULT: Failures detected"
fi

echo ""
echo -e "  📄 Full report saved to: ${BOLD}$REPO_PATH/$OUTPUT_FILE${RESET}"
echo ""