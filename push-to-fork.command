#!/bin/zsh
# Double-click to push the AtollMixer fork to github.com/Aatricks/Atoll.
# Remotes and commits are already prepared; this only runs `git push`.
cd "$(dirname "$0")"
echo "Pushing to $(git remote get-url origin) ..."
git push -u origin main
status=$?
if [ $status -eq 0 ]; then
  echo ""
  echo "✅ Pushed. Branch main is on your fork."
else
  echo ""
  echo "❌ Push failed (exit $status)."
  echo "If it complained about authentication: run 'gh auth login' or push once"
  echo "from any git GUI so macOS stores your GitHub credentials, then retry."
  echo "If it complained about non-fast-forward: rerun with --force:"
  echo "    git push -u origin main --force"
fi
echo ""
read -k 1 "?Press any key to close..."
