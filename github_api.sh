#!/bin/bash
# ============================================================
#   github_api.sh  — GitHub API Verification helpers
#   Feature 3: GitHub API verification
#   Source this file:  source "$(dirname "$0")/github_api.sh"
#
#   Requires: curl
#   jq: prompted for install automatically if not found
#   Set GITHUB_TOKEN (optional) for higher rate limits.
# ============================================================

GH_API="https://api.github.com"

# ── jq: check once at source time, offer to install if missing ──
_JQ_OK=false

_jq_ensure() {
  # Already available — nothing to do
  if command -v jq &>/dev/null; then
    _JQ_OK=true
    return 0
  fi

  # Already asked this session — don't prompt again
  if [ "${_JQ_ASKED:-false}" = true ]; then
    return 1
  fi
  _JQ_ASKED=true

  echo -e "\n  ${YELLOW}⚠️  jq is not installed — needed for GitHub API features${RESET}"
  echo -e "  ${DIM}jq parses JSON responses from the GitHub API.${RESET}"
  read -rp "  Install jq now? (y/n): " _JQ_INSTALL_CHOICE

  if [ "$_JQ_INSTALL_CHOICE" = "y" ]; then
    echo -e "  ${CYAN}Installing jq...${RESET}"

    if command -v apt-get &>/dev/null; then
      sudo apt-get install -y jq
    elif command -v brew &>/dev/null; then
      brew install jq
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm jq
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y jq
    else
      echo -e "  ${RED}❌ Could not detect package manager. Install jq manually:${RESET}"
      echo -e "  ${DIM}  Ubuntu/Debian : sudo apt install jq${RESET}"
      echo -e "  ${DIM}  macOS         : brew install jq${RESET}"
      echo -e "  ${DIM}  Arch          : sudo pacman -S jq${RESET}"
      echo -e "  ${DIM}  Fedora        : sudo dnf install jq${RESET}"
      return 1
    fi

    if command -v jq &>/dev/null; then
      echo -e "  ${GREEN}✅ jq installed successfully${RESET}"
      _JQ_OK=true
      return 0
    else
      echo -e "  ${RED}❌ Installation failed — GitHub API features will be skipped${RESET}"
      return 1
    fi

  else
    echo -e "  ${DIM}Skipping GitHub API features for this session.${RESET}"
    return 1
  fi
}

# Run the check immediately when this file is sourced
_jq_ensure

# ── Internal: curl wrapper ────────────────────────────────────
_gh_get() {
  local url="$GH_API$1"
  local args=(-sf -H "Accept: application/vnd.github+json")
  [ -n "$GITHUB_TOKEN" ] && args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl "${args[@]}" "$url" 2>/dev/null
}

# ── Internal: safe jq wrapper ────────────────────────────────
_jq() { jq "$@" 2>/dev/null; }

# ── Token prompt (called once) ────────────────────────────────
github_prompt_token() {
  echo -e "\n  ${CYAN}GitHub API — optional Personal Access Token${RESET}"
  echo -e "  ${DIM}(Leave blank for unauthenticated — 60 req/hr limit)${RESET}"
  echo -e "  ${DIM}Token needs scopes: read:user, repo${RESET}"
  read -rsp "  Token: " GITHUB_TOKEN
  echo ""
  export GITHUB_TOKEN
}

# ── 1. Verify email is registered on GitHub account ──────────
github_verify_email() {
  local email="$1" username="$2"

  if ! $_JQ_OK; then return 2; fi

  local resp; resp=$(_gh_get "/users/$username")
  if [ -z "$resp" ]; then
    echo -e "  ${YELLOW}⚠️  GitHub API unreachable — skipping email verification${RESET}"
    return 2
  fi

  local api_email; api_email=$(_jq -r '.email // empty' <<< "$resp")
  local api_name;  api_name=$( _jq -r '.name  // empty' <<< "$resp")
  local api_login; api_login=$(_jq -r '.login // empty' <<< "$resp")

  if [ -z "$api_login" ]; then
    echo -e "  ${RED}❌ GitHub user '${username}' not found${RESET}"
    return 1
  fi

  echo -e "  ${GREEN}✅ GitHub user found: ${BOLD}$api_login${RESET}${GREEN} ($api_name)${RESET}"

  if [ "$api_email" = "$email" ]; then
    echo -e "  ${GREEN}✅ Public email matches: ${BOLD}$email${RESET}"
    return 0
  elif [ -z "$api_email" ]; then
    echo -e "  ${YELLOW}⚠️  GitHub public email is hidden — can't verify via API${RESET}"
    echo -e "  ${DIM}Tip: The email still works for contributions even if hidden.${RESET}"
  else
    echo -e "  ${YELLOW}⚠️  Public email mismatch${RESET}"
    echo -e "  ${DIM}  API says : $api_email${RESET}"
    echo -e "  ${DIM}  Expected : $email${RESET}"
  fi
  return 1
}

# ── 2. Get contribution count for today ──────────────────────
github_today_contributions() {
  local username="$1"

  if ! $_JQ_OK; then return 2; fi

  local today; today=$(date -u +%Y-%m-%d)
  local resp; resp=$(_gh_get "/users/$username/events?per_page=100")
  if [ -z "$resp" ]; then
    echo -e "  ${YELLOW}⚠️  Could not fetch events — API unreachable${RESET}"
    return 2
  fi

  local push_count; push_count=$(_jq -r --arg d "$today" \
    '[.[] | select(.type=="PushEvent" and (.created_at | startswith($d)))] | length' <<< "$resp")
  push_count=${push_count:-0}
  echo -e "  ${CYAN}ℹ️  Push events on GitHub today (${today}): ${BOLD}${push_count}${RESET}"
}

# ── 3. Check repo visibility & default branch ────────────────
github_check_repo() {
  local username="$1" reponame="$2"

  if ! $_JQ_OK; then return 2; fi

  local resp; resp=$(_gh_get "/repos/$username/$reponame")

  if [ -z "$resp" ] || _jq -e '.message' <<< "$resp" &>/dev/null; then
    echo -e "  ${YELLOW}⚠️  Repo '$reponame' not found or private (no token?)${RESET}"
    return 1
  fi

  local visibility; visibility=$(_jq -r '.visibility'       <<< "$resp")
  local default_b;  default_b=$( _jq -r '.default_branch'  <<< "$resp")
  local fork;       fork=$(      _jq -r '.fork'             <<< "$resp")
  local stars;      stars=$(     _jq -r '.stargazers_count' <<< "$resp")

  echo -e "  ${GREEN}✅ Repo: ${BOLD}$reponame${RESET}${GREEN} | ${visibility} | branch: ${default_b} | ⭐ ${stars}${RESET}"
  [ "$fork" = "true" ] && echo -e "  ${YELLOW}⚠️  This is a fork — contributions to forks may not count${RESET}"
}

# ── 4. Rate-limit status ──────────────────────────────────────
github_rate_limit() {
  if ! $_JQ_OK; then return 2; fi

  local resp; resp=$(_gh_get "/rate_limit")
  if [ -z "$resp" ]; then
    echo -e "  ${YELLOW}⚠️  Cannot reach GitHub API${RESET}"
    return
  fi

  local remaining; remaining=$(_jq -r '.rate.remaining' <<< "$resp")
  local limit;     limit=$(    _jq -r '.rate.limit'     <<< "$resp")
  local reset_ts;  reset_ts=$( _jq -r '.rate.reset'     <<< "$resp")
  local reset_t;   reset_t=$(date -d "@$reset_ts" '+%H:%M' 2>/dev/null || date -r "$reset_ts" '+%H:%M' 2>/dev/null)

  if [ "$remaining" -lt 10 ]; then
    echo -e "  ${RED}⚠️  GitHub API rate limit low: ${remaining}/${limit} (resets ~${reset_t})${RESET}"
  else
    echo -e "  ${DIM}GitHub API: ${remaining}/${limit} requests remaining (resets ~${reset_t})${RESET}"
  fi
}