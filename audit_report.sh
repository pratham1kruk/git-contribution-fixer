#!/bin/bash

echo "===== Git Email Audit Tool ====="

# Ask inputs
read -p "Enter base directory path (e.g. /mnt/d/git): " BASE_PATH
read -p "Enter your correct GitHub email: " CORRECT_EMAIL

OUTPUT_FILE="repo_email_report_$(date +%Y%m%d_%H%M%S).txt"

cd "$BASE_PATH" || exit

echo "Git Email Audit Report" > "$OUTPUT_FILE"
echo "==========================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for repo in */; do
  if [ -d "$repo/.git" ]; then
    echo "🔍 Checking repo: $repo"
    cd "$repo"

    echo "Repo: $repo" >> "../$OUTPUT_FILE"
    echo "Remote: $(git remote get-url origin 2>/dev/null)" >> "../$OUTPUT_FILE"

    echo "Commit Email Distribution:" >> "../$OUTPUT_FILE"
    git log --pretty=format:"%ae" | sort | uniq -c >> "../$OUTPUT_FILE"

    WRONG_COUNT=$(git log --pretty=format:"%ae" | grep -c -v "$CORRECT_EMAIL")

    if [ "$WRONG_COUNT" -gt 0 ]; then
      echo "❌ WARNING: $WRONG_COUNT commits with wrong email" >> "../$OUTPUT_FILE"
    else
      echo "✅ All commits valid" >> "../$OUTPUT_FILE"
    fi

    echo "" >> "../$OUTPUT_FILE"
    echo "-----------------------------" >> "../$OUTPUT_FILE"
    echo "" >> "../$OUTPUT_FILE"

    cd ..
  fi
done

echo "✅ Report saved to: $BASE_PATH/$OUTPUT_FILE"