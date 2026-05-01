#!/bin/bash

# ============================================================
#   fix_commits.sh  v2.0
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
echo "║         fix_commits.sh  v2.0                         ║"
echo "║         Git Commit Email Fix Tool                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Check git-filter-repo is installed ───────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  echo -e "${RED}❌ git-filter-repo not found.${RESET}"
  echo -e "   Install it first:"
  echo -e "   ${DIM}pip install git-filter-repo${RESET}   (or via your package manager)"
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

# ── Dry-run option ────────────────────────────────────────────
echo ""
read -p "  Dry run first? Shows what would change without modifying anything (y/n): " DRY_RUN_CHOICE
if [ "$DRY_RUN_CHOICE" = "y" ]; then
  DRY_RUN=true
  echo -e "  ${YELLOW}⚠️  Dry-run mode — no changes will be made or pushed${RESET}"
else
  DRY_RUN=false
fi

BASE_PATH="${BASE_PATH%/}"

# ── Enforce correct global Git config ────────────────────────
CURRENT_GLOBAL_EMAIL=$(git config --global user.email 2>/dev/null)
if [ "$CURRENT_GLOBAL_EMAIL" != "$CORRECT_EMAIL" ]; then
  echo -e "\n  ${YELLOW}⚠️  Global git email is '${CURRENT_GLOBAL_EMAIL:-not set}', expected '$CORRECT_EMAIL'${RESET}"
  read -p "  Update global git config now? (y/n): " choice
  if [ "$choice" = "y" ]; then
    git config --global user.email "$CORRECT_EMAIL"
    git config --global user.name "$CORRECT_NAME"
    echo -e "  ${GREEN}✅ Global Git config updated${RESET}"
  else
    echo -e "  ${RED}❌ Please fix global config before continuing${RESET}"
    exit 1
  fi
fi

cd "$BASE_PATH" || exit 1

FIXED=0
SKIPPED=0
CLEAN=0

for repo in */; do
  repo="${repo%/}"
  if [ ! -d "$repo/.git" ]; then continue; fi

  echo -e "\n${CYAN}🔍 $repo${RESET}"
  cd "$repo" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)

  # Skip repos not owned by the user
  if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then
    echo -e "  ${DIM}⏭️  Skipping — remote doesn't match username${RESET}"
    ((SKIPPED++))
    cd ..
    continue
  fi

  # Count commits to fix
  if [ -n "$OLD_EMAIL" ]; then
    COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cxF "$OLD_EMAIL")
  else
    COUNT=$(git log --pretty=format:"%ae" 2>/dev/null | grep -cvxF "$CORRECT_EMAIL")
  fi

  if [ "$COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}✅ No issues found${RESET}"
    ((CLEAN++))
    cd ..
    continue
  fi

  echo -e "  ${YELLOW}⚠️  $COUNT commit(s) need fixing${RESET}"

  # Show preview of affected commits
  echo -e "  ${DIM}Affected commits (up to 5):${RESET}"
  if [ -n "$OLD_EMAIL" ]; then
    git log --pretty=format:"    %h | %an | %ae" 2>/dev/null | grep "$OLD_EMAIL" | head -5
  else
    git log --pretty=format:"    %h | %an | %ae" 2>/dev/null | grep -v "$CORRECT_EMAIL" | head -5
  fi

  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}[DRY RUN] Would rewrite $COUNT commit(s) and force-push${RESET}"
    cd ..
    continue
  fi

  echo -e "  ${CYAN}🔧 Rewriting history with git-filter-repo...${RESET}"

  # Build the mailmap file for git-filter-repo
  MAILMAP_FILE=$(mktemp)

  if [ -n "$OLD_EMAIL" ]; then
    # Targeted: only remap the specific old email
    echo "$CORRECT_NAME <$CORRECT_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"
  else
    # Fix-all: remap every distinct wrong email found in this repo
    git log --pretty=format:"%ae" 2>/dev/null | grep -vxF "$CORRECT_EMAIL" | sort -u | while read -r bad_email; do
      echo "$CORRECT_NAME <$CORRECT_EMAIL> <$bad_email>"
    done > "$MAILMAP_FILE"
  fi

  git filter-repo --mailmap "$MAILMAP_FILE" --force 2>&1 | tail -3
  rm -f "$MAILMAP_FILE"

  # Re-add remote (filter-repo removes it as a safety measure)
  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

  echo -e "  ${CYAN}🚀 Force pushing...${RESET}"
  if git push --force 2>&1; then
    echo -e "  ${GREEN}✅ Fixed & pushed: $repo${RESET}"
    ((FIXED++))
  else
    echo -e "  ${RED}❌ Push failed for: $repo — check remote access${RESET}"
  fi

  cd ..
  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
done

echo ""
echo -e "${BOLD}🎉 Done!${RESET}"
echo -e "  ${GREEN}Fixed  : $FIXED${RESET}"
echo -e "  ${GREEN}Clean  : $CLEAN${RESET}"
echo -e "  ${DIM}Skipped: $SKIPPED${RESET}"
if [ "$DRY_RUN" = true ]; then
  echo -e "\n  ${YELLOW}This was a dry run — re-run and choose 'n' to apply changes.${RESET}"
fi
echo ""
