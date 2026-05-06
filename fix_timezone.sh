#!/bin/bash

# ============================================================
#   fix_timezone.sh  v1.0
#   UTC Boundary Fix Tool for Near-Midnight IST Commits
#   Problem: Commits made in IST between 00:00–05:29 AM
#            appear on the PREVIOUS day in GitHub (UTC).
#   Fix: Shifts commit timestamps forward so they land
#        safely within the intended UTC day.
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
echo "║         fix_timezone.sh  v1.0                        ║"
echo "║         UTC Boundary Fix for IST Commits             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "  ${DIM}IST is UTC+5:30. Commits made between 12:00 AM–5:29 AM IST"
echo -e "  fall on the PREVIOUS UTC day → GitHub streak breaks.${RESET}"
echo -e "  ${DIM}This tool detects and shifts those commits safely forward.${RESET}\n"

# ── Check git-filter-repo ────────────────────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  echo -e "${RED}❌ git-filter-repo not found.${RESET}"
  echo -e "   ${DIM}pip install git-filter-repo${RESET}"
  exit 1
fi

# ── Inputs ───────────────────────────────────────────────────
read -p "  Enter path (single repo OR parent folder): " INPUT_PATH
read -p "  Enter your GitHub username: " GITHUB_USERNAME

echo ""
echo -e "  ${DIM}Shift strategy for boundary commits:${RESET}"
echo -e "    ${BOLD}1)${RESET} Push to 06:00 AM IST (safe, same IST day, clears UTC boundary)"
echo -e "    ${BOLD}2)${RESET} Push to 09:00 AM IST (comfortable mid-morning)"
echo -e "    ${BOLD}3)${RESET} Custom offset (you specify hours to add)"
read -p "  Choose [1/2/3]: " SHIFT_CHOICE

case "$SHIFT_CHOICE" in
  1) SHIFT_HOURS=6;  SHIFT_LABEL="06:00 AM IST" ;;
  2) SHIFT_HOURS=9;  SHIFT_LABEL="09:00 AM IST" ;;
  3)
    read -p "  Enter hour to shift to (IST, 0–23): " SHIFT_HOURS
    SHIFT_LABEL="${SHIFT_HOURS}:00 IST"
    ;;
  *) SHIFT_HOURS=6; SHIFT_LABEL="06:00 AM IST (default)" ;;
esac

echo ""
read -p "  Dry run first? Preview affected commits without changing anything (y/n): " DRY_RUN_CHOICE
[ "$DRY_RUN_CHOICE" = "y" ] && DRY_RUN=true || DRY_RUN=false

if [ "$DRY_RUN" = true ]; then
  echo -e "  ${YELLOW}⚠️  Dry-run mode — no changes will be made${RESET}"
fi

INPUT_PATH="${INPUT_PATH%/}"

# ── Detect single vs multi-repo ──────────────────────────────
if [ -d "$INPUT_PATH/.git" ]; then
  REPOS=("$INPUT_PATH")
else
  REPOS=()
  while IFS= read -r -d '' dir; do
    REPOS+=("${dir%/.git}")
  done < <(find "$INPUT_PATH" -maxdepth 2 -name ".git" -type d -print0 2>/dev/null)

  if [ ${#REPOS[@]} -eq 0 ]; then
    echo -e "\n${RED}❌ No Git repositories found at: $INPUT_PATH${RESET}"
    exit 1
  fi
fi

echo -e "\n  ${GREEN}Found ${#REPOS[@]} repo(s)${RESET}\n"

OUTPUT_FILE="$INPUT_PATH/timezone_fix_report_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "fix_timezone Report  v1.0"
  echo "Generated : $(date)"
  echo "Path      : $INPUT_PATH"
  echo "Shift to  : $SHIFT_LABEL"
  echo "Dry run   : $DRY_RUN"
  echo "=================================================="
} > "$OUTPUT_FILE"

TOTAL_FIXED_REPOS=0
TOTAL_AFFECTED_COMMITS=0

# ════════════════════════════════════════════════════════════
# PROCESS EACH REPO
# ════════════════════════════════════════════════════════════
for REPO in "${REPOS[@]}"; do
  REPO_NAME=$(basename "$REPO")
  echo -e "${CYAN}🔍 $REPO_NAME${RESET}"

  cd "$REPO" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)

  if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then
    echo -e "  ${DIM}⏭️  Skipping — not your repo${RESET}"
    echo "REPO: $REPO_NAME — Skipped (not owner)" >> "$OUTPUT_FILE"
    cd "$INPUT_PATH" || exit
    continue
  fi

  # ── Find boundary commits ──────────────────────────────────
  # A commit is "boundary-risky" if its UTC hour is 18–23
  # (which means it was made between 23:30–05:29 IST)
  AFFECTED_COMMITS=()
  while IFS= read -r line; do
    HASH=$(echo "$line" | awk '{print $1}')
    UTC_TIMESTAMP=$(git log -1 --format="%ad" --date=format:"%H" "$HASH" 2>/dev/null)
    # Commits in UTC hours 18-23 = IST 23:30-05:29 = boundary zone
    if [ "$UTC_TIMESTAMP" -ge 18 ] 2>/dev/null; then
      AFFECTED_COMMITS+=("$HASH")
    fi
  done < <(git log --pretty=format:"%H %ad" --date=format:"%H" 2>/dev/null)

  COUNT=${#AFFECTED_COMMITS[@]}

  if [ "$COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}✅ No boundary commits found${RESET}"
    echo "REPO: $REPO_NAME — Clean (no boundary commits)" >> "$OUTPUT_FILE"
    cd "$INPUT_PATH" || exit
    continue
  fi

  ((TOTAL_AFFECTED_COMMITS += COUNT))
  echo -e "  ${YELLOW}⚠️  $COUNT commit(s) in UTC boundary zone${RESET}"

  # Show preview
  echo -e "  ${DIM}Affected commits:${RESET}"
  for h in "${AFFECTED_COMMITS[@]}"; do
    IST_TIME=$(git log -1 --format="%ad" --date=format:"%Y-%m-%d %H:%M IST" "$h" 2>/dev/null)
    UTC_TIME=$(TZ=UTC git log -1 --format="%ad" --date=format:"%Y-%m-%d %H:%M UTC" "$h" 2>/dev/null)
    MSG=$(git log -1 --format="%s" "$h" 2>/dev/null | cut -c1-50)
    echo -e "    ${DIM}$h  |  $UTC_TIME  |  $IST_TIME  |  $MSG${RESET}"
    echo "  $h | $UTC_TIME | $IST_TIME | $MSG" >> "$OUTPUT_FILE"
  done

  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}[DRY RUN] Would shift $COUNT commit(s) to $SHIFT_LABEL and force-push${RESET}"
    echo "REPO: $REPO_NAME — DRY RUN: $COUNT commits would be shifted" >> "$OUTPUT_FILE"
    cd "$INPUT_PATH" || exit
    continue
  fi

  # ── Write callback script for git-filter-repo ─────────────
  # We shift each affected commit's author/committer date
  # so the UTC hour lands safely in daytime (past boundary)
  CALLBACK_FILE=$(mktemp /tmp/tz_callback_XXXX.py)
  # Build a python set of affected hashes
  HASH_LIST=$(printf "'%s'," "${AFFECTED_COMMITS[@]}")
  HASH_LIST="[${HASH_LIST%,}]"

  cat > "$CALLBACK_FILE" << PYEOF
import subprocess, datetime, re

affected = $HASH_LIST
target_ist_hour = $SHIFT_HOURS  # shift to this IST hour

def fix_date(date_str):
    # date_str format from git: "1234567890 +0530"
    parts = date_str.split()
    if len(parts) != 2:
        return date_str
    ts = int(parts[0])
    dt = datetime.datetime.utcfromtimestamp(ts)
    # Convert to IST
    ist = dt + datetime.timedelta(hours=5, minutes=30)
    # Only shift if in boundary zone (IST hour < target)
    if ist.hour < target_ist_hour:
        ist = ist.replace(hour=target_ist_hour, minute=0, second=0)
        # Convert back to UTC unix timestamp
        utc_back = ist - datetime.timedelta(hours=5, minutes=30)
        new_ts = int(utc_back.timestamp())
        return f"{new_ts} +0530"
    return date_str

def callback(commit, metadata):
    h = commit.original_id
    if h and h.decode() in affected:
        commit.author_date    = fix_date(commit.author_date.decode()).encode()
        commit.committer_date = fix_date(commit.committer_date.decode()).encode()
PYEOF

  echo -e "  ${CYAN}🔧 Shifting commit timestamps...${RESET}"
  git filter-repo --commit-callback "$(cat "$CALLBACK_FILE")" --force 2>&1 | tail -3
  rm -f "$CALLBACK_FILE"

  # Re-add remote
  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

  echo -e "  ${CYAN}🚀 Force pushing...${RESET}"
  if git push --force 2>&1; then
    echo -e "  ${GREEN}✅ Fixed & pushed: $REPO_NAME${RESET}"
    ((TOTAL_FIXED_REPOS++))
    echo "REPO: $REPO_NAME — FIXED: $COUNT commits shifted to $SHIFT_LABEL" >> "$OUTPUT_FILE"
  else
    echo -e "  ${RED}❌ Push failed — check remote access${RESET}"
    echo "REPO: $REPO_NAME — PUSH FAILED" >> "$OUTPUT_FILE"
  fi

  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
  cd "$INPUT_PATH" || exit
done

# ── Final summary ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}Done!${RESET}"
echo -e "  ${YELLOW}Boundary commits found : $TOTAL_AFFECTED_COMMITS${RESET}"

if [ "$DRY_RUN" = true ]; then
  echo -e "  ${YELLOW}Dry run — no changes made. Re-run and choose 'n' to apply.${RESET}"
else
  echo -e "  ${GREEN}Repos fixed & pushed   : $TOTAL_FIXED_REPOS${RESET}"
fi

{
  echo ""
  echo "=================================================="
  echo "SUMMARY"
  echo "Boundary commits found : $TOTAL_AFFECTED_COMMITS"
  echo "Repos fixed            : $TOTAL_FIXED_REPOS"
  echo "Dry run                : $DRY_RUN"
} >> "$OUTPUT_FILE"

echo -e "\n  📄 Report saved to: ${BOLD}$OUTPUT_FILE${RESET}\n"