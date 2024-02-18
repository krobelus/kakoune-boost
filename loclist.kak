## Location List

declare-option -hidden str loclist_buffer
declare-option -hidden str-list loclist_stack
declare-option -docstring %{Defines location patterns for location lists.
Default locations look like "file:line[:column][:message]"

Capture groups must be:
    1: filename
    2: line number
    3: optional column
    4: optional message
} regex loclist_location_format ^\h*\K([^:\n]+):(\d+)\b(?::(\d+)\b)?(?::([^\n]+))

declare-option str loclist_root ''

define-command loclist-jump %{ # from grep.kak
    evaluate-commands -save-regs abc %{ # use evaluate-commands to ensure jumps are collapsed
        try %{
            evaluate-commands -draft -save-regs / %{
                set-register / %opt{loclist_location_format}
                execute-keys <semicolon>xs<ret>
                set-register a "%reg{1}"
                set-register b "%reg{2}"
                set-register c "%reg{3}"
                try %{
                    # Is it an absolute path?
                    execute-keys s\A/.*<ret>
                } catch %{
                    set-register a "%opt{loclist_root}%reg{a}"
                }
            }
            set-option buffer grep_current_line %val{cursor_line}
            evaluate-commands -try-client %opt{jumpclient} -verbatim -- edit -existing -- %reg{a} %reg{b} %reg{c}
            try %{ focus %opt{jumpclient} }
        }
    }
}

define-command loclist-next-location -docstring %{
    loclist-next-location
    Jump to next location listed in the current location list buffer, usually one of
    *diagnostics* *goto* *grep* *implementations* *lint-output* *make* *references* *symbols*

    %opt{loclist_buffer} determines the buffer current location list buffer.
    %opt{loclist_location_format} determines matching locations.
} -buffer-completion %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %opt{loclist_buffer}
        set-register / %opt{loclist_location_format}
        execute-keys ge %opt{grep_current_line}g<a-l> /<ret>
        loclist-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %opt{loclist_buffer}
            execute-keys gg %opt{grep_current_line}g
        }
    }
}

define-command loclist-previous-location -docstring %{
    loclist-previous-location
    Jump to previous location listed in the current location list buffer, usually one of
    *diagnostics* *goto* *grep* *implementations* *lint-output* *make* *references* *symbols*

    %opt{loclist_buffer} determines the buffer current location list buffer.
    %opt{loclist_location_format} determines matching locations.
} -buffer-completion %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %opt{loclist_buffer}
        set-register / %opt{loclist_location_format}
        execute-keys ge %opt{grep_current_line}g<a-h> <a-/><ret>
        loclist-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %opt{loclist_buffer}
            execute-keys gg %opt{grep_current_line}g
        }
    }
}

define-command -override loclist-stack-push -docstring "record location list buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_loclist_stack
        if printf '%s\n' "$@" | grep -Fxq -- "$kak_bufname"; then {
            exit
        } fi
        newbuf=$kak_bufname-$#
        echo "try %{ delete-buffer! $newbuf }"
        echo "rename-buffer $newbuf"
        echo "set-option -add global loclist_stack %val{bufname}"
    }
    set-option global loclist_buffer %val{bufname}
}

define-command -override loclist-stack-pop -docstring "restore location list buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_loclist_stack
        if [ $# -eq 0 ]; then {
            echo fail "loclist-stack-pop: no location list buffer to pop"
            exit
        } fi
        printf 'set-option global loclist_stack'
        top=
        while [ $# -ge 2 ]; do {
            top=$1
            printf ' %s' "$1"
            shift
        } done
        echo
        echo "delete-buffer $1"
        echo "set-option global loclist_buffer '$top'"
    }
    try %{
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer %opt{loclist_buffer}
            grep-jump
        }
    }
}
define-command -override loclist-stack-clear -docstring "clear location list buffers" %{
    evaluate-commands %sh{
        eval set --  $kak_quoted_opt_loclist_stack
        printf 'try %%{ delete-buffer %s }\n' "$@"
    }
    set-option global loclist_stack
}

# TODO: What exactly does this disable, and do we need to?
set-option global disabled_hooks "%opt{disabled_hooks}|grep-jump"
declare-option regex loclist_buffer_regex \*(?:callees|callers|diagnostics|goto|find|grep|implementations|lint-output|references)\*(?:-\d+)?

hook -group loclist global WinDisplay %opt{loclist_buffer_regex} %{
    loclist-stack-push
}

hook -group loclist global GlobalSetOption '^loclist_buffer=(.*)$' %{
    # TODO: Upstream as loclist-write?
    # alias "buffer=%opt{loclist_buffer}" w grep-write
    map "buffer=%opt{loclist_buffer}" r
}

# NOTE: Only relevant if other bufer-stack systems are included
# alias global buffers-pop loclist-stack-pop
# alias global buffer-clear loclist-stack-clear
