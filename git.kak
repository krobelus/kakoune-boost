remove-hooks global boost-git

## Clipboard
# TODO Replace/move this.
declare-option str clipboard_copy_cmd wl-copy
define-command -override clipboard-yank %{
    execute-keys -draft %{,y<a-|>"${kak_opt_clipboard_copy_cmd}" >/dev/null 2>&1<ret>}
}

# Github issue #5048
define-command -override git-jump -docstring %{
    If inside a diff, run git-diff-goto-source,
    Else show the Git object at cursor.
} %{ evaluate-commands -save-regs c %{
    try %{
        execute-keys -draft l[px<a-k>^diff<ret>
        set-register c git-diff-goto-source
    } catch %{
        execute-keys -draft x<a-k> "^Staged changes$" <ret>
        set-register c git diff --staged
    } catch %{
        execute-keys -draft x<a-k> "^Unstaged changes$" <ret>
        set-register c git diff
    } catch %{
        evaluate-commands -draft %{
            try %{
                execute-keys <a-i>w
            } catch %{
                fail git-jump: no word at cursor
            }
            try %{
                evaluate-commands %sh{
                    [ "$(git rev-parse --revs-only "$kak_selection")" ] || echo fail
                }
            } catch %{
                fail "git-jump: bad revision '%val{selection}'"
            }
            set-register c git show %val{selection} --
        }
    }
    %reg{c}
}}
hook -group boost-git global WinSetOption filetype=git-(?:commit|diff|log|notes|rebase) %{
    map buffer normal <ret> %exp{:git-jump # %val{hook_param}<ret>} -docstring 'Jump to source from git diff'
    hook -once -always window WinSetOption filetype=.* %exp{
        unmap buffer normal <ret> %%{:git-jump # %val{hook_param}<ret>}
    }
}

## Git buffer stack
declare-option str git_buffer
declare-option -hidden str-list git_stack
hook -group boost-git global WinDisplay \*git\* git-stack-push
hook -group boost-git global BufCreate \*git\* %{
    alias buffer buffer-pop git-stack-pop
}
define-command -override git-stack-push -docstring "record *git* buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_git_stack
        if printf '%s\n' "$@" | grep -Fxq -- "$kak_bufname"; then {
            exit
        } fi
        newbuf=$kak_bufname-$#
        echo "try %{ delete-buffer! $newbuf }"
        echo "rename-buffer $newbuf"
        echo "set-option -add global git_stack %val{bufname}"
    }
    set-option global git_buffer %val{bufname}
}
define-command -override git-stack-pop -docstring "restore *git* buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_git_stack
        if [ $# -eq 0 ]; then {
            echo fail "git-stack-pop: no *git* buffer to pop"
            exit
        } fi
        printf 'set-option global git_stack'
        top=
        while [ $# -ge 2 ]; do {
            top=$1
            printf ' %s' "$1"
            shift
        } done
        echo
        echo "delete-buffer $1"
        echo "set-option global git_buffer '$top'"
    }
    try %{
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer %opt{git_buffer}
        }
    }
}
define-command -override git-stack-clear -docstring "clear *git* buffers" %{
    evaluate-commands %sh{
        eval set --  $kak_quoted_opt_git_stack
        printf 'try %%{ delete-buffer %s }\n' "$@"
    }
    set-option global git_stack
}

## Conflict resolution. TODO Better shortcuts?
define-command -override git-conflict-use-ours -docstring "choose the first side of a conflict hunk" %{
    evaluate-commands -draft %{
        execute-keys <a-l>l<a-/>^<lt>{4}<ret>xd
        execute-keys h/^={4}|^\|{4}<ret>
        execute-keys ?^>{4}<ret>xd
    }
}
define-command -override git-conflict-use-theirs -docstring "choose the second side of a conflict hunk" %{
    evaluate-commands -draft %{
        execute-keys <a-l>l<a-/>^<lt>{4}<ret>
        execute-keys ?^={4}<ret>xd
        execute-keys />{4}<ret>xd
    }
}

## Generic Git integration
define-command -override git-select-commit %{
    try %{
        execute-keys %{<a-/>^commit \S+<ret>}
        execute-keys %{1s^commit (\S+)<ret>}
    } catch %{
        try %{
            execute-keys <a-i>w
            evaluate-commands %sh{
                [ "$(git rev-parse --revs-only "$kak_selection" 2>/dev/null)" ] || echo fail
            }
        } catch %{
            # oneline log
            execute-keys <semicolon>x
            try %{ execute-keys %{s^[0-9a-f]{4,}\b<ret>} }
        }
    }
}
declare-option str git_editor %{
    sh -c '
        #!/bin/sh
        # Send an "edit" command to the given Kakoune session and client.
        session="$1"; shift
        client="$1"; shift
        wait=false
        if [ "$1" = --wait ]; then
            wait=true
            shift
        fi
        while [ x"$1" = x-- ]
        do
            shift
        done
        if printf %s "$1" | grep -q ^+; then
            line_and_maybe_column=$(printf %s "$1" | sed -e s,^+,, -e "s,:, ,")
            shift
        fi
        filename=$(realpath "$1")
        cmd="edit -- $filename $line_and_maybe_column"
        if $wait; then
            fifo=$(mktemp -d "${TMPDIR:-/tmp}"/kak-remote-edit.XXXXXXXX)/fifo
            mkfifo $fifo
            cmd="
                $cmd
                define-command -override -hidden git-editor-write -params .. %{
                    remove-hooks buffer remote-edit
                    write %arg{@}
                    delete-buffer
                    echo -to-file $fifo 0
                }
                alias buffer w git-editor-write
                evaluate-commands -verbatim hook -group remote-edit buffer BufClose .* %{
                    echo -to-file $fifo 1
                }
            "
        fi
        printf %s "evaluate-commands -client $client %{$cmd}" |
            kak -p "$session"
        if $wait; then
            read status < $fifo
            rm -r $(dirname $fifo)
            exit $status
        fi
        ' --}
define-command -override boost-git -params 1.. %{ evaluate-commands -draft %{ nop %sh{
    (
        response=git-log-default
        prepend_git=true
        while true; do {
            if [ "$1" = -no-refresh ]; then {
                response=nop
                shift
            } elif [ "$1" = -no-git ]; then {
                prepend_git=false
                shift
            } else {
                break
            } fi
        } done
        if $prepend_git; then
        set -- git "$@"
        fi
        commit=$kak_selection eval set -- "$@"
        escape2() { printf %s "$*" | sed "s/'/''''/g"; }
        escape3() { printf %s "$*" | sed "s/'/''''''''/g"; }
        if output=$(
            EDITOR="$kak_opt_git_editor ${kak_session} ${kak_client} --wait" \
            "$@" 2>&1
        ); then {
            response="'
            $response
            echo -debug $ ''$(escape2 "$@") <<<''
            echo -debug -- ''$(escape2 "$output")>>>''
            '"
        } else {
            response="'
            $response
            echo -debug failed to run ''$(escape2 "$@")''
            echo -debug ''git output: <<<''
            echo -debug -- ''$(escape2 "$output")>>>''
            hook -once buffer NormalIdle .* ''
            echo -markup ''''{Error}{\\}failed to run $(escape3 "$@"), see *debug* buffer''''
            ''
            '"
        } fi
        echo "evaluate-commands -client ${kak_client} $response" |
        kak -p ${kak_session}
    ) >/dev/null 2>&1 </dev/null &
}}}
define-command -override git-with-commit -params 1.. %{ evaluate-commands -draft %{
    try git-select-commit
    boost-git %arg{@}
}}

## Git CLI wrappers
declare-option int git_line 1
define-command -override git-log -params .. %{
    evaluate-commands %{
        try %{
            buffer *git-log*
            try %{
                execute-keys -draft gkJxs 'Unstaged changes\n' | 'Staged changes\n' <ret> d
            }
            set-option global git_line %val{cursor_line}
        } catch %{
            set-option global git_line 1
        }
    }
    evaluate-commands -draft %{
        try %{
            buffer *git*
            rename-buffer *git*.bak
        }
    }
    try %{ delete-buffer *git-log* }
    git log --oneline %arg{@}
    hook -once buffer NormalIdle .* %{
        execute-keys %opt{git_line}g<a-h>
        execute-keys -draft \
        %{gk!} \
        %{git diff --quiet || echo "Unstaged changes";} \
        %{git diff --quiet --cached || echo "Staged changes";} \
        <ret>
    }
    rename-buffer *git-log*
    evaluate-commands -draft %{
        try %{
            buffer *git*.bak
            rename-buffer *git*
        }
    }
}
define-command -override git-log-default -params .. %{
    # TODO Use upstream/fork point
    git-log -50 %arg{@}
}
define-command -override git-fixup %{ evaluate-commands -draft %{
    git-select-commit
    git commit --fixup %val{selection}
}}
define-command -override git-yank -params 1 %{ evaluate-commands -draft %{
    git-select-commit
    evaluate-commands %sh{
        x=$(git log -1 "${kak_selection}" --format="$1")
        printf %s "set-register dquote '$(printf %s "$x" | sed "s/'/''/g")'"
        printf %s "$x" | "${kak_opt_clipboard_copy_cmd}" >/dev/null 2>&1
    }
}}
define-command -override git-yank-reference %{ evaluate-commands -draft %{
    git-select-commit
    evaluate-commands %sh{
        x=$(git log -1 "${kak_selection}" --pretty=reference)
        printf %s "set-register dquote '$(printf %s "$x" | sed "s/'/''/g")'"
        printf %s "$x" | "${kak_opt_clipboard_copy_cmd}" >/dev/null 2>&1
    }
}}

## Third-party Git tools
### Tig - http://jonas.github.io/tig/
define-command -override tig -params .. %{
    terminal env "EDITOR=kak -c %val{session}" tig %arg{@}
}
define-command -override tig-blame -docstring "Run tig blame on the current line" %{
    tig -C %sh{git rev-parse --show-toplevel} blame -C "+%val{cursor_line}" -- %sh{
        dir="$(git rev-parse --show-toplevel)"
        printf %s "${kak_buffile##$dir/}"
    }
}
define-command -override tig-blame-selection -docstring "Run tig -L on the selected lines" %{
    evaluate-commands -save-regs d %{
        evaluate-commands -draft %{
            execute-keys <a-:>
            set-register d %sh{git rev-parse --show-toplevel}
        }
        tig -C %reg{d} %sh{
            anchor=${kak_selection_desc%,*}
            anchor_line=${anchor%.*}
            cursor=${kak_selection_desc#*,}
            cursor_line=${cursor%.*}
            d=$kak_reg_d
            printf %s "-L$anchor_line,$cursor_line:${kak_buffile##$d/}"
        }
    }
}

### git-revise - https://github.com/mystor/git-revise
define-command -override git-revise -params .. %{ git-with-commit revise %arg{@} }
hook -group boost-git global BufCreate .*/git-revise-todo %{
    set-option buffer filetype git-rebase
}

### git-autofixup - https://github.com/torbiak/git-autofixup
declare-option str git_fork_point %{
    #!/bin/sh
    upstream=@{upstream}
    gitdir=$(git rev-parse --git-dir)
    if test -d "$gitdir"/rebase-merge; then
        branch=$(cat "$gitdir"/rebase-merge/head-name)
        branch=${branch#refs/heads/}
        upstream="$branch@{upstream}"
    fi
    git merge-base --fork-point HEAD "$upstream" ||
    git merge-base HEAD "$upstream"
}
define-command -override git-autofixup %{
    boost-git autofixup %sh{eval "${kak_opt_git_fork_point}"}
}
define-command -override git-autofixup-and-apply %{
    evaluate-commands %sh{
        fork_point=$(sh -c "${kak_opt_git_fork_point}")
        git-autofixup "$fork_point" --exit-code >&2
        if [ $? -ge 2 ]; then {
            echo "fail 'error running git-autofixup $fork_point'"
        } fi
    }
    boost-git -c sequence.editor=true revise -i --autosquash %sh{eval "${kak_opt_git_fork_point}"}
}

try %{ declare-user-mode git }
try %{ declare-user-mode git-am }
try %{ declare-user-mode git-apply }
try %{ declare-user-mode git-bisect }
try %{ declare-user-mode git-blame }
try %{ declare-user-mode git-cherry-pick }
try %{ declare-user-mode git-commit }
try %{ declare-user-mode git-diff }
try %{ declare-user-mode git-fetch }
try %{ declare-user-mode git-merge }
try %{ declare-user-mode git-push }
try %{ declare-user-mode git-rebase }
try %{ declare-user-mode git-reset }
try %{ declare-user-mode git-revert }
try %{ declare-user-mode git-revise }
try %{ declare-user-mode git-yank }
try %{ declare-user-mode git-stash }

## User modes
map global git 1 %{:git-conflict-use-ours<ret>} -docstring "conflict: use ours"
map global git 2 %{:git-conflict-use-theirs<ret>} -docstring "conflict: use theirs"
map global git a %{:enter-user-mode git-apply<ret>} -docstring "apply/revert/stage/unstage selection..."
map global git A %{:enter-user-mode git-cherry-pick<ret>} -docstring 'cherry-pick...'
map global git B %{:enter-user-mode git-bisect<ret>} -docstring 'bisect...'
map global git b %{:enter-user-mode git-blame<ret>} -docstring "blame..."
map global git c %{:enter-user-mode git-commit<ret>} -docstring "commit..."
map global git d %{:enter-user-mode git-diff<ret>} -docstring "diff..."
map global git e %{:git edit } -docstring "edit..."
map global git f %{:enter-user-mode git-fetch<ret>} -docstring 'fetch...'
map global git l %{:git-log-default<ret>} -docstring 'log'
map global git L %{:git-log } -docstring 'log...'
map global git m %{:enter-user-mode git-am<ret>} -docstring 'am...'
map global git M %{:enter-user-mode git-merge<ret>} -docstring 'merge...'
map global git o %{:enter-user-mode git-reset<ret>} -docstring "reset..."
map global git p %{:enter-user-mode git-push<ret>} -docstring 'push...'
map global git q %{:git-stack-pop<ret>} -docstring "return to previous *git* buffer"
map global git r %{:enter-user-mode git-rebase<ret>} -docstring "rebase..."
map global git s %{:git show<ret>} -docstring 'git show'
map global git <tab> %{:buffer %opt{git_buffer}<ret>} -docstring "switch to most recent *git* buffer"
map global git t %{:enter-user-mode git-revert<ret>} -docstring "revert..."
map global git v %{:enter-user-mode git-revise<ret>} -docstring "revise..."
map global git y %{:enter-user-mode git-yank<ret>} -docstring "yank..."
map global git z %{:enter-user-mode git-stash<ret>} -docstring "stash..."

map global git-am a %{:boost-git am --abort<ret>} -docstring 'abort'
map global git-am r %{:boost-git am --continue<ret>} -docstring 'continue'
map global git-am s %{:boost-git am --skip<ret>} -docstring 'skip'

map global git-apply a %{:git apply<ret>} -docstring 'apply'
map global git-apply 3 %{:git apply --3way<ret>} -docstring 'apply using 3way merge'
map global git-apply r %{:git apply --reverse<ret>} -docstring 'reverse'
map global git-apply t %{:git apply --reverse --index<ret>} -docstring 'revert and unstage'
map global git-apply s %{:git apply --cached<ret>} -docstring 'stage'
map global git-apply u %{:git apply --reverse --cached<ret>} -docstring 'unstage'
map global git-apply i %{:git apply --index<ret>} -docstring 'apply and stage'

map global git-bisect B %{:git-with-commit bisect bad %{"$commit"}<ret>} -docstring 'mark commit as bad'
map global git-bisect G %{:git-with-commit bisect good %{"$commit"}<ret>} -docstring 'mark commit as good'

map global git-blame t %{:tig-blame<ret>} -docstring "tig: show blame at cursor line"
map global git-blame s %{:tig-blame-selection<ret>} -docstring "tig: show commits that touched main selection"
map global git-blame a %{:git blame<ret>} -docstring "toggle git blame annotations"
map global git-blame b %{:git blame-jump<ret>} -docstring "jump to change that introduced line at cursor"

map global git-cherry-pick a %{:boost-git cherry-pick --abort<ret>} -docstring 'abort'
map global git-cherry-pick p %{:git-with-commit cherry-pick %{"$commit"}<ret>} -docstring 'cherry-pick selected commit'
map global git-cherry-pick r %{:boost-git cherry-pick --continue<ret>} -docstring 'continue'
map global git-cherry-pick s %{:boost-git cherry-pick --skip<ret>} -docstring 'skip'

map global git-commit a %{:boost-git commit --amend<ret>} -docstring 'amend'
map global git-commit A %{:boost-git commit --amend --all<ret>} -docstring 'stage all and amend'
map global git-commit r %{:boost-git commit --amend --reset-author<ret>} -docstring 'amend resetting author'
map global git-commit c %{:boost-git commit<ret>} -docstring 'commit'
map global git-commit C %{:boost-git commit --all<ret>} -docstring 'stage all and commit'
map global git-commit F %{:boost-git commit --fixup=} -docstring 'fixup...'
map global git-commit f %{:git-fixup<ret>} -docstring 'fixup commit selected commit'
map global git-commit u %{:git-autofixup<ret>} -docstring 'autofixup'
map global git-commit o %{:git-autofixup-and-apply<ret>} -docstring 'autofixup and apply'

map global git-diff d %{:git diff<ret>} -docstring "show unstaged changes"
map global git-diff h %{:git diff HEAD<ret>} -docstring "show changes between HEAD and working tree"
map global git-diff u %{:git status<ret>} -docstring "show status"
map global git-diff s %{:git diff --staged<ret>} -docstring "show staged changes"
map global git-diff w %{:git diff -w<ret>} -docstring "show unstaged changes ignoring whitespace"
map global git-diff <ret> %{:git-select-commit<ret>:git diff %reg{.}<ret>} -docstring "show changes between selected commit and working tree"
map global git-diff c %{:eval "grep ^<lt><lt><lt><lt><lt><lt><lt> %sh{git ls-files -u | cut -f2 | sort -u | xargs}"<ret>} -docstring "find all conflicts"

map global git-fetch f %{:boost-git pull --rebase<ret>} -docstring 'pull'
map global git-fetch a %{:boost-git fetch --all<ret>} -docstring 'fetch all'
map global git-fetch o %{:boost-git fetch origin<ret>} -docstring 'fetch origin'

map global git-merge a %{:boost-git merge --abort<ret>} -docstring 'abort'
map global git-merge m %{:git-with-commit merge %{"$commit"}<ret>} -docstring 'merge selected commit'
map global git-merge r %{:boost-git merge --continue<ret>} -docstring 'continue'
map global git-merge s %{:boost-git merge --skip<ret>} -docstring 'skip'

map global git-push p %{:boost-git push<ret>} -docstring 'push'
map global git-push f %{:boost-git push --force<ret>} -docstring 'push --force'

map global git-rebase a %{:boost-git rebase --abort<ret>} -docstring 'abort'
map global git-rebase e %{:boost-git rebase --edit-todo<ret>} -docstring 'edit todo list'
map global git-rebase i %{:git-with-commit rebase --interactive %{"${kak_selection}"^}<ret>} -docstring "interactive rebase from selected commit's parent"
map global git-rebase r %{:boost-git rebase --continue<ret>} -docstring 'continue'
map global git-rebase s %{:boost-git rebase --skip<ret>} -docstring 'skip'
map global git-rebase u %{:boost-git rebase --interactive<ret>} -docstring 'interactive rebase'

map global git-reset o %{:git-with-commit reset %{"$commit"}<ret>} -docstring 'mixed reset'
map global git-reset s %{:git-with-commit reset --soft %{"$commit"}<ret>} -docstring 'soft reset'
map global git-reset O %{:git-with-commit reset --hard %{"$commit"}<ret>} -docstring 'hard reset'

map global git-revert a %{:boost-git revert --abort<ret>} -docstring 'abort'
map global git-revert t %{:git-with-commit revert %{"$commit"}<ret>} -docstring 'revert'
map global git-revert r %{:boost-git revert --continue<ret>} -docstring 'continue'
map global git-revert s %{:boost-git revert --skip<ret>} -docstring 'skip'

map global git-revise a %{:git-revise --reauthor %{"$commit"}<ret>} -docstring 'reauthor'
map global git-revise e %{:git-revise --interactive --edit %sh{eval "${kak_opt_git_fork_point}"}<ret>} -docstring 'edit all since fork-point'
map global git-revise E %{:git-revise --interactive --edit %{"$commit"^}<ret>} -docstring 'edit all since commit'
map global git-revise f %{:git-revise %{"$commit"}<ret>} -docstring 'fixup selected commit'
map global git-revise i %{:git-revise --interactive %{"${kak_selection}^"}<ret>} -docstring "interactive revise from selected commit's parent"
map global git-revise u %{:git-revise --interactive %sh{eval "${kak_opt_git_fork_point}"}<ret>} -docstring 'interactive revise from fork point'
map global git-revise w %{:git-revise --edit %{"$commit"}<ret>} -docstring 'edit'

map global git-stash z %{:boost-git stash push<ret>} -docstring 'push'
map global git-stash p %{:boost-git stash pop<ret>} -docstring 'pop'

map global git-yank a %{:git-yank '%aN <lt>%aE>'<ret>} -docstring 'copy author name and email'
map global git-yank m %{:git-yank '%s%n%n%b'<ret>} -docstring 'copy message'
map global git-yank c %{:git-yank '%H'<ret>} -docstring 'copy commit ID'
map global git-yank r %{:git-yank-reference<ret>} -docstring 'copy pretty commit reference'
