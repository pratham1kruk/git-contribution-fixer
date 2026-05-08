#!/bin/bash

# ============================================================
#   fix_commits.sh  v4.0
#   Git Commit Email Fix Tool — multi-repo
#   Features:
#   • Dry Run
#   • Detailed Report
#   • Allowlist for valid extra emails/users
#   • Skip forked/cloned repos
#   • Uses git-filter-repo
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
echo "║         fix_commits.sh  v4.0                         ║"
echo "║         Git Commit Email Fix Tool                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Check git-filter-repo ────────────────────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  echo -e "${RED}❌ git-filter-repo not found.${RESET}"
  echo -e "   Install using:"
  echo -e "   ${DIM}sudo apt install git-filter-repo${RESET}"
  exit 1
fi

# ── Inputs ───────────────────────────────────────────────────
read -p "  Enter base directory path: " BASE_PATH
read -p "  Enter your GitHub username: " GITHUB_USERNAME
read -p "  Enter correct GitHub email: " CORRECT_EMAIL
read -p "  Enter correct Git author name: " CORRECT_NAME

echo ""
echo -e "  ${DIM}Old email to replace (leave blank to fix ALL emails):${RESET}"
read -p "  Old email: " OLD_EMAIL

# ── Allowlist Feature ────────────────────────────────────────
echo ""
read -p "  Add trusted emails/users to allowlist? (y/n): " ADD_ALLOW

ALLOWLIST_EMAILS=()
ALLOWLIST_NAMES=()

if [ "$ADD_ALLOW" = "y" ]; then

  echo ""
  echo -e "  ${CYAN}Enter trusted identities.${RESET}"
  echo -e "  ${DIM}Example:${RESET}"
  echo "    Ubuntu"
  echo "    ubuntu@ip-172-31-21-116.eu-north-1.compute.internal"
  echo ""

  while true; do

    read -p "  Trusted author name (leave blank to stop): " TMP_NAME

    if [ -z "$TMP_NAME" ]; then
      break
    fi

    read -p "  Trusted email: " TMP_EMAIL

    ALLOWLIST_NAMES+=("$TMP_NAME")
    ALLOWLIST_EMAILS+=("$TMP_EMAIL")

    echo -e "  ${GREEN}✅ Added to allowlist${RESET}"
    echo ""
  done
fi

# ── Skip Fork/Cloned Repo Option ─────────────────────────────
echo ""
read -p "  Skip forked/cloned repos not owned by you? (y/n): " SKIP_FOREIGN

# ── Dry Run ──────────────────────────────────────────────────
echo ""
read -p "  Dry run first? (y/n): " DRY_RUN_INPUT

if [ "$DRY_RUN_INPUT" = "y" ]; then
  DRY_RUN=true
  echo -e "  ${YELLOW}⚠️ Dry-run mode enabled${RESET}"
else
  DRY_RUN=false
fi

BASE_PATH="${BASE_PATH%/}"

REPORT_FILE="$BASE_PATH/fix_commits_report_$(date +%Y%m%d_%H%M%S).txt"

{
  echo "fix_commits Report v4.0"
  echo "Generated : $(date)"
  echo "Base Path : $BASE_PATH"
  echo "GitHub Username : $GITHUB_USERNAME"
  echo "Correct Email : $CORRECT_EMAIL"
  echo "Correct Name  : $CORRECT_NAME"
  echo "Dry Run : $DRY_RUN"
  echo ""

  echo "Trusted Allowlist:"
  for i in "${!ALLOWLIST_EMAILS[@]}"; do
    echo "  ${ALLOWLIST_NAMES[$i]} <${ALLOWLIST_EMAILS[$i]}>"
  done

  echo ""
  echo "=================================================="
  echo ""
} > "$REPORT_FILE"

# ── Check Global Git Config ──────────────────────────────────
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null)

if [ "$CURRENT_EMAIL" != "$CORRECT_EMAIL" ]; then

  echo ""
  echo -e "${YELLOW}⚠️ Global Git email mismatch${RESET}"
  echo "Current : ${CURRENT_EMAIL:-not set}"
  echo "Expected: $CORRECT_EMAIL"

  read -p "Update global Git config? (y/n): " UPDATE_GLOBAL

  if [ "$UPDATE_GLOBAL" = "y" ]; then

    git config --global user.email "$CORRECT_EMAIL"
    git config --global user.name "$CORRECT_NAME"

    echo -e "${GREEN}✅ Global Git config updated${RESET}"

  else
    echo -e "${RED}❌ Aborted${RESET}"
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

  echo ""
  echo -e "${CYAN}🔍 $repo${RESET}"

  cd "$repo" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  CURRENT_BRANCH=$(git branch --show-current)

  {
    echo "Repo   : $repo"
    echo "Remote : $REMOTE_URL"
    echo "Branch : $CURRENT_BRANCH"
  } >> "../$(basename "$REPORT_FILE")"

  # ── Skip Foreign Repos ────────────────────────────────────
  if [ "$SKIP_FOREIGN" = "y" ]; then

    if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then

      echo -e "  ${DIM}⏭️ Skipped (not owned by user)${RESET}"

      {
        echo "STATUS : SKIPPED"
        echo "Reason : Foreign repo"
        echo "--------------------------------------------------"
        echo ""
      } >> "../$(basename "$REPORT_FILE")"

      ((SKIPPED++))
      cd ..
      continue
    fi
  fi

  # ── Create Temporary Email Ignore File ────────────────────
  TEMP_ALLOWED=$(mktemp)

  echo "$CORRECT_EMAIL" >> "$TEMP_ALLOWED"

  for email in "${ALLOWLIST_EMAILS[@]}"; do
    echo "$email" >> "$TEMP_ALLOWED"
  done

  # ── Count Invalid Commits ─────────────────────────────────
  if [ -n "$OLD_EMAIL" ]; then

    COUNT=$(git log --pretty=format:"%ae" | grep -cxF "$OLD_EMAIL")

  else

    COUNT=0

    while read -r email; do

      if ! grep -qxF "$email" "$TEMP_ALLOWED"; then
        ((COUNT++))
      fi

    done < <(git log --pretty=format:"%ae")
  fi

  TOTAL_COMMITS=$(git rev-list --count HEAD)

  {
    echo "Total Commits : $TOTAL_COMMITS"
    echo "Commits To Fix: $COUNT"
    echo ""
    echo "Email Distribution:"
    git log --pretty=format:"%ae" | sort | uniq -c
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

    rm -f "$TEMP_ALLOWED"

    cd ..
    continue
  fi

  echo -e "  ${YELLOW}⚠️ $COUNT commit(s) need fixing${RESET}"

  ((TOTAL_COMMITS_FIXED += COUNT))

  echo -e "  ${DIM}Affected commits:${RESET}"

  PREVIEW=""

  while read -r line; do

    EMAIL=$(echo "$line" | awk -F'|' '{print $3}' | xargs)

    if ! grep -qxF "$EMAIL" "$TEMP_ALLOWED"; then
      PREVIEW="${PREVIEW}${line}\n"
    fi

  done < <(git log --pretty=format:"%h | %an | %ae | %ad" --date=iso | head -20)

  echo -e "$PREVIEW" | head -5

  {
    echo "Affected Commits:"
    echo -e "$PREVIEW" | head -10
    echo ""
  } >> "../$(basename "$REPORT_FILE")"

  # ── Dry Run ───────────────────────────────────────────────
  if [ "$DRY_RUN" = true ]; then

    echo -e "  ${YELLOW}[DRY RUN] Would rewrite $COUNT commit(s) and force-push${RESET}"

    {
      echo "STATUS : DRY RUN"
      echo "Action : Would rewrite history"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    rm -f "$TEMP_ALLOWED"

    cd ..
    continue
  fi

  # ── Rewrite History ───────────────────────────────────────
  echo -e "  ${CYAN}🔧 Rewriting history...${RESET}"

  MAILMAP_FILE=$(mktemp)

  if [ -n "$OLD_EMAIL" ]; then

    echo "$CORRECT_NAME <$CORRECT_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"

  else

    git log --pretty=format:"%ae" | sort -u | while read -r bad_email; do

      if ! grep -qxF "$bad_email" "$TEMP_ALLOWED"; then
        echo "$CORRECT_NAME <$CORRECT_EMAIL> <$bad_email>"
      fi

    done > "$MAILMAP_FILE"

  fi

  git filter-repo --mailmap "$MAILMAP_FILE" --force > /tmp/gitfix_output.txt 2>&1

  rm -f "$MAILMAP_FILE"
  rm -f "$TEMP_ALLOWED"

  git remote add origin "$REMOTE_URL" 2>/dev/null || \
  git remote set-url origin "$REMOTE_URL"

  echo -e "  ${CYAN}🚀 Force pushing...${RESET}"

  if git push --force 2>&1; then

    echo -e "  ${GREEN}✅ Fixed & pushed${RESET}"

    {
      echo "STATUS : FIXED"
      echo "Action : History rewritten"
      echo "Commits Fixed : $COUNT"
      echo "--------------------------------------------------"
      echo ""
    } >> "../$(basename "$REPORT_FILE")"

    ((FIXED++))

  else

    echo -e "  ${RED}❌ Push failed${RESET}"

    {
      echo "STATUS : FAILED"
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
  echo "Repos Fixed         : $FIXED"
  echo "Repos Clean         : $CLEAN"
  echo "Repos Skipped       : $SKIPPED"
  echo "Repos Failed        : $FAILED"
  echo "Total Commits Fixed : $TOTAL_COMMITS_FIXED"
  echo "Dry Run             : $DRY_RUN"
} >> "$REPORT_FILE"

echo ""
echo -e "${BOLD}🎉 Done!${RESET}"

echo -e "  ${GREEN}Fixed   : $FIXED${RESET}"
echo -e "  ${GREEN}Clean   : $CLEAN${RESET}"
echo -e "  ${DIM}Skipped : $SKIPPED${RESET}"
echo -e "  ${RED}Failed  : $FAILED${RESET}"

echo -e "  ${CYAN}Commits Fixed : $TOTAL_COMMITS_FIXED${RESET}"

if [ "$DRY_RUN" = true ]; then
  echo -e "\n  ${YELLOW}Dry run only — no changes made.${RESET}"
fi

echo -e "\n  📄 Report saved to: ${BOLD}$REPORT_FILE${RESET}\n"