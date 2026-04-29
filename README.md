# 🔧 git-identity-fixer

> A DevOps-style toolkit for auditing and fixing Git commit identity across multiple repositories — so your GitHub contributions are always counted correctly.

---

## 🚨 The Problem

You commit regularly, but your GitHub contribution graph shows gaps. Your streak is broken. Work that took real effort simply doesn't appear.

**Why?** GitHub only counts a commit as a contribution if the commit's author email **exactly matches** a verified email on your GitHub account.

A common culprit:

```
hp@RelevantGuy.localdomain   ← local system default, not your GitHub email
```

This means:
- ❌ Commits are ignored by GitHub
- ❌ Contribution streak breaks
- ❌ Graph stays empty despite real work

---

## 🔍 Root Cause Summary

| Issue | Impact |
|-------|--------|
| Commits authored with local system email | Not counted as contributions |
| Multiple repos pointing to same remote | History mismatch |
| No global Git identity configured | Wrong email used silently |
| UTC vs IST timezone offset | Streak day boundaries shift |

---

## 🛠️ What This Toolkit Does

### 1. `audit_report.sh` — Scan & Report
- Scans all Git repositories in a given directory
- Reports email distribution per repo
- Flags commits made with wrong/unknown emails
- Saves a timestamped audit report file

### 2. `fix_commits.sh` — Rewrite & Fix
- Rewrites commit author/committer email across all repos
- Uses `git filter-branch` to update full history
- Skips repos that don't belong to your GitHub username
- Enforces correct global Git config before making any changes
- Force-pushes corrected history to remote

Both scripts are fully dynamic — no hardcoded paths or emails.

---

## 🚀 Usage

### Step 1: Audit Your Repos

```bash
bash audit_report.sh
```

You'll be prompted for:
- Base directory path (e.g. `/mnt/d/git`)
- Your correct GitHub email

A report file like `repo_email_report_20260429_200000.txt` will be generated.

### Step 2: Fix Commit History

```bash
bash fix_commits.sh
```

You'll be prompted for:
- Base directory path
- Old (wrong) email to replace
- GitHub username
- Correct GitHub email
- Your name

The script will:
1. Verify/set your global Git config
2. Scan each repo
3. Rewrite history where the old email is found
4. Force-push corrected commits to GitHub

---

## 📋 Requirements

- Git (with `filter-branch` support)
- Bash shell (Linux / macOS / WSL on Windows)
- Push access to your GitHub repositories

---

## ⚠️ Important Notes

> **Rewriting history is destructive.** This toolkit uses `git push --force`, which rewrites the remote branch. Only run this on repositories you own.

- Collaborators will need to re-clone or rebase after a force push
- GitHub may take a few minutes to update the contribution graph
- Streak recovery depends on commit timestamps — past gaps won't be recovered retroactively, but future commits will count correctly
- UTC timezone affects streak day boundaries; commits near midnight IST may fall on a different UTC date

---

## 🔄 Step-by-Step: How the Fix Works

```
1. Identify wrong email in commits
   └─ git log --pretty=format:"%ae"

2. Run audit_report.sh to get a full picture

3. Run fix_commits.sh to rewrite history

4. git filter-branch rewrites author/committer email

5. Force push updated commits to GitHub

6. Verify on GitHub profile → Contributions graph
```

---

## 📁 Project Structure

```
git-contribution-fixer/
├── audit_report.sh     # Scan repos and generate email audit report
├── fix_commits.sh      # Rewrite commit history with correct email
├── .gitignore
└── .vbcignore
```

---

## 💡 Key Takeaways

- GitHub contributions are tied to **commit email**, not username
- Always configure Git identity before your first commit:
  ```bash
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  ```
- Rewriting history requires a force push — communicate with collaborators first
- Automation prevents this issue from recurring

---

## 📈 Outcome After Running the Toolkit

- ✅ All commits linked to correct GitHub identity  
- ✅ Contributions start appearing on your profile  
- ✅ Consistent, clean repository history  
- ✅ Global Git config enforced for future commits  
- ✅ Reusable scripts for ongoing maintenance  

---

## 📄 License

MIT — free to use, modify, and share.

---

*Built to solve a real-world problem. If this saved your streak, give it a ⭐*