#!/bin/bash
# ============================================================
#   colors.sh  — Shared color & print helpers
#   Feature 1: Colored CLI output (consistent across all scripts)
#   Source this file:  source "$(dirname "$0")/colors.sh"
# ============================================================

# ── Palette ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
RESET='\033[0m'

# ── Print helpers ─────────────────────────────────────────────
ok()      { echo -e "  ${GREEN}✅ PASS${RESET}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $*"; }
fail()    { echo -e "  ${RED}❌ FAIL${RESET}  $*"; }
info()    { echo -e "  ${CYAN}ℹ️  INFO${RESET}  $*"; }
step()    { echo -e "\n${CYAN}🔍 $*${RESET}"; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────────────────${RESET}"; }
header()  {
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════════════════════════╗"
  printf "║  %-52s  ║\n" "$1"
  printf "║  %-52s  ║\n" "$2"
  echo "╚══════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

# Strip ANSI codes (for writing to files)
strip_color() { sed 's/\x1b\[[0-9;]*m//g'; }
