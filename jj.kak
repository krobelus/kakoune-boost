# Jujutsu - https://martinvonz.github.io/jj

declare-option -hidden str jj_source %val{source}

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
            undo
    } %{ evaluate-commands %sh{
        kakquote() {
            printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
        }

        generic_jj() {
            if ! output=$(jj "$@" 2>&1); then {
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
                exit
            } fi
        }

        show_jj_cmd_output() {
            output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-jj.XXXXXXXX)/fifo
            mkfifo ${output}
            color=
            render=
            if [ -n "$kak_opt_ansi_filter" ]; then
                color=--color=always
                render=ansi-render
            fi
            ( trap - INT QUIT; jj $color "$@" > ${output} 2>&1 & ) > /dev/null 2>&1 < /dev/null

            printf %s "evaluate-commands -try-client '$kak_opt_docsclient' '
                      edit! -fifo ${output} *jj*
                      set-option buffer filetype ${filetype}
                      hook -always -once buffer BufCloseFifo .* ''
                          nop %sh{ rm -r $(dirname ${output}) }
                          $render
                      ''
            '"
        }

        jj_describe() {
            msgfile=$(mktemp "${TMPDIR:-/tmp}"/kak-jj-describe.XXXXXXXX)
            JJ_EDITOR=cat jj describe "$@" >"$msgfile" 2>/dev/null
            printf %s "edit $msgfile
                set-option buffer filetype jj-describe
                hook buffer BufWritePost .* %{ evaluate-commands %sh{
                    jj describe $* --message \"\$(grep -v ^JJ $msgfile)\"
                } }
                hook buffer BufClose .* %{ nop %sh{ rm -f $msgfile } }
                "
        }

        jj_diff() {
            filetype=jj-diff
            show_jj_cmd_output diff "$@"
        }

        jj_log() {
            filetype=jj-log
            show_jj_cmd_output log "$@"
        }

        jj_show() {
            filetype=jj-diff
            show_jj_cmd_output show "$@"
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
            (abandon) generic_jj abandon "$@" ;;
            (backout) generic_jj backout "$@" ;;
            (describe) jj_describe "$@" ;;
            (diff) jj_diff "$@" ;;
            (edit) generic_jj edit "$@" ;;
            (log) jj_log "$@" ;;
            (new) generic_jj new "$@" ;;
            (parallelize) generic_jj parallelize "$@" ;;
            (rebase) generic_jj rebase "$@" ;;
            (show) jj_show "$@" ;;
            (squash) generic_jj squash "$@" ;;
            (split) jj_split "$@" ;;
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
        undo \
}
