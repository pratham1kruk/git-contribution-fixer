#!/bin/bash

echo "===== Git Commit Email Fix Tool ====="

# Ask inputs
read -p "Enter base directory path (e.g. /mnt/d/git): " BASE_PATH
read -p "Enter OLD email to replace: " OLD_EMAIL
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -p "Enter correct GitHub email: " CORRECT_EMAIL
read -p "Enter your name: " CORRECT_NAME

# Force user to set global email
CURRENT_EMAIL=$(git config --global user.email)

if [ "$CURRENT_EMAIL" != "$CORRECT_EMAIL" ]; then
  echo "⚠️ Your global git email is not set correctly."
  read -p "Set global email to $CORRECT_EMAIL? (y/n): " choice
  if [ "$choice" = "y" ]; then
    git config --global user.email "$CORRECT_EMAIL"
    git config --global user.name "$CORRECT_NAME"
    echo "✅ Global Git config updated"
  else
    echo "❌ Please set correct email before continuing"
    exit 1
  fi
fi

cd "$BASE_PATH" || exit

for repo in */; do
  if [ -d "$repo/.git" ]; then
    echo "🔍 Checking repo: $repo"
    cd "$repo"

    REMOTE_URL=$(git remote get-url origin 2>/dev/null)

    if [[ "$REMOTE_URL" != *"$GITHUB_USERNAME"* ]]; then
      echo "⏭️ Skipping (not your repo)"
      cd ..
      continue
    fi

    COUNT=$(git log --pretty=format:"%ae" | grep -c "$OLD_EMAIL")

    if [ "$COUNT" -gt 0 ]; then
      echo "⚠️ Found $COUNT wrong commits. Fixing..."

      git filter-branch --env-filter "
      if [ \"\$GIT_COMMITTER_EMAIL\" = \"$OLD_EMAIL\" ]
      then
          export GIT_COMMITTER_NAME=\"$CORRECT_NAME\"
          export GIT_COMMITTER_EMAIL=\"$CORRECT_EMAIL\"
      fi
      if [ \"\$GIT_AUTHOR_EMAIL\" = \"$OLD_EMAIL\" ]
      then
          export GIT_AUTHOR_NAME=\"$CORRECT_NAME\"
          export GIT_AUTHOR_EMAIL=\"$CORRECT_EMAIL\"
      fi
      " --tag-name-filter cat -- --branches --tags

      echo "🚀 Force pushing..."
      git push --force

      echo "✅ Fixed: $repo"
    else
      echo "✅ No issues in: $repo"
    fi

    cd ..
    echo "-----------------------------"
  fi
done

echo "🎉 All done!"