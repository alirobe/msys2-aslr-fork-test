# A real git workflow through the install's own bash: hooks, a clone, an interactive rebase with editors, an alias.
export PATH=/mingw64/bin:/usr/bin:$PATH HOME=/tmp
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --global core.autocrlf false
rm -rf /tmp/w && mkdir -p /tmp/w && cd /tmp/w || exit 1
git init -q src && cd src || exit 1
printf '#!/bin/sh\necho hook ran >> ../hooklog\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
n=0; i=0; while [ $i -lt 50 ]; do i=$((i+1)); echo $i > f$i; git add f$i; git commit -q -m "c$i" && n=$((n+1)); done
echo "commits: $n/50  hook runs: $(grep -c hook ../hooklog 2>/dev/null)/50"
cd .. && git clone -q src clone && cd clone && echo "clone: $(git rev-list --count HEAD)/50 commits"
echo pick > ../t; sed -i s/^pick/reword/ ../t; echo "standalone sed -i: exit $? content $(cat ../t)"
GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true git rebase -i HEAD~5 > ../rebase0.log 2>&1 && echo "rebase with no-op editors: ok" || { echo "rebase with no-op editors: failed"; tail -3 ../rebase0.log; }
printf '#!/bin/sh
sed -i s/^pick/reword/ "$1"; r=$?; echo "seq editor: sed exit $r" >> /tmp/w/editor.log; exit $r
' > ../seq-editor.sh; chmod +x ../seq-editor.sh
GIT_SEQUENCE_EDITOR=/tmp/w/seq-editor.sh GIT_EDITOR='sed -i s/^c/r/' git rebase -i HEAD~5 > ../rebase.log 2>&1 && echo "rebase with editors: $(git log --format=%s -5 | grep -c ^r)/5 reworded" || { echo "rebase with editors: failed, exit $?"; tail -8 ../rebase.log; cat /tmp/w/editor.log 2>/dev/null; git rebase --abort 2>/dev/null; }
git config alias.hi '!echo hi' && echo "shell alias: $(git hi)"
echo "log via pager pipe: $(git log --oneline | wc -l) lines"
# Editor probes: direct-exec editors and shell-launched ones, with git's structured trace for the child exit code.
printf '#!/bin/sh
echo "marker editor ran: $1" >> /tmp/w/editor.log
' > ../mark-editor.sh; chmod +x ../mark-editor.sh
echo "PATH=$PATH"; for ed in /usr/bin/true /tmp/w/mark-editor.sh 'sed -i s/^pick/pick/' 'sh /tmp/w/mark-editor.sh'; do
  rm -f /tmp/w/editor.log /tmp/w/t2.log
  GIT_SEQUENCE_EDITOR="$ed" GIT_EDITOR=true GIT_TRACE2=/tmp/w/t2.log git rebase -i HEAD~3 > ../r.log 2>&1; r=$?
  echo "editor [$ed]: exit $r; $(head -1 /tmp/w/editor.log 2>/dev/null)"
  grep -aE "child_start|child_exit" /tmp/w/t2.log | grep -av "GIT_EDITOR\|rebase--" | sed 's/^.*child_/  child_/' | head -4
  git rebase --abort >/dev/null 2>&1
done
