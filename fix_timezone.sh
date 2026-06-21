#!/bin/bash
# ============================================================
#   fix_timezone.sh  v2.0
#   UTC Boundary Fix Tool for Near-Midnight IST Commits
#   Part of: git-identity-fixer toolkit
#
#   Features added:
#   [1] Colored CLI output         (via colors.sh)
#   [2] TXT + JSON report export   (via report.sh)
#   [5] Streak safety warning      (via streak.sh)
#   [6] Auto UTC analysis          (via utc_analysis.sh)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/report.sh"
source "$SCRIPT_DIR/utc_analysis.sh"
source "$SCRIPT_DIR/streak.sh"

header "fix_timezone.sh  v2.0" "UTC Boundary Fix for Near-Midnight Commits"

echo -e "  ${DIM}IST is UTC+5:30. Commits made between 12:00 AM–5:29 AM IST"
echo -e "  fall on the PREVIOUS UTC day → GitHub streak breaks."
echo -e "  This tool auto-detects your timezone and fixes affected commits.${RESET}\n"

# ── Check git-filter-repo ─────────────────────────────────────
if ! command -v git-filter-repo &>/dev/null; then
  fail "git-filter-repo not found."
  echo -e "   ${DIM}pip install git-filter-repo${RESET}"
  exit 1
fi

# ── Feature 6: Auto-detect timezone ──────────────────────────
utc_detect_offset
info "Auto-detected timezone: ${BOLD}${TZ_NAME}${RESET} (UTC offset: ${TZ_OFFSET_MIN} min)"

if [ "$TZ_OFFSET_MIN" -eq 0 ]; then
  warn "UTC offset is 0 — no boundary risk from timezone shift. Proceeding anyway."
fi

# ── Inputs ────────────────────────────────────────────────────
read -rp "  Enter path (single repo OR parent folder): " INPUT_PATH
read -rp "  Enter your GitHub username: "                 GITHUB_USERNAME
read -rp "  Enter your correct GitHub email: "            CORRECT_EMAIL

echo ""
echo -e "  ${DIM}Shift strategy for boundary commits:${RESET}"
echo -e "    ${BOLD}1)${RESET} Push to 06:00 AM local (safe, clears UTC boundary)"
echo -e "    ${BOLD}2)${RESET} Push to 09:00 AM local (comfortable mid-morning)"
echo -e "    ${BOLD}3)${RESET} Custom hour (you specify)"
read -rp "  Choose [1/2/3]: " SHIFT_CHOICE

case "$SHIFT_CHOICE" in
  1) SHIFT_HOURS=6;  SHIFT_LABEL="06:00 AM local" ;;
  2) SHIFT_HOURS=9;  SHIFT_LABEL="09:00 AM local" ;;
  3)
    read -rp "  Enter hour to shift to (0–23): " SHIFT_HOURS
    SHIFT_LABEL="${SHIFT_HOURS}:00 local"
    ;;
  *) SHIFT_HOURS=6; SHIFT_LABEL="06:00 AM local (default)" ;;
esac

echo ""
read -rp "  Dry run first? (y/n): " DRY_RUN_CHOICE
[ "$DRY_RUN_CHOICE" = "y" ] && DRY_RUN=true || DRY_RUN=false

$DRY_RUN && warn "Dry-run mode — no changes will be made"

INPUT_PATH="${INPUT_PATH%/}"

# ── Feature 5: Streak safety check ───────────────────────────
streak_safety_check "$INPUT_PATH" "$CORRECT_EMAIL"
echo ""

# ── Detect single vs multi-repo ──────────────────────────────
if [ -d "$INPUT_PATH/.git" ]; then
  REPOS=("$INPUT_PATH")
else
  REPOS=()
  while IFS= read -r -d '' dir; do
    REPOS+=("${dir%/.git}")
  done < <(find "$INPUT_PATH" -maxdepth 2 -name ".git" -type d -print0 2>/dev/null)

  if [ ${#REPOS[@]} -eq 0 ]; then
    fail "No Git repositories found at: $INPUT_PATH"
    exit 1
  fi
fi

info "Found ${#REPOS[@]} repo(s)"

# ── Feature 2: Init dual report ──────────────────────────────
report_init "timezone_fix" "$INPUT_PATH"

{
  echo "fix_timezone Report  v2.0"
  echo "Generated  : $(date)"
  echo "Path       : $INPUT_PATH"
  echo "Timezone   : $TZ_NAME (UTC+${TZ_OFFSET_MIN}min)"
  echo "Shift to   : $SHIFT_LABEL"
  echo "Dry run    : $DRY_RUN"
  echo "=================================================="
} >> "$REPORT_TXT"

TOTAL_FIXED_REPOS=0
TOTAL_AFFECTED_COMMITS=0

# ════════════════════════════════════════════════════════════
# PROCESS REPOS
# ════════════════════════════════════════════════════════════
for REPO in "${REPOS[@]}"; do
  REPO_NAME=$(basename "$REPO")
  step "$REPO_NAME"
  rtxt "REPO: $REPO_NAME"

  cd "$REPO" || continue

  REMOTE_URL=$(git remote get-url origin 2>/dev/null)

  if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then
    info "Skipping — not your repo"
    rtxt "STATUS: SKIPPED (not owner)"
    rtxt "--------------------------------------------------"
    cd "$INPUT_PATH" || exit
    continue
  fi

  # ── Find boundary commits (auto UTC-aware) ────────────────
  ABS_OFFSET="${TZ_OFFSET_MIN#-}"
  BOUNDARY_UTC_H=$(( (24 - ABS_OFFSET / 60) % 24 ))   # UTC hour where local midnight starts

  AFFECTED_COMMITS=()
  while IFS= read -r line; do
    HASH=$(echo "$line" | awk '{print $1}')
    UTC_H=$(git log -1 --format="%ad" --date=format:"%H" "$HASH" 2>/dev/null)
    if [ "$UTC_H" -ge "$BOUNDARY_UTC_H" ] 2>/dev/null; then
      AFFECTED_COMMITS+=("$HASH")
    fi
  done < <(git log --pretty=format:"%H %ad" --date=format:"%H" 2>/dev/null)

  COUNT=${#AFFECTED_COMMITS[@]}

  if [ "$COUNT" -eq 0 ]; then
    ok "No boundary commits found"
    rtxt "STATUS: CLEAN"
    rtxt "--------------------------------------------------"
    cd "$INPUT_PATH" || exit
    continue
  fi

  ((TOTAL_AFFECTED_COMMITS += COUNT))
  warn "$COUNT commit(s) in UTC boundary zone"

  # Show preview
  echo -e "  ${DIM}Affected commits:${RESET}"
  ISSUES_JSON="[]"
  for h in "${AFFECTED_COMMITS[@]}"; do
    LOC_T=$(git log -1 --format="%ad" --date=format:"%Y-%m-%d %H:%M %Z" "$h" 2>/dev/null)
    UTC_T=$(TZ=UTC git log -1 --format="%ad" --date=format:"%Y-%m-%d %H:%M UTC" "$h" 2>/dev/null)
    MSG=$(git log -1 --format="%s" "$h" 2>/dev/null | cut -c1-50)
    echo -e "    ${DIM}$h  |  $UTC_T  |  $LOC_T  |  $MSG${RESET}"
    rtxt "  $h | $UTC_T | $LOC_T | $MSG"
    hj=$(json_str "$h"); uj=$(json_str "$UTC_T"); lj=$(json_str "$LOC_T"); mj=$(json_str "$MSG")
    obj="{\"hash\":${hj},\"utc\":${uj},\"local\":${lj},\"msg\":${mj}}"
    ISSUES_JSON=$(json_append "$ISSUES_JSON" "$obj")
  done

  if [ "$DRY_RUN" = true ]; then
    warn "[DRY RUN] Would shift $COUNT commit(s) to $SHIFT_LABEL"
    rtxt "STATUS: DRY RUN — $COUNT commits would be shifted"
    cd "$INPUT_PATH" || exit
    continue
  fi

  # ── Write Python callback ────────────────────────────────
  CALLBACK_FILE=$(mktemp /tmp/tz_callback_XXXX.py)
  HASH_LIST=$(printf "'%s'," "${AFFECTED_COMMITS[@]}")
  HASH_LIST="[${HASH_LIST%,}]"
  OFFSET_SECS=$(( TZ_OFFSET_MIN * 60 ))

  cat > "$CALLBACK_FILE" << PYEOF
import datetime

affected     = $HASH_LIST
target_hour  = $SHIFT_HOURS
offset_secs  = $OFFSET_SECS   # system UTC offset in seconds

def fix_date(date_str):
    parts = date_str.split()
    if len(parts) != 2:
        return date_str
    ts      = int(parts[0])
    tz_sign = parts[1]
    dt      = datetime.datetime.utcfromtimestamp(ts)
    local   = dt + datetime.timedelta(seconds=offset_secs)
    # Only shift if in boundary zone
    boundary_local_h = abs(offset_secs) // 3600 + 1
    if local.hour < boundary_local_h:
        local    = local.replace(hour=target_hour, minute=0, second=0)
        utc_back = local - datetime.timedelta(seconds=offset_secs)
        new_ts   = int(utc_back.timestamp())
        return f"{new_ts} {tz_sign}"
    return date_str

def callback(commit, metadata):
    h = commit.original_id
    if h and h.decode() in affected:
        commit.author_date    = fix_date(commit.author_date.decode()).encode()
        commit.committer_date = fix_date(commit.committer_date.decode()).encode()
PYEOF

  info "Shifting commit timestamps..."
  git filter-repo --commit-callback "$(cat "$CALLBACK_FILE")" --force 2>&1 | tail -3
  rm -f "$CALLBACK_FILE"

  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

  info "Force pushing..."
  if git push --force 2>&1; then
    ok "Fixed & pushed: $REPO_NAME"
    ((TOTAL_FIXED_REPOS++))
    rtxt "STATUS: FIXED — $COUNT commits shifted to $SHIFT_LABEL"
  else
    fail "Push failed — check remote access"
    rtxt "STATUS: PUSH FAILED"
  fi

  rtxt "--------------------------------------------------"
  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
  cd "$INPUT_PATH" || exit
done

# ── Summary ──────────────────────────────────────────────────
section "SUMMARY"
echo -e "  ${YELLOW}Boundary commits found : $TOTAL_AFFECTED_COMMITS${RESET}"

if $DRY_RUN; then
  warn "Dry run — no changes made. Re-run and choose 'n' to apply."
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
} >> "$REPORT_TXT"

report_set_summary "${#REPOS[@]}" "0" "$TOTAL_FIXED_REPOS" "$TOTAL_AFFECTED_COMMITS" "$TOTAL_AFFECTED_COMMITS"
report_finalize

echo ""
