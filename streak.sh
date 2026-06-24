#!/bin/bash
# ============================================================
#   streak.sh  — Contribution Prediction + Streak Safety
#   Feature 4: contribution prediction
#   Feature 5: streak safety warning
#   Source this file:  source "$(dirname "$0")/streak.sh"
# ============================================================

# ── Feature 4: Contribution Prediction ───────────────────────
# Analyzes last N days of commits across all repos in BASE_PATH
# and predicts likely contribution patterns.
#
#   predict_contributions "$BASE_PATH" "$CORRECT_EMAIL" [days=30]
#
predict_contributions() {
  local base="$1" email="$2" days="${3:-30}"

  section "CONTRIBUTION PREDICTION (last ${days} days)"

  local -A day_counts   # date → count
  local total=0

  # Collect commits across all repos
  for repo in "$base"/*/; do
    [ -d "$repo/.git" ] || continue
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      day_counts["$d"]=$(( ${day_counts["$d"]:-0} + 1 ))
      ((total++))
    done < <(git -C "$repo" log \
      --author="$email" \
      --pretty=format:"%ad" \
      --date=format:"%Y-%m-%d" \
      --since="${days} days ago" 2>/dev/null)
  done

  if [ "$total" -eq 0 ]; then
    warn "No commits by $email found in the last ${days} days."
    return
  fi

  local active_days="${#day_counts[@]}"
  local avg_per_active; avg_per_active=$(echo "scale=1; $total / $active_days" | bc 2>/dev/null || echo "?")
  local avg_per_day;    avg_per_day=$(echo   "scale=1; $total / $days"         | bc 2>/dev/null || echo "?")

  echo -e "\n  ${BOLD}Stats (last ${days} days):${RESET}"
  echo -e "  Total commits      : ${BOLD}$total${RESET}"
  echo -e "  Active days        : ${BOLD}$active_days${RESET} / $days"
  echo -e "  Avg commits/day    : ${BOLD}$avg_per_day${RESET}"
  echo -e "  Avg on active days : ${BOLD}$avg_per_active${RESET}"

  # Predict streak probability
  local streak_pct; streak_pct=$(echo "scale=0; $active_days * 100 / $days" | bc 2>/dev/null || echo "?")
  echo -e "\n  ${BOLD}Streak consistency:${RESET} ${CYAN}${streak_pct}%${RESET} of days had a commit"

  if   [ "$streak_pct" -ge 90 ] 2>/dev/null; then
    ok  "Excellent cadence — streak very likely to continue"
  elif [ "$streak_pct" -ge 70 ] 2>/dev/null; then
    warn "Good cadence — watch for gaps on low-activity days"
  elif [ "$streak_pct" -ge 50 ] 2>/dev/null; then
    warn "Moderate cadence — streak at risk on inactive days"
  else
    fail "Low cadence (${streak_pct}%) — streak is fragile"
    echo -e "  ${DIM}Tip: Even one small commit per day preserves the streak.${RESET}"
  fi

  # Day-of-week breakdown
  echo -e "\n  ${BOLD}Commits by day of week:${RESET}"
  local -A dow_counts
  for date in "${!day_counts[@]}"; do
    local dow; dow=$(date -d "$date" +%a 2>/dev/null || date -j -f "%Y-%m-%d" "$date" +%a 2>/dev/null)
    dow_counts["$dow"]=$(( ${dow_counts["$dow"]:-0} + ${day_counts["$date"]} ))
  done
  for dow in Mon Tue Wed Thu Fri Sat Sun; do
    local c="${dow_counts[$dow]:-0}"
    local bar; bar=$(printf '█%.0s' $(seq 1 $((c > 20 ? 20 : c > 0 ? c : 0))))
    printf "    %-3s  %s %s\n" "$dow" "${bar:-·}" "$c"
  done

  # Project next 7 days
  echo -e "\n  ${BOLD}Projected contribution risk (next 7 days):${RESET}"
  local today_dow; today_dow=$(date +%a)
  local risk_flag=false
  for i in 0 1 2 3 4 5 6; do
    local fdate; fdate=$(date -d "+${i} days" +%Y-%m-%d 2>/dev/null || date -v+${i}d +%Y-%m-%d 2>/dev/null)
    local fdow;  fdow=$(date  -d "+${i} days" +%a        2>/dev/null || date -v+${i}d +%a        2>/dev/null)
    local hist="${dow_counts[$fdow]:-0}"
    if [ "$hist" -eq 0 ]; then
      echo -e "    ${YELLOW}$fdate ($fdow) — no historical commits on this day ⚠️${RESET}"
      risk_flag=true
    else
      echo -e "    ${GREEN}$fdate ($fdow) — typically active ($hist commits)${RESET}"
    fi
  done

  if [ "$risk_flag" = true ]; then
    warn "Plan commits on the highlighted days to keep your streak safe."
  fi
}

# ── Feature 5: Streak Safety Warning ─────────────────────────
# Checks current UTC time and warns if near midnight boundary.
# Also scans today's commits across repos and warns if none yet.
#
#   streak_safety_check "$BASE_PATH" "$CORRECT_EMAIL"
#
streak_safety_check() {
  local base="$1" email="$2"

  section "STREAK SAFETY WARNING"

  local utc_hour;   utc_hour=$(date   -u +%H)
  local utc_min;    utc_min=$(date    -u +%M)
  local ist_hour;   ist_hour=$(( (utc_hour * 60 + utc_min + 330) / 60 % 24 ))
  local local_time; local_time=$(date '+%H:%M %Z')
  local utc_time;   utc_time=$(date -u '+%H:%M UTC')

  info "Local: $local_time  |  UTC: $utc_time"

  # ── UTC midnight proximity ────────────────────────────────
  local mins_to_midnight=$(( (24 - utc_hour) * 60 - utc_min ))
  [ "$mins_to_midnight" -eq 1440 ] && mins_to_midnight=0

  if   [ "$mins_to_midnight" -le 30 ] && [ "$mins_to_midnight" -ge 0 ]; then
    fail "UTC midnight in ${mins_to_midnight} min — commit NOW to avoid losing the day!"
    echo -e "  ${RED}${BOLD}  ⏰ CRITICAL: Any commit after midnight UTC counts tomorrow.${RESET}"
  elif [ "$mins_to_midnight" -le 120 ]; then
    warn "UTC midnight in ~${mins_to_midnight} min — consider committing soon"
  fi

  # ── IST boundary zone (12:00 AM – 5:29 AM IST = yesterday UTC) ──
  if [ "$ist_hour" -ge 0 ] && [ "$ist_hour" -lt 6 ]; then
    warn "IST time is ${ist_hour}:xx — commits now appear on YESTERDAY in UTC!"
    echo -e "  ${DIM}  Run fix_timezone.sh to shift these commits to the correct UTC day.${RESET}"
  fi

  # ── Today's commit check ──────────────────────────────────
  local today_utc; today_utc=$(date -u +%Y-%m-%d)
  local today_commits=0

  for repo in "$base"/*/; do
    [ -d "$repo/.git" ] || continue
    local cnt; cnt=$(git -C "$repo" log \
      --author="$email" \
      --after="${today_utc}T00:00:00Z" \
      --before="${today_utc}T23:59:59Z" \
      --oneline 2>/dev/null | wc -l | tr -d ' ')
    today_commits=$(( today_commits + cnt ))
  done

  if [ "$today_commits" -eq 0 ]; then
    warn "No commits found today (${today_utc} UTC) — streak at risk!"
    echo -e "  ${DIM}  Make at least one commit to preserve your streak.${RESET}"
  else
    ok "$today_commits commit(s) found today (${today_utc} UTC) — streak is safe ✓"
  fi
}
