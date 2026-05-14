<div align="center">

```
██████╗ ██╗████████╗       ██╗██████╗ ███████╗███╗   ██╗████████╗██╗████████╗██╗   ██╗
██╔════╝ ██║╚══██╔══╝      ██║██╔══██╗██╔════╝████╗  ██║╚══██╔══╝██║╚══██╔══╝╚██╗ ██╔╝
██║  ███╗██║   ██║   █████╗██║██║  ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║    ╚████╔╝
██║   ██║██║   ██║   ╚════╝██║██║  ██║██╔══╝  ██║╚██╗██║   ██║   ██║   ██║     ╚██╔╝
╚██████╔╝██║   ██║         ██║██████╔╝███████╗██║ ╚████║   ██║   ██║   ██║      ██║
 ╚═════╝ ╚═╝   ╚═╝         ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   ╚═╝      ╚═╝
                          F  I  X  E  R
```

**Your GitHub contribution graph should reflect your real work.**
*This toolkit makes sure it does.*

[![Shell](https://img.shields.io/badge/Shell-Bash-89e051?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-2ea44f?style=flat-square)](https://github.com)
[![GitHub](https://img.shields.io/badge/GitHub-API%20Ready-238636?style=flat-square&logo=github)](https://api.github.com)
[![License](https://img.shields.io/badge/License-MIT-3fb950?style=flat-square)](LICENSE)

</div>

---

## 🟢 The Problem

You commit every day. GitHub shows gaps.

The reason is almost always one of these:

| Root Cause | Effect on GitHub |
|---|---|
| Wrong author email in commits | Commits invisible to your profile |
| Local system email (`hp@RelevantGuy.localdomain`) | Never counted as contributions |
| IST commits between 12:00 AM – 5:29 AM | Appear on the **previous** UTC day |
| Unpushed commits | Never reach GitHub at all |
| Fork repositories | Contributions may not count |

This toolkit finds all of these, fixes them, and keeps them fixed.

---

## 🟢 What It Does

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   Scan all repos  →  Find bad emails / UTC issues       │
│         ↓                                               │
│   Rewrite commit history with correct identity          │
│         ↓                                               │
│   Fix near-midnight commits to the right UTC day        │
│         ↓                                               │
│   Validate everything  →  Force push to GitHub          │
│         ↓                                               │
│   Monitor live via dashboard  →  Stay streak-safe       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🟢 Scripts at a Glance

| Script | What it does |
|---|---|
| `audit_report.sh` | Scans every repo, finds wrong emails, exports TXT + JSON report |
| `fix_commits.sh` | Rewrites commit history across all repos with the correct email |
| `fix_timezone.sh` | Shifts near-midnight IST commits to the correct UTC day |
| `git-contribution-validator.sh` | Full 7-section diagnostic check per repo |
| `dashboard.sh` | Live terminal dashboard — heatmap, streak safety, repo status |

---

## 🟢 Quick Start

### Step 1 — Audit your repos
```bash
bash audit_report.sh
```
Enter your base directory (e.g. `/mnt/d/git`) and your GitHub email.
A `.txt` and `.json` report are saved automatically.

### Step 2 — Fix wrong emails
```bash
bash fix_commits.sh
```
Rewrites commit author/committer email across every repo that needs it.
Always do a **dry run first** when prompted — it shows what would change without touching anything.

### Step 3 — Fix timezone boundary commits
```bash
bash fix_timezone.sh
```
Auto-detects your UTC offset. Shifts commits that fell on the wrong UTC day.

### Step 4 — Validate
```bash
bash git-contribution-validator.sh
```
Runs 7 checks per repo: identity, commit emails, branch, push sync, time, contribution stats, and repo integrity.

### Step 5 — Monitor
```bash
bash dashboard.sh
```
Live-updating terminal view of all repos, today's commits, streak safety, and GitHub API stats.

---

## 🟢 Dashboard

```
╔══════════════════════════════════════════════════════════════════════════╗
║  🔧 git-contribution-fixer  DASHBOARD                                        ║
║     2026-05-11 11:30:00 IST  |  2026-05-11 06:00:00 UTC                 ║
╚══════════════════════════════════════════════════════════════════════════╝

  📡 GitHub API — 58/60 requests  |  Push events today: 3

  📊 Repository Status
  REPO                     COMMITS   TODAY   ISSUES   SYNC
  ──────────────────────────────────────────────────────────
  my-project               142       2       0        ✓ synced
  side-project             38        0       3        ↑ ahead

  🔥 Streak Safety  ✅  2 commits today — streak is safe

  📅 Last 14 Days
  Mon   Tue   Wed   Thu   Fri   Sat   Sun  ...
   ██    ░░    ▓▓    ··    ██    ··    ░░

  [a] audit  [f] fix_commits  [t] fix_timezone  [s] save report  [q] quit  [r] refresh
```

---

## 🟢 Report Output

Every script saves two files on each run:

```
audit_report_20260511_113000.txt    ← human readable
audit_report_20260511_113000.json   ← machine readable for CI / dashboards
```

The JSON report structure:
```json
{
  "meta": { "script": "audit_report", "generated": "2026-05-11T..." },
  "summary": { "repos_scanned": 20, "wrong_commits_found": 5 },
  "repos": [
    { "repo": "my-project", "status": "CLEAN", "total_commits": 142 }
  ]
}
```

---

## 🟢 Requirements

| Tool | Purpose | Required? |
|---|---|---|
| `git` | All operations | ✅ Yes |
| `git-filter-repo` | Rewriting commit history | ✅ For fix scripts |
| `bash 4+` | Running all scripts | ✅ Yes |
| `python3` | Timezone fix callback | ✅ For fix_timezone.sh |
| `curl` | GitHub API calls | ⚡ For API features |
| `jq` | JSON parsing (auto-install prompted) | ⚡ For API features |
| `bc` | Prediction percentages | ○ Optional |

Install `git-filter-repo`:
```bash
sudo apt install git-filter-repo   # Ubuntu / WSL
pip install git-filter-repo        # via pip
```

---

## 🟢 Safety

> ⚠️ **Rewriting history is destructive.** `fix_commits.sh` and `fix_timezone.sh` use `git push --force`.

- Every fix script asks for a **dry run** before making changes
- Streak safety warning fires before any destructive operation
- The validator lets you check everything without modifying anything
- Only run on repositories **you own**

---

## 🟢 Project Structure

```
git-contribution-fixer/
│
├── 📋 MAIN SCRIPTS
│   ├── audit_report.sh              ← scan & report
│   ├── fix_commits.sh               ← rewrite email history
│   ├── fix_timezone.sh              ← fix UTC boundary commits
│   ├── git-contribution-validator.sh← full diagnostics
│   └── dashboard.sh                 ← live terminal monitor
│
└── 🔧 SHARED MODULES (sourced automatically)
    ├── colors.sh                    ← colored output & print helpers
    ├── report.sh                    ← TXT + JSON dual report writer
    ├── github_api.sh                ← GitHub API verification
    ├── streak.sh                    ← prediction + streak warnings
    └── utc_analysis.sh              ← auto UTC boundary detection
```

---

## 🟢 License

MIT — free to use, modify, and share.

*Built to solve a real problem. If this saved your streak, give it a* ⭐