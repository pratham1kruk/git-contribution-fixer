#!/bin/bash

# ============================================================
#   fix_commits.sh  v3.0
#   Git Commit Email Fix Tool — multi-repo
#   Uses git-filter-repo (modern replacement for filter-branch)
#   Part of: git-identity-fixer toolkit
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║         fix_commits.sh  v3.0                         ║"
echo "║         Git Commit Email Fix Tool                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Check git-filter-repo ────────────────────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  echo -e "${RED}❌ git-filter-repo not found.${RESET}"
  echo -e "   Install it first:"
  echo -e "   ${DIM}sudo apt install git-filter-repo${RESET}"
  exit 1
fi

# ── Inputs ───────────────────────────────────────────────────
read -p "  Enter base directory path (e.g. /mnt/d/git): " BASE_PATH
read -p "  Enter your GitHub username: " GITHUB_USERNAME
read -p "  Enter correct GitHub email: " CORRECT_EMAIL
read -p "  Enter your correct name: " CORRECT_NAME

echo ""
echo -e "  ${DIM}Old email to replace (leave blank to fix ALL emails → correct one):${RESET}"
read -p "  Old email [Enter to fix all]: " OLD_EMAIL

if [ -n "$OLD_EMAIL" ]; then
  echo -e "  ${CYAN}ℹ️  Mode: Targeted — replacing only: ${BOLD}$OLD_EMAIL${RESET}"
else
  echo -e "  ${CYAN}ℹ️  Mode: Fix-all — replacing every email that isn't: ${BOLD}$CORRECT_EMAIL${RESET}"
fi

# ── Dry Run ──────────────────────────────────────────────────
echo ""
read -p "  Dry run first? Shows what would change without modifying anything (y/n): " DRY_RUN_CHOICE

if [ "$DRY_RUN_CHOICE" = "y" ]; then
  DRY_RUN=true
  echo -e "  ${YELLOW}⚠️  Dry-run mode enabled — no changes will be made${RESET}"
else
  DRY_RUN=false
fi

BASE_PATH="${BASE_PATH%/}"

# ── Report File ──────────────────────────────────────────────
REPORT_FILE="$BASE_PATH/fix_commits_report_$(date +%Y%m%d_%H%M%S).txt"

{
  echo "fix_commits Report v3.0"
  echo "Generated : $(date)"
  echo "Base Path : $BASE_PATH"
  echo "GitHub User : $GITHUB_USERNAME"
  echo "Correct Email : $CORRECT_EMAIL"
  echo "Correct Name  : $CORRECT_NAME"
  echo "Dry Run : $DRY_RUN"
  echo "=================================================="
  echo ""
} > "$REPORT_FILE"

# ── Enforce Global Git Config ────────────────────────────────
CURRENT_GLOBAL_EMAIL=$(git config --global user.email 2>/dev/null)

if [ "$CURRENT_GLOBAL_EMAIL" != "$CORRECT_EMAIL" ]; then

  echo -e "\n${YELLOW}⚠️  Global git email mismatch${RESET}"
  echo -e "  Current : ${DIM}${CURRENT_GLOBAL_EMAIL:-not set}${RESET}"
  echo -e "  Expected: ${DIM}$CORRECT_EMAIL${RESET}"

  read -p "  Update global Git config now? (y/n): " choice

  if [ "$choice" = "y" ]; then
    git config --global user.email "$CORRECT_EMAIL"
    git config --global user.name "$CORRECT_NAME"

    echo -e "  ${GREEN}✅ Global Git config updated${RESET}"

    {
      echo "Global Git Config Updated"
      echo "New user.name  : $CORRECT_NAME"
      echo "New user.email : $CORRECT_EMAIL"
      echo ""
    } >> "$REPORT_FILE"

  else
    echo -e "  ${RED}❌ Aborted — fix global config first${RESET}"
    exit 1
  fi
fi

cd "$BASE_PATH" || exit 1

FIXED=0
CLEAN=0
SKIPPED=0
FAILED=0
TOTAL_COMMITS_FIXED=0

# ════════════════════════════════════════════════════════════
# PROCESS REPOS
# ════════════════════════════════════════════════════════════

for repo in */; do

  repo="${repo%/}"

  if [ ! -d "$repo/.git" ]; then
    continue
  fi

  echo -e "\n${CYAN}🔍 $repo${RESET}"

  cd "$repo" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)

  {
    echo "Repo : $repo"
    echo "Remote : $REMOTE_URL"
    echo "Branch : $(git branch --show-current)"
  } >> "../$(basename "$REPORT_FILE")"

  # ── Skip non-user repos ───────────────────────────────────
  if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then

    echo -e "  ${DIM}⏭️  Skipping — not owned by user${RESET}"

    {
      echo "STATUS : SKIPPED"
      echo "Reason : Remote does not match username"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    ((SKIPPED++))
    cd ..
    continue
  fi

  # ── Count commits needing fixes ───────────────────────────
  if [ -n "$OLD_EMAIL" ]; then
    COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cxF "$OLD_EMAIL")
  else
    COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cvxF "$CORRECT_EMAIL")
  fi

  TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null)

  {
    echo "Total Commits : $TOTAL_COMMITS"
    echo "Commits To Fix: $COUNT"
    echo ""
    echo "Email Distribution:"
    git log --pretty=format:"%ae" 2>/dev/null | sort | uniq -c
    echo ""
  } >> "../$(basename "$REPORT_FILE")"

  # ── Clean Repo ────────────────────────────────────────────
  if [ "$COUNT" -eq 0 ]; then

    echo -e "  ${GREEN}✅ No issues found${RESET}"

    {
      echo "STATUS : CLEAN"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    ((CLEAN++))
    cd ..
    continue
  fi

  echo -e "  ${YELLOW}⚠️  $COUNT commit(s) need fixing${RESET}"

  ((TOTAL_COMMITS_FIXED += COUNT))

  # ── Preview affected commits ──────────────────────────────
  echo -e "  ${DIM}Affected commits (up to 5):${RESET}"

  {
    echo "Affected Commits:"
  } >> "../$(basename "$REPORT_FILE")"

  if [ -n "$OLD_EMAIL" ]; then

    PREVIEW=$(git log --pretty=format:"%h | %an | %ae | %ad" --date=iso 2>/dev/null | grep "$OLD_EMAIL" | head -5)

  else

    PREVIEW=$(git log --pretty=format:"%h | %an | %ae | %ad" --date=iso 2>/dev/null | grep -v "$CORRECT_EMAIL" | head -5)

  fi

  echo "$PREVIEW"
  echo "$PREVIEW" >> "../$(basename "$REPORT_FILE")"

  # ── Dry Run ───────────────────────────────────────────────
  if [ "$DRY_RUN" = true ]; then

    echo -e "  ${YELLOW}[DRY RUN] Would rewrite $COUNT commit(s) and force-push${RESET}"

    {
      echo ""
      echo "STATUS : DRY RUN"
      echo "Action : Would rewrite and force-push"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    cd ..
    continue
  fi

  # ── Rewrite History ───────────────────────────────────────
  echo -e "  ${CYAN}🔧 Rewriting history...${RESET}"

  MAILMAP_FILE=$(mktemp)

  if [ -n "$OLD_EMAIL" ]; then

    echo "$CORRECT_NAME <$CORRECT_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"

  else

    git log --pretty=format:"%ae" 2>/dev/null | \
    grep -vxF "$CORRECT_EMAIL" | \
    sort -u | while read -r bad_email; do
      echo "$CORRECT_NAME <$CORRECT_EMAIL> <$bad_email>"
    done > "$MAILMAP_FILE"

  fi

  git filter-repo --mailmap "$MAILMAP_FILE" --force > /tmp/gitfix_output.txt 2>&1

  rm -f "$MAILMAP_FILE"

  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

  echo -e "  ${CYAN}🚀 Force pushing...${RESET}"

  if git push --force 2>&1; then

    echo -e "  ${GREEN}✅ Fixed & pushed: $repo${RESET}"

    {
      echo ""
      echo "STATUS : FIXED"
      echo "Action : History rewritten and pushed"
      echo "Commits Fixed : $COUNT"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    ((FIXED++))

  else

    echo -e "  ${RED}❌ Push failed${RESET}"

    {
      echo ""
      echo "STATUS : FAILED"
      echo "Reason : Push failed"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    ((FAILED++))
  fi

  cd ..

  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"

done

# ════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════

{
  echo ""
  echo "=================================================="
  echo "SUMMARY"
  echo "=================================================="
  echo "Repos Fixed           : $FIXED"
  echo "Repos Clean           : $CLEAN"
  echo "Repos Skipped         : $SKIPPED"
  echo "Repos Failed          : $FAILED"
  echo "Total Commits Fixed   : $TOTAL_COMMITS_FIXED"
  echo "Dry Run               : $DRY_RUN"
} >> "$REPORT_FILE"

echo ""
echo -e "${BOLD}🎉 Done!${RESET}"

echo -e "  ${GREEN}Fixed   : $FIXED${RESET}"
echo -e "  ${GREEN}Clean   : $CLEAN${RESET}"
echo -e "  ${DIM}Skipped : $SKIPPED${RESET}"
echo -e "  ${RED}Failed  : $FAILED${RESET}"

echo -e "  ${CYAN}Commits Fixed : $TOTAL_COMMITS_FIXED${RESET}"

if [ "$DRY_RUN" = true ]; then
  echo -e "\n  ${YELLOW}Dry run only — no changes were made.${RESET}"
fi

echo -e "\n  📄 Report saved to: ${BOLD}$REPORT_FILE${RESET}\n"