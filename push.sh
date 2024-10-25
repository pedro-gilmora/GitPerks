git status | grep -q "rebase in progress" && git rebase --continue && git push --force && echo "Rebase done" || 
git log @{u}..HEAD 2>&1 | grep -q "fatal: no upstream configured" && git push --set-upstream origin $(git branch --show-current) || 
git log @{u}..HEAD 2>&1 | grep -q "commit " && git push --force && echo "All changes were pushed" || 
echo "No changes were pushed"