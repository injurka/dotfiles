# Git shortcuts carried over from the active Zsh configuration.
# Branch helpers mirror the Zsh git plugin behavior used by dynamic aliases.

function git_current_branch
    set -l ref (command git symbolic-ref --quiet HEAD 2>/dev/null)
    if test $status -ne 0
        set ref (command git rev-parse --short HEAD 2>/dev/null); or return
    end
    string replace --regex "^refs/heads/" "" -- $ref
end

function git_main_branch
    command git rev-parse --git-dir >/dev/null 2>&1; or return
    for location in refs/heads refs/remotes/origin refs/remotes/upstream
        for branch in main trunk mainline default stable master
            if command git show-ref --quiet --verify "$location/$branch"
                echo $branch
                return 0
            end
        end
    end
    for remote in origin upstream
        set -l ref (command git rev-parse --abbrev-ref "$remote/HEAD" 2>/dev/null)
        if string match --quiet -- "$remote/*" $ref
            string replace -- "$remote/" "" -- $ref
            return 0
        end
    end
    echo master
    return 1
end

function git_develop_branch
    command git rev-parse --git-dir >/dev/null 2>&1; or return
    for branch in dev devel develop development
        if command git show-ref --quiet --verify "refs/heads/$branch"
            echo $branch
            return 0
        end
    end
    echo develop
    return 1
end

# The original Zsh function accepted an optional tag prefix.
function gtl
    set -l prefix "*"
    if set -q argv[1]
        set prefix "$argv[1]*"
    end
    command git tag --sort=-v:refname -n --list "$prefix"
end

# Fish backgrounds these GUI commands with &, matching the Zsh aliases.
function gk
    command gitk --all --branches $argv &
end
function gke
    command gitk --all (command git log --walk-reflogs --pretty=%h) $argv &
end

alias 'glgga' 'git log --graph --decorate --all'
alias 'gcsm' 'git commit --signoff --message'
alias 'gbsb' 'git bisect bad'
alias 'groh' 'git reset origin/$(git_current_branch) --hard'
alias 'gcss' 'git commit --gpg-sign --signoff'
alias 'gbsg' 'git bisect good'
alias 'gbsn' 'git bisect new'
alias 'gbso' 'git bisect old'
alias 'gds' 'git diff --staged'
alias 'gbsr' 'git bisect reset'
alias 'gignored' 'git ls-files -v | grep "^[[:lower:]]"'
alias 'gdt' 'git diff-tree --no-commit-id --name-only -r'
alias 'gbss' 'git bisect start'
alias 'gdw' 'git diff --word-diff'
alias 'gpod' 'git push origin --delete'
alias 'gpd' 'git push --dry-run'
alias 'gsps' 'git show --pretty=short --show-signature'
alias 'gpf' 'git push --force-with-lease --force-if-includes'
alias 'gpf!' 'git push --force'
alias 'glola' 'git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all'
alias 'gpr' 'git pull --rebase'
alias 'gpu' 'git push upstream'
alias 'gpv' 'git push --verbose'
alias 'gcans!' 'git commit --verbose --all --signoff --no-edit --amend'
alias 'gdup' 'git diff @{upstream}'
alias 'gwtls' 'git worktree list'
alias 'glols' 'git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --stat'
alias 'grev' 'git revert'
alias 'gca!' 'git commit --verbose --all --amend'
alias 'gfa' 'git fetch --all --tags --prune --jobs=10'
alias 'gfg' 'git ls-files | grep'
alias 'gpristine' 'git reset --hard && git clean --force -dfx'
alias 'gfo' 'git fetch origin'
alias 'gmom' 'git merge origin/$(git_main_branch)'
alias 'gwta' 'git worktree add'
alias 'gwtmv' 'git worktree move'
alias 'glod' 'git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset"'
alias 'g' 'git'
alias 'glog' 'git log --oneline --decorate --graph'
alias 'gra' 'git remote add'
alias 'grb' 'git rebase'
alias 'glol' 'git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
alias 'grf' 'git reflog'
alias 'gga' 'git gui citool --amend'
alias 'grh' 'git reset'
alias 'grset' 'git remote set-url'
alias 'grm' 'git rm'
alias 'gwip' 'git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
alias 'grrm' 'git remote remove'
alias 'gclean' 'git clean --interactive -d'
alias 'grs' 'git restore'
alias 'gru' 'git reset --'
alias 'ggpush' 'git push origin "$(git_current_branch)"'
alias 'grv' 'git remote --verbose'
alias 'greva' 'git revert --abort'
alias 'grevc' 'git revert --continue'
alias 'gcn!' 'git commit --verbose --no-edit --amend'
alias 'gpra' 'git pull --rebase --autostash'
alias 'gamscp' 'git am --show-current-patch'
alias 'gsb' 'git status --short --branch'
alias 'gclf' 'git clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'
alias 'gsd' 'git svn dcommit'
alias 'gsh' 'git show'
alias 'gsi' 'git submodule init'
alias 'ghh' 'git help'
alias 'gcam' 'git commit --all --message'
alias 'grhh' 'git reset --hard'
alias 'gsr' 'git svn rebase'
alias 'grhk' 'git reset --keep'
alias 'gss' 'git status --short'
alias 'grbum' 'git rebase upstream/$(git_main_branch)'
alias 'gst' 'git status'
alias 'gcas' 'git commit --all --signoff'
alias 'gsu' 'git submodule update'
alias 'gsta' 'git stash push'
alias 'grss' 'git restore --source'
alias 'gpsup' 'git push --set-upstream origin $(git_current_branch)'
alias 'gprv' 'git pull --rebase -v'
alias 'grst' 'git restore --staged'
alias 'gmff' 'git merge --ff-only'
alias 'gsw' 'git switch'
alias 'gstc' 'git stash clear'
alias 'gstd' 'git stash drop'
alias 'grhs' 'git reset --soft'
alias 'glods' 'git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset" --date=short'
alias 'gstl' 'git stash list'
alias 'gprum' 'git pull --rebase upstream $(git_main_branch)'
alias 'gcasm' 'git commit --all --signoff --message'
alias 'gta' 'git tag --annotate'
alias 'gstp' 'git stash pop'
alias 'gsts' 'git stash show --patch'
alias 'gstall' 'git stash --all'
alias 'ga' 'git add'
alias 'gb' 'git branch'
alias 'gc' 'git commit --verbose'
alias 'gd' 'git diff'
alias 'gf' 'git fetch'
alias 'gts' 'git tag --sign'
alias 'gg' 'git gui citool'
alias 'git-svn-dcommit-push' 'git svn dcommit && git push github $(git_main_branch):svntrunk'
alias 'gdca' 'git diff --cached'
alias 'gstaa' 'git stash apply'
alias 'gtv' 'git tag | sort -V'
alias 'gl' 'git pull'
alias 'gm' 'git merge'
alias 'gpsupf' 'git push --set-upstream origin $(git_current_branch) --force-with-lease --force-if-includes'
alias 'ggsup' 'git branch --set-upstream-to=origin/$(git_current_branch)'
alias 'gama' 'git am --abort'
alias 'gp' 'git push'
alias 'gamc' 'git am --continue'
alias 'gr' 'git remote'
alias 'glgg' 'git log --graph'
alias 'gdct' 'git describe --tags $(git rev-list --tags --max-count=1)'
alias 'gdcw' 'git diff --cached --word-diff'
alias 'glgm' 'git log --graph --max-count=10'
alias 'gams' 'git am --skip'
alias 'glgp' 'git log --stat --patch'
alias 'grup' 'git remote update'
alias 'gprumi' 'git pull --rebase=interactive upstream $(git_main_branch)'
alias 'gbnm' 'git branch --no-merged'
alias 'gunwip' 'git rev-list --max-count=1 --format="%s" HEAD | grep -q "\\--wip--" && git reset HEAD~1'
alias 'gignore' 'git update-index --assume-unchanged'
alias 'gloga' 'git log --oneline --decorate --graph --all'
alias 'gcor' 'git checkout --recurse-submodules'
alias 'gprav' 'git pull --rebase --autostash -v'
alias 'gwtrm' 'git worktree remove'
alias 'gswc' 'git switch --create'
alias 'gmtl' 'git mergetool --no-prompt'
alias 'gswd' 'git switch $(git_develop_branch)'
alias 'gcann!' 'git commit --verbose --all --date=now --no-edit --amend'
alias 'ggpull' 'git pull origin "$(git_current_branch)"'
alias 'gcpa' 'git cherry-pick --abort'
alias 'gcssm' 'git commit --gpg-sign --signoff --message'
alias 'gcpc' 'git cherry-pick --continue'
alias 'gswm' 'git switch $(git_main_branch)'
alias 'gwch' 'git log --patch --abbrev-commit --pretty=medium --raw'
alias 'gaa' 'git add --all'
alias 'glg' 'git log --stat'
alias 'gc!' 'git commit --verbose --amend'
alias 'gbD' 'git branch --delete --force'
alias 'gwt' 'git worktree'
alias 'glo' 'git log --oneline --decorate'
alias 'gam' 'git am'
alias 'gmum' 'git merge upstream/$(git_main_branch)'
alias 'gap' 'git apply'
alias 'gapa' 'git add --patch'
alias 'gcan!' 'git commit --verbose --all --no-edit --amend'
alias 'gpoat' 'git push origin --all && git push origin --tags'
alias 'gluc' 'git pull upstream $(git_current_branch)'
alias 'gau' 'git add --update'
alias 'gav' 'git add --verbose'
alias 'gcount' 'git shortlog --summary --numbered'
alias 'gma' 'git merge --abort'
alias 'glum' 'git pull upstream $(git_main_branch)'
alias 'gmc' 'git merge --continue'
alias 'grmc' 'git rm --cached'
alias 'gba' 'git branch --all'
alias 'grba' 'git rebase --abort'
alias 'gcB' 'git checkout -B'
alias 'gapt' 'git apply --3way'
alias 'gbd' 'git branch --delete'
alias 'grbc' 'git rebase --continue'
alias 'gpromi' 'git pull --rebase=interactive origin $(git_main_branch)'
alias 'grbd' 'git rebase $(git_develop_branch)'
alias 'gbg' 'LANG=C git branch -vv | grep ": gone\\]"'
alias 'grbi' 'git rebase --interactive'
alias 'gbgD' 'LANG=C git branch --no-color -vv | grep ": gone\\]" | cut -c 3- | awk \'{print $1}\' | xargs git branch -D'
alias 'gcfu' 'git commit --fixup'
alias 'gbl' 'git blame -w'
alias 'gbm' 'git branch --move'
alias 'grbom' 'git rebase origin/$(git_main_branch)'
alias 'gms' 'git merge --squash'
alias 'grbm' 'git rebase $(git_main_branch)'
alias 'grbo' 'git rebase --onto'
alias 'gbr' 'git branch --remote'
alias 'grmv' 'git remote rename'
alias 'gbs' 'git bisect'
alias 'grbs' 'git rebase --skip'
alias 'gmtlvim' 'git mergetool --no-prompt --tool=vimdiff'
alias 'gprom' 'git pull --rebase origin $(git_main_branch)'
alias 'gca' 'git commit --verbose --all'
alias 'gwipe' 'git reset --hard && git clean --force -df'
alias 'gcb' 'git checkout -b'
alias 'gunignore' 'git update-index --no-assume-unchanged'
alias 'gcd' 'git checkout $(git_develop_branch)'
alias 'gcf' 'git config --list'
alias 'gcmsg' 'git commit --message'
alias 'gbgd' 'LANG=C git branch --no-color -vv | grep ": gone\\]" | cut -c 3- | awk \'{print $1}\' | xargs git branch -d'
alias 'gcl' 'git clone --recurse-submodules'
alias 'gcm' 'git checkout $(git_main_branch)'
alias 'gcn' 'git commit --verbose --no-edit'
alias 'gco' 'git checkout'
alias 'gcp' 'git cherry-pick'
alias 'gcs' 'git commit --gpg-sign'
