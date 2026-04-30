#!/bin/bash

echo "===== Git Email Audit Tool ====="

# Ask inputs
read -p "Enter base directory path (e.g. /mnt/d/git): " BASE_PATH
read -p "Enter your correct GitHub email: " CORRECT_EMAIL

OUTPUT_FILE="repo_email_report_$(date +%Y%m%d_%H%M%S).txt"

# Validate path
if [ ! -d "$BASE_PATH" ]; then
    echo "❌ ERROR: Directory does not exist"
    exit 1
fi

cd "$BASE_PATH" || exit

# Report header
echo "Git Email Audit Report" > "$OUTPUT_FILE"
echo "Generated : $(date)" >> "$OUTPUT_FILE"
echo "Base Path : $BASE_PATH" >> "$OUTPUT_FILE"
echo "Expected Email : $CORRECT_EMAIL" >> "$OUTPUT_FILE"
echo "==========================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Statistics counters
TOTAL_REPOS=0
REPOS_WITH_ISSUES=0
TOTAL_COMMITS=0
TOTAL_WRONG_COMMITS=0

for repo in */; do
  if [ -d "$repo/.git" ]; then

    ((TOTAL_REPOS++))

    echo "🔍 Checking repo: $repo"

    cd "$repo"

    REMOTE_URL=$(git remote get-url origin 2>/dev/null)

    COMMIT_COUNT=$(git log --pretty=format:"%ae" | wc -l)
    WRONG_COUNT=$(git log --pretty=format:"%ae" | grep -c -v "$CORRECT_EMAIL")

    ((TOTAL_COMMITS += COMMIT_COUNT))
    ((TOTAL_WRONG_COMMITS += WRONG_COUNT))

    echo "Repo: $repo" >> "../$OUTPUT_FILE"
    echo "Remote: $REMOTE_URL" >> "../$OUTPUT_FILE"
    echo "Current Branch: $(git branch --show-current)" >> "../$OUTPUT_FILE"

    echo "Latest Commit:" >> "../$OUTPUT_FILE"
    git log -1 --pretty=format:"  Hash  : %h%n  Author: %an%n  Email : %ae%n  ISO   : %ad" --date=iso >> "../$OUTPUT_FILE"

    echo "" >> "../$OUTPUT_FILE"
    echo "Latest Commit UTC Time:" >> "../$OUTPUT_FILE"
    git log -1 --pretty=format:"  %ad" --date=utc >> "../$OUTPUT_FILE"

    echo "" >> "../$OUTPUT_FILE"
    echo "Total Commits: $COMMIT_COUNT" >> "../$OUTPUT_FILE"

    echo "Commit Email Distribution:" >> "../$OUTPUT_FILE"
    git log --pretty=format:"%ae" | sort | uniq -c >> "../$OUTPUT_FILE"

    if [ "$WRONG_COUNT" -gt 0 ]; then
      ((REPOS_WITH_ISSUES++))
      echo "❌ WARNING: $WRONG_COUNT commits with wrong email" >> "../$OUTPUT_FILE"
    else
      echo "✅ All commits valid" >> "../$OUTPUT_FILE"
    fi

    echo "" >> "../$OUTPUT_FILE"
    echo "Git Status:" >> "../$OUTPUT_FILE"
    git status -sb >> "../$OUTPUT_FILE"

    echo "" >> "../$OUTPUT_FILE"
    echo "-----------------------------" >> "../$OUTPUT_FILE"
    echo "" >> "../$OUTPUT_FILE"

    cd ..
  fi
done

# Final Summary
echo "" >> "$OUTPUT_FILE"
echo "==================================================" >> "$OUTPUT_FILE"
echo "SUMMARY" >> "$OUTPUT_FILE"
echo "==================================================" >> "$OUTPUT_FILE"
echo "Repos Scanned        : $TOTAL_REPOS" >> "$OUTPUT_FILE"
echo "Repos With Issues    : $REPOS_WITH_ISSUES" >> "$OUTPUT_FILE"
echo "Clean Repos          : $((TOTAL_REPOS - REPOS_WITH_ISSUES))" >> "$OUTPUT_FILE"
echo "Total Commits Scanned: $TOTAL_COMMITS" >> "$OUTPUT_FILE"
echo "Wrong Commits Found  : $TOTAL_WRONG_COMMITS" >> "$OUTPUT_FILE"

echo ""
echo "=================================================="
echo "Repos Scanned        : $TOTAL_REPOS"
echo "Repos With Issues    : $REPOS_WITH_ISSUES"
echo "Clean Repos          : $((TOTAL_REPOS - REPOS_WITH_ISSUES))"
echo "Total Commits Scanned: $TOTAL_COMMITS"
echo "Wrong Commits Found  : $TOTAL_WRONG_COMMITS"
echo "=================================================="

echo "✅ Report saved to: $BASE_PATH/$OUTPUT_FILE"