#!/bin/bash
# ============================================================
#   dashboard.sh  v1.0
#   Live Contribution Dashboard
#   Feature 7: dashboard mode
#   Part of: git-identity-fixer toolkit
#
#   Usage: bash dashboard.sh
#   • Refreshes every 60 seconds (Ctrl+C to quit)
#   • Press 'r' to force-refresh immediately
#   • Optionally saves a snapshot report every N refreshes
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/utc_analysis.sh"

REFRESH_INTERVAL=60    # seconds between auto-refresh

# ── Inputs ───────────────────────────────────────────────────
clear
header "git-contribution-fixer  Dashboard  v1.0" "Live Contribution Health Monitor"

read -rp "  Base directory (parent of your repos): " BASE_PATH
read -rp "  Your GitHub email: "    CORRECT_EMAIL
read -rp "  Your GitHub username: " GITHUB_USERNAME
read -rp "  Refresh interval in seconds [60]: " RI_INPUT
[ -n "$RI_INPUT" ] && REFRESH_INTERVAL="$RI_INPUT"

BASE_PATH="${BASE_PATH%/}"

if [ ! -d "$BASE_PATH" ]; then
  echo -e "${RED}❌ Directory not found: $BASE_PATH${RESET}"
  exit 1
fi

# ── Source optional modules ───────────────────────────────────
HAVE_STREAK=false
HAVE_GITHUB=false

[ -f "$SCRIPT_DIR/streak.sh"     ] && { source "$SCRIPT_DIR/streak.sh";     HAVE_STREAK=true; }
[ -f "$SCRIPT_DIR/github_api.sh" ] && { source "$SCRIPT_DIR/github_api.sh"; HAVE_GITHUB=true; }

if $HAVE_GITHUB; then
  echo ""
  echo -e "  ${DIM}Optional: GitHub API token for live contribution data${RESET}"
  github_prompt_token
fi

# ── Report config ────────────────────────────────────────────
DASH_REPORT=false
DASH_REPORT_INTERVAL=0   # every N refreshes (0 = every refresh)
DASH_REFRESH_COUNT=0     # internal counter

echo ""
read -rp "  Save dashboard snapshot reports? (y/n): " _DREPORT_CHOICE
if [ "$_DREPORT_CHOICE" = "y" ]; then
  DASH_REPORT=true
  source "$SCRIPT_DIR/report.sh"
  echo -e "  ${DIM}How often to save a report?${RESET}"
  echo -e "  ${DIM}  0 = every refresh${RESET}"
  echo -e "  ${DIM}  N = every N refreshes (e.g. 5 = every 5th refresh)${RESET}"
  read -rp "  Save every [N] refreshes [0]: " _DREPORT_INT
  DASH_REPORT_INTERVAL=$(( 10#${_DREPORT_INT:-0} ))
  echo -e "  ${GREEN}✅ Reports will save to: ${BOLD}$BASE_PATH${RESET}"
fi

# ════════════════════════════════════════════════════════════
# RENDER FUNCTION — draws the full dashboard
# ════════════════════════════════════════════════════════════
render_dashboard() {
  clear

  utc_detect_offset

  local now_local; now_local=$(date '+%Y-%m-%d %H:%M:%S %Z')
  local now_utc;   now_utc=$(date   -u '+%Y-%m-%d %H:%M:%S UTC')
  local today_utc; today_utc=$(date -u '+%Y-%m-%d')

  # ── Header ───────────────────────────────────────────────
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════════════════╗"
  printf "║  %-72s  ║\n" "🔧 git-identity-fixer  DASHBOARD"
  printf "║  %-72s  ║\n" "   $now_local  |  $now_utc"
  echo "╚══════════════════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"

  # ── UTC Boundary Alert ───────────────────────────────────
  local utc_hour; utc_hour=$(date -u +%H)
  local utc_min;  utc_min=$(date  -u +%M)
  local mins_left=$(( (24 - utc_hour) * 60 - utc_min ))
  [ "$mins_left" -eq 1440 ] && mins_left=0

  if   [ "$mins_left" -le 30 ]; then
    echo -e "  ${RED}${BOLD}🚨 UTC MIDNIGHT IN ${mins_left} MINUTES — COMMIT NOW TO SAVE YOUR STREAK!${RESET}\n"
  elif [ "$mins_left" -le 120 ]; then
    echo -e "  ${YELLOW}⏰  UTC midnight in ~${mins_left} min — consider committing soon${RESET}\n"
  fi

  # ── IST boundary zone ─────────────────────────────────────
  local ist_hour; ist_hour=$(( (utc_hour * 60 + utc_min + TZ_OFFSET_MIN) / 60 % 24 ))
  local abs_off="${TZ_OFFSET_MIN#-}"
  local boundary_h=$(( abs_off / 60 + 1 ))
  if [ "$ist_hour" -lt "$boundary_h" ] && [ "$ist_hour" -ge 0 ]; then
    echo -e "  ${YELLOW}⚠️  Local time ${ist_hour}:xx (${TZ_NAME}) — commits now appear on YESTERDAY on GitHub${RESET}\n"
  fi

  # ── GitHub API stats ─────────────────────────────────────
  if $HAVE_GITHUB; then
    echo -e "${BOLD}  📡 GitHub API${RESET}"
    github_rate_limit
    github_today_contributions "$GITHUB_USERNAME"
    echo ""
  fi

  # ── Today's local commits ─────────────────────────────────
  echo -e "${BOLD}  📊 Repository Status${RESET}"
  echo -e "  ${DIM}$(printf '%-30s  %-8s  %-8s  %-8s  %-10s' 'REPO' 'COMMITS' 'TODAY' 'ISSUES' 'SYNC')${RESET}"
  echo -e "  ${DIM}$(printf '%0.s─' {1..72})${RESET}"

  local total_repos=0
  local total_today=0
  local total_issues=0
  local repos_behind=0

  for repo in "$BASE_PATH"/*/; do
    [ -d "$repo/.git" ] || continue
    ((total_repos++))

    local rname; rname=$(basename "$repo")

    # Total commits
    local total_c; total_c=$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo "?")

    # Today's commits (UTC)
    local today_c; today_c=$(git -C "$repo" log \
      --author="$CORRECT_EMAIL" \
      --after="${today_utc}T00:00:00Z" \
      --oneline 2>/dev/null | wc -l | tr -d ' \n\r')
    today_c=$(( 10#${today_c:-0} ))
    total_today=$(( total_today + today_c ))

    # Wrong-email commits
    local wrong_c; wrong_c=$(git -C "$repo" log \
      --pretty=format:"%ae" 2>/dev/null | \
      grep -cv "^${CORRECT_EMAIL}$" 2>/dev/null || true)
    wrong_c=$(( 10#${wrong_c:-0} ))
    total_issues=$(( total_issues + wrong_c ))

    # Sync status
    local sync_raw; sync_raw=$(git -C "$repo" status -sb 2>/dev/null | head -1)
    local sync_label
    if echo "$sync_raw" | grep -q "ahead";  then sync_label="${YELLOW}↑ahead${RESET}";  ((repos_behind++)); \
    elif echo "$sync_raw" | grep -q "behind"; then sync_label="${YELLOW}↓behind${RESET}"; ((repos_behind++)); \
    else sync_label="${GREEN}✓ synced${RESET}"; fi

    # Color today column
    local today_col
    if [ "$today_c" -gt 0 ]; then today_col="${GREEN}${today_c}${RESET}"
    else today_col="${RED}0${RESET}"; fi

    # Color issues column
    local issue_col
    if [ "$wrong_c" -gt 0 ]; then issue_col="${RED}${wrong_c}${RESET}"
    else issue_col="${GREEN}0${RESET}"; fi

    printf "  %-30s  %-8s  " "$rname" "$total_c"
    echo -en "$today_col        "
    echo -en "$issue_col        "
    echo -e  "$sync_label"
  done

  # ── Summary bar ──────────────────────────────────────────
  echo -e "\n  ${DIM}$(printf '%0.s─' {1..72})${RESET}"
  echo -e "  ${BOLD}Repos: $total_repos  |  Today's commits: ${GREEN}${total_today}${RESET}${BOLD}  |  Wrong-email: ${wrong_c:+${RED}}${total_issues}${RESET}${BOLD}  |  Out of sync: ${repos_behind}${RESET}"

  # ── Streak safety ─────────────────────────────────────────
  if $HAVE_STREAK; then
    echo ""
    echo -e "${BOLD}  🔥 Streak Safety${RESET}"
    local today_total=0
    for repo in "$BASE_PATH"/*/; do
      [ -d "$repo/.git" ] || continue
      local cnt; cnt=$(git -C "$repo" log \
        --author="$CORRECT_EMAIL" \
        --after="${today_utc}T00:00:00Z" \
        --oneline 2>/dev/null | wc -l | tr -d ' ')
      today_total=$(( today_total + ${cnt:-0} ))
    done

    if [ "$today_total" -eq 0 ]; then
      echo -e "  ${RED}${BOLD}  ⚠️  NO COMMITS TODAY — streak at risk!${RESET}"
    else
      echo -e "  ${GREEN}  ✅ $today_total commit(s) today — streak is safe${RESET}"
    fi
  fi

  # ── Heatmap: last 14 days ─────────────────────────────────
  echo -e "\n${BOLD}  📅 Last 14 Days (UTC)${RESET}"
  echo -en "  "
  for i in $(seq 13 -1 0); do
    local d; d=$(date -d "-${i} days" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
    local dow; dow=$(date -d "$d" +%a 2>/dev/null || date -j -f "%Y-%m-%d" "$d" +%a 2>/dev/null)
    printf "%-5s" "$dow"
  done
  echo ""
  echo -en "  "
  for i in $(seq 13 -1 0); do
    local d; d=$(date -d "-${i} days" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
    local cnt=0
    for repo in "$BASE_PATH"/*/; do
      [ -d "$repo/.git" ] || continue
      local c; c=$(git -C "$repo" log \
        --author="$CORRECT_EMAIL" \
        --after="${d}T00:00:00Z" --before="${d}T23:59:59Z" \
        --oneline 2>/dev/null | wc -l | tr -d ' ')
      cnt=$(( cnt + ${c:-0} ))
    done
    if   [ "$cnt" -ge 5 ]; then echo -en "${GREEN}${BOLD}  ██  ${RESET}"
    elif [ "$cnt" -ge 2 ]; then echo -en "${GREEN}  ▓▓  ${RESET}"
    elif [ "$cnt" -ge 1 ]; then echo -en "${CYAN}  ░░  ${RESET}"
    else                        echo -en "${DIM}  ··  ${RESET}"; fi
  done
  echo -e "\n  ${DIM}  ██=5+  ▓▓=2-4  ░░=1  ··=none${RESET}"

  # ── Quick-action hints ───────────────────────────────────
  echo -e "\n  ${DIM}Quick actions:  [a] audit_report  [f] fix_commits  [t] fix_timezone  [s] save report  [q] quit  [r] refresh${RESET}"
  echo -e "  ${DIM}Auto-refresh in ${REFRESH_INTERVAL}s — press r to refresh now${RESET}"
}

# ════════════════════════════════════════════════════════════
# MAIN LOOP
# ════════════════════════════════════════════════════════════
trap 'echo -e "\n${RESET}Exiting dashboard."; exit 0' INT TERM

# ── Dashboard snapshot save ──────────────────────────────────
save_dashboard_report() {
  report_init "dashboard_snapshot" "$BASE_PATH"
  local today_utc; today_utc=$(date -u '+%Y-%m-%d')
  local now_utc;   now_utc=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

  {
    echo "Dashboard Snapshot Report"
    echo "Generated  : $(date)"
    echo "UTC Time   : $now_utc"
    echo "Base Path  : $BASE_PATH"
    echo "Email      : $CORRECT_EMAIL"
    echo "Username   : $GITHUB_USERNAME"
    echo "Refresh #  : $DASH_REFRESH_COUNT"
    echo "=================================================="
    echo ""
  } >> "$REPORT_TXT"

  local snap_repos=()
  for repo in "$BASE_PATH"/*/; do
    [ -d "$repo/.git" ] || continue
    local rname; rname=$(basename "$repo")
    local total_c; total_c=$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)
    local today_c; today_c=$(git -C "$repo" log       --author="$CORRECT_EMAIL"       --after="${today_utc}T00:00:00Z"       --oneline 2>/dev/null | wc -l | tr -d " 

")
    today_c=$(( 10#${today_c:-0} ))
    local wrong_c; wrong_c=$(git -C "$repo" log       --pretty=format:"%ae" 2>/dev/null | grep -cv "^${CORRECT_EMAIL}$" 2>/dev/null || true)
    wrong_c=$(( 10#${wrong_c:-0} ))
    local remote; remote=$(git -C "$repo" remote get-url origin 2>/dev/null)

    echo "Repo: $rname" >> "$REPORT_TXT"
    echo "  Remote        : $remote" >> "$REPORT_TXT"
    echo "  Total Commits : $total_c" >> "$REPORT_TXT"
    echo "  Today (UTC)   : $today_c" >> "$REPORT_TXT"
    echo "  Wrong Email   : $wrong_c" >> "$REPORT_TXT"
    echo "" >> "$REPORT_TXT"

    local rj; rj="{"repo":"$rname","total":$total_c,"today":$today_c,"wrong_email":$wrong_c}"
    snap_repos+=("$rj")
  done

  report_set_summary "${#snap_repos[@]}" "0" "${#snap_repos[@]}" "0" "0"
  # Override _JSON_REPOS with snapshot data
  _JSON_REPOS=("${snap_repos[@]}")
  report_finalize

  echo -e "  ${GREEN}📄 Snapshot saved${RESET}"
  sleep 1
}

while true; do
  ((DASH_REFRESH_COUNT++))
  render_dashboard

  # ── Save report if due ──────────────────────────────────
  if $DASH_REPORT; then
    if [ "$DASH_REPORT_INTERVAL" -eq 0 ] ||        [ $(( DASH_REFRESH_COUNT % DASH_REPORT_INTERVAL )) -eq 0 ]; then
      save_dashboard_report
    fi
  fi

  # Non-blocking key read with timeout
  if read -r -s -n 1 -t "$REFRESH_INTERVAL" key 2>/dev/null; then
    case "$key" in
      q|Q) echo -e "\n${RESET}Exiting dashboard."; exit 0 ;;
      r|R) continue ;;   # force refresh
      s|S) $DASH_REPORT && save_dashboard_report || echo -e "  ${YELLOW}Reports not enabled — restart dashboard to enable${RESET}"; sleep 1 ;;
      a|A) bash "$SCRIPT_DIR/audit_report.sh";     read -rsp "  [Enter to return to dashboard]" _; ;;
      f|F) bash "$SCRIPT_DIR/fix_commits.sh";      read -rsp "  [Enter to return to dashboard]" _; ;;
      t|T) bash "$SCRIPT_DIR/fix_timezone.sh";     read -rsp "  [Enter to return to dashboard]" _; ;;
    esac
  fi
done