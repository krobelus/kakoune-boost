# Jujutsu - https://martinvonz.github.io/jj

declare-option -hidden str jj_source %val{source}

hook global WinSetOption filetype=jj-diff %{
    map buffer normal <ret> %{:git-diff-goto-source<ret>} -docstring 'Jump to source from git diff'
    hook -once -always -first window WinSetOption filetype=.* %{
        # TODO this only works in colocated repos
        unmap buffer normal <ret> %{:git-diff-goto-source<ret>}
    }
}

define-command -override jj -params 1.. \
    -docstring %{
        jj [<arguments>]: Jujutsu wrapper
        All optional arguments are forwarded to the jj utility

        See ':doc jj' for help.

        Available commands:
            abandon
            backout
            describe
            diff        - compare file contents between two revisions
            edit
            log
            new
            parallelize
            rebase
            show
            squash
            split       - split the selected lines into a separate commit
            status
            undo
    } %{ evaluate-commands %sh{
        kakquote() {
            printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
        }

        trace() {
            # Tracing output.
            printf 'echo -debug -- $ jj'
            for arg; do
                printf ' %s' "$(kakquote "$arg")"
            done
            printf '\n'
        }

        generic_jj() {
            trace "$@"
            if ! output=$(JJ_EDITOR=true jj "$@" 2>&1); then {
                printf %s "fail failed to run jj $1, see the *debug* buffer"
                exec >&2
                printf '$ jj'
                for arg
                do
                    printf ' '
                    kakquote "$arg"
                done
                printf '\n'
                printf '%s\n' "$output"
            } fi
        }

        # TODO handle errors
        show_jj_cmd_output() {
            output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-jj.XXXXXXXX)/fifo
            mkfifo ${output}
            color=
            render_ansi=
            if [ -n "$kak_opt_ansi_filter" ]; then
                color=--color=always
                render_ansi='
                    ansi-enable
                    hook -once buffer BufReadFifo .* %exp{
                        execute-keys -client %val{client} gk
                    }
                '
            fi
            trace "$@"
            ( trap - INT QUIT; jj $color "$@" > ${output} 2>&1 & ) > /dev/null 2>&1 < /dev/null
            printf %s "evaluate-commands -try-client '$kak_opt_docsclient' '
                      edit! -fifo ${output} *jj*
                      $render_ansi
                      set-option buffer filetype ${filetype}
                      hook -always -once buffer BufCloseFifo .* ''
                          nop %sh{ rm -r $(dirname ${output}) }
                      ''
            '"
        }

        with_revisions_around_cursor() {
            revisions=$(revisions_around_cursor)
            generic_jj "$@" $revisions
        }
        with_dash_revision_around_cursor() {
            revision=
            if ! printf '%s\n' "$@" | grep -qE '^(-r|--revisions)'; then
                revision=$(revisions_around_cursor)
            fi
            generic_jj "$@" ${revision:+"--revision=${revision}"}
        }
        with_dash_revisions_around_cursor() {
            revisions=
            if ! printf '%s\n' "$@" | grep -qE '^(-r|--revisions)'; then
                revisions=$(revisions_around_cursor)
            fi
            generic_jj "$@" ${revisions:+"--revisions=$(printf %s\\n ${revisions} | paste -d '|' -s)"}
        }

        revisions_around_cursor() {
            echo >${kak_command_fifo} "jj-revisions-around-cursor ${kak_response_fifo}"
            cat ${kak_response_fifo}
        }

        jj_describe() {
            revisions=$(revisions_around_cursor)
            msgfile=$(mktemp "${TMPDIR:-/tmp}"/kak-jj-describe.XXXXXXXX)
            JJ_EDITOR=cat jj describe $revisions "$@" >"$msgfile" 2>/dev/null
            printf %s "edit $msgfile
                set-option buffer filetype jj-describe
                hook buffer BufWritePost .* %{ evaluate-commands %sh{
                    jj describe $revisions $* --message=\"\$(grep -v ^JJ $msgfile)\"
                } }
                hook buffer BufClose .* %{ nop %sh{ rm -f $msgfile } }
                "
        }

        jj_diff() {
            filetype=git-diff
            show_jj_cmd_output diff "$@"
        }

        jj_log() {
            filetype=jj-log
            show_jj_cmd_output log "$@"
        }

        jj_status() {
            filetype=git-status
            show_jj_cmd_output status "$@"
        }

        jj_show() {
            filetype=git-diff
            revision=$(revisions_around_cursor)
            # Don't pass revision if given as arg.
            if ! jj show $revision "$@" >/dev/null 2>&1; then
                revision=
            fi
            show_jj_cmd_output show $revision "$@"
        }

        jj_squash() {
            if ! printf '%s\n' "$@" | grep -qE '^(-r|--revisions)'; then
                from=$(printf '%s\n' "$@" | grep -oE '^--from')
                into=$(printf '%s\n' "$@" | grep -oE '^--into')
                revisions=$(revisions_around_cursor)
                joined_revisions=${revisions:+"$(printf %s\\n ${revisions} | paste -d '|' -s)"}
                case ${from}${into} in
                    ( --from )
                        generic_jj squash "$@" ${revisions:+"--into=${joined_revisions}"}
                        return
                        ;;
                    ( --into )
                        generic_jj squash "$@" ${revisions:+"--from=${joined_revisions}"}
                        return
                        ;;
                esac
                if [ -n "$revisions" ]; then
                    for revision in $revisions
                    do
                        generic_jj squash "$@" ${revision:+"--revision=${revision}"}
                    done
                    return
                fi
            fi
            generic_jj squash "$@"
        }

        jj_split() {
            echo >${kak_command_fifo} "
                evaluate-commands -draft %{
                    try %{
                        execute-keys %{<a-/>^(?:commit|Commit ID:) \S+<ret>}
                        execute-keys %{1s^(?:commit|Commit ID:) (\S+)<ret>}
                        echo -to-file ${kak_response_fifo} -- %exp{--revision=%val{selection}}
                    } catch %{
                        echo -to-file ${kak_response_fifo}
                    }
                }
            "
            commit=$(cat ${kak_response_fifo})
            echo "require-module patch"
            printf %s "patch JJ_EDITOR=true \
                jj split $commit --tool=${kak_opt_jj_source%/*}/jj-split-tool"
            if [ $# -ge 2 ]; then
                printf ' %%arg{%s}' $(seq 2 $#)
            fi
        }

        cmd=$1
        shift
        case "$cmd" in
            (abandon) with_revisions_around_cursor abandon "$@" ;;
            (backout) with_dash_revisions_around_cursor backout "$@" ;;
            (bookmark) generic_jj bookmark "$@" ;;
            (describe) jj_describe "$@" ;;
            (diff) jj_diff "$@" ;;
            (edit) with_revisions_around_cursor edit "$@" ;;
            (log) jj_log "$@" ;;
            (new) generic_jj new "$@" ;;
            (parallelize) with_revisions_around_cursor parallelize "$@" ;;
            (rebase) with_dash_revisions_around_cursor rebase "$@" ;;
            (show) jj_show "$@" ;;
            (squash) jj_squash "$@" ;;
            (split) jj_split "$@" ;;
            (status) jj_status "$@" ;;
            (undo) generic_jj undo "$@" ;;
            (*) printf "fail unknown jj command '%s'\n" "$cmd"
        esac
    }
}

complete-command jj shell-script-candidates %{
    printf %s\\n \
        abandon \
        backout \
        describe \
        diff \
        edit \
        log \
        new \
        parallelize \
        rebase \
        show \
        squash \
        split \
        status \
        undo \
}

define-command -override jj-revisions-around-cursor -params 1 %{
    evaluate-commands -draft %{
        try %{
            execute-keys %{<a-/>^(?:commit|Change ID:) \S+<ret>}
            execute-keys %{1s^(?:commit|Change ID:) (\S+)<ret>}
            echo -to-file %arg{1} %val{selection}
        } catch %{
            execute-keys %{<a-s><a-l><semicolon><a-/>^\h*(?:│ )*[@◆○×](?:\h*│)*\h*\b[a-z]+<ret>}
            execute-keys %{1s^\h*(?:│ )*[@◆○×](?:\h*│)*\h*\b([a-z]+)<ret>}
            echo -to-file %arg{1} %val{selections}
        } catch %{
            echo -to-file %arg{1}
        }
    }
}
