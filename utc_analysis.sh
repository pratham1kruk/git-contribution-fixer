#!/bin/bash
# ============================================================
#   utc_analysis.sh  — Auto UTC Boundary Analysis
#   Feature 6: auto UTC analysis
#   Source this file:  source "$(dirname "$0")/utc_analysis.sh"
#
#   Automatically detects the user's UTC offset from the system
#   and analyzes all commits for boundary risk — no manual input.
# ============================================================

# ── Auto-detect system UTC offset (in minutes) ───────────────
#   Returns e.g. "+330" for IST, "-300" for EST
utc_detect_offset() {
  # Works on GNU date and BSD date
  TZ_OFFSET_MIN=$(date +%z | awk '{
    sign=substr($0,1,1)=="+"?1:-1
    h=substr($0,2,2)+0
    m=substr($0,4,2)+0
    printf "%d", sign*(h*60+m)
  }')
  export TZ_OFFSET_MIN
  TZ_NAME=$(date +%Z)
  export TZ_NAME
}

# ── Classify a UTC hour as boundary-risky ────────────────────
#   utc_is_boundary_risky <utc_hour> <offset_min>
#   Boundary = commit's local time is between midnight and
#   the moment the UTC day flips (|offset| / 60 hours into local day)
utc_is_boundary_risky() {
  # Strip leading zeros before arithmetic — bash treats 08/09 as invalid octal
  local utc_h=$(( 10#${1} )) offset_min="$2"
  # Convert commit's UTC hour to local hour
  local local_h=$(( (utc_h * 60 + offset_min) / 60 % 24 ))
  # If local time is between 0 and the "safe margin" hour
  local safe_margin=$(( (offset_min < 0 ? -offset_min : offset_min) / 60 + 1 ))
  [ "$local_h" -ge 0 ] && [ "$local_h" -lt "$safe_margin" ]
}

# ── Full auto-UTC analysis across all repos ───────────────────
#   auto_utc_analysis "$BASE_PATH" "$CORRECT_EMAIL"
auto_utc_analysis() {
  local base="$1" email="$2"

  utc_detect_offset

  section "AUTO UTC ANALYSIS"

  local offset_h; offset_h=$(echo "scale=1; $TZ_OFFSET_MIN / 60" | bc 2>/dev/null || echo "?")
  info "System timezone : ${BOLD}${TZ_NAME}${RESET} (UTC${TZ_OFFSET_MIN:0:1}$(echo "$offset_h" | sed 's/-//')h)"
  info "Current UTC     : $(date -u '+%Y-%m-%d %H:%M:%S')"
  info "Current Local   : $(date '+%Y-%m-%d %H:%M:%S %Z')"

  # Warn about high-risk offset zones
  local abs_offset; abs_offset=${TZ_OFFSET_MIN#-}
  if [ "$abs_offset" -ge 270 ]; then   # ≥ 4.5h offset
    warn "High UTC offset (${TZ_NAME}) — boundary risk is elevated"
    echo -e "  ${DIM}  Commits within $(( abs_offset / 60 + 1 ))h of local midnight cross UTC day boundary.${RESET}"
  fi

  local -a risky_commits
  local total_checked=0
  local total_risky=0

  for repo in "$base"/*/; do
    [ -d "$repo/.git" ] || continue
    local rname; rname=$(basename "$repo")

    while IFS='|' read -r hash utc_ts_raw author_email; do
      [ -z "$hash" ] && continue
      author_email=$(echo "$author_email" | xargs)
      [ "$author_email" != "$email" ] && continue

      ((total_checked++))

      # Extract UTC hour from timestamp
      local utc_h; utc_h=$(date -d "@$utc_ts_raw" -u +%H 2>/dev/null || \
                            date -r "$utc_ts_raw"  -u +%H 2>/dev/null)
      [ -z "$utc_h" ] && continue

      if utc_is_boundary_risky "$utc_h" "$TZ_OFFSET_MIN"; then
        ((total_risky++))
        local utc_pretty; utc_pretty=$(date -d "@$utc_ts_raw" -u '+%Y-%m-%d %H:%M UTC' 2>/dev/null || \
                                       date -r "$utc_ts_raw"  -u '+%Y-%m-%d %H:%M UTC' 2>/dev/null)
        local loc_pretty; loc_pretty=$(date -d "@$utc_ts_raw"    '+%Y-%m-%d %H:%M %Z'  2>/dev/null || \
                                       date -r "$utc_ts_raw"     '+%Y-%m-%d %H:%M %Z'  2>/dev/null)
        risky_commits+=("  ${YELLOW}$rname${RESET}  $hash  |  $utc_pretty  |  local: $loc_pretty")
      fi
    done < <(git -C "$repo" log \
      --pretty=format:"%h|%at|%ae" 2>/dev/null)
  done

  echo -e "\n  Commits analyzed : ${BOLD}$total_checked${RESET}"
  echo -e "  Boundary-risky   : ${BOLD}${total_risky}${RESET}"

  if [ "$total_risky" -eq 0 ]; then
    ok "No boundary-risky commits found — all contributions should count on the correct day"
  else
    fail "$total_risky commit(s) land on the wrong UTC day due to timezone offset"
    echo -e "\n  ${BOLD}Affected commits:${RESET}"
    for c in "${risky_commits[@]:0:15}"; do   # cap display at 15
      echo -e "    $c"
    done
    [ "${#risky_commits[@]}" -gt 15 ] && \
      echo -e "    ${DIM}... and $((total_risky - 15)) more — see report file${RESET}"
    echo -e "\n  ${DIM}→ Run fix_timezone.sh to shift these commits to the correct UTC day.${RESET}"
  fi

  # Boundary window info
  local window_h; window_h=$(( abs_offset / 60 ))
  local window_m; window_m=$(( abs_offset % 60 ))
  echo -e "\n  ${DIM}Boundary window: commits made locally between 00:00 and ${window_h}:${window_m#-} ${TZ_NAME}"
  echo -e "  will appear on the previous UTC day on GitHub.${RESET}"
}

# ── Quick single-repo UTC scan (used by validator) ────────────
#   utc_scan_repo   (call from inside the repo dir)
utc_scan_repo() {
  utc_detect_offset

  local boundary_count=0
  while IFS= read -r utc_ts_raw; do
    [ -z "$utc_ts_raw" ] && continue
    local utc_h; utc_h=$(date -d "@$utc_ts_raw" -u +%H 2>/dev/null || \
                          date -r "$utc_ts_raw"  -u +%H 2>/dev/null)
    # Strip leading zero so bash doesn't treat 08/09 as invalid octal
    utc_h=$(( 10#${utc_h} ))
    utc_is_boundary_risky "$utc_h" "$TZ_OFFSET_MIN" && ((boundary_count++))
  done < <(git log --pretty=format:"%at" 2>/dev/null)

  if [ "$boundary_count" -gt 0 ]; then
    warn "$boundary_count commit(s) in UTC boundary zone — may count on wrong day (auto-detected: ${TZ_NAME})"
  else
    ok "UTC boundary analysis clean (auto-detected: ${TZ_NAME})"
  fi
}