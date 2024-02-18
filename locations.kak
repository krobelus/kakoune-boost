## Grep

define-command -override boost-grep -docstring "grep and select matches with <a-s>
works best if grepcmd uses a regex flavor simlar to Kakoune's
" -params .. %{
  try %{
    evaluate-commands %sh{ [ -z "$1" ] && echo fail }
    set-register / "(?S)%arg{1}"
    grep %arg{@}
  } catch %{
    execute-keys -save-regs '' *
    evaluate-commands -save-regs l %{
      evaluate-commands -verbatim grep -- %sh{ printf %s "$kak_main_reg_slash" }
    }
  }
  boost-map-quickselect
}
try %{ complete-command boost-grep file }

define-command -override boost-map-quickselect %{ evaluate-commands -save-regs 'l' %{
  evaluate-commands -try-client %opt{toolsclient} %sh{
    printf %s "map buffer=$kak_opt_locations_buffer normal <tab> '"
    printf %s '%S^<ret><a-h>/^.*?:\d+(?::\d+)?:<ret>'
    printf %s '<a-semicolon>l<a-l>'
    printf %s "s$(printf %s "$kak_main_reg_slash" | sed s/"'"/"''"/g"; s/</<lt>/g")<ret>"
    printf %s "'"
  }
}}

## Locations

declare-option -hidden str locations_buffer
declare-option -hidden str-list locations_stack
declare-option -docstring %{Defines location patterns for location lists.
Default locations look like "file:line[:column][:message]"

Capture groups must be:
    1: filename
    2: line number
    3: optional column
    4: optional message
} regex locations_location_format ^\h*\K([^:\n]+):(\d+)\b(?::(\d+)\b)?(?::([^\n]+))

declare-option str locations_root ''

declare-option regex locations_buffer_regex \*(?:callees|callers|diagnostics|goto|find|grep|implementations|lint-output|references)\*(?:-\d+)?

hook -group locations global WinDisplay %opt{locations_buffer_regex} %{
    locations-stack-push
}

hook -group locations global GlobalSetOption 'locations_buffer=(.*)' %{
    # TODO: Upstream as locations-write?
    # alias "buffer=%opt{locations_buffer}" w grep-write
    map "buffer=%opt{locations_buffer}" normal <ret> ':locations-jump<ret>'
}

# NOTE: Only relevant if other bufer-stack systems are included
# alias global buffers-pop locations-stack-pop
# alias global buffer-clear locations-stack-clear

define-command locations-jump %{ # from grep.kak
    evaluate-commands -save-regs abc %{ # use evaluate-commands to ensure jumps are collapsed
        try %{
            evaluate-commands -draft -save-regs / %{
                set-register / %opt{locations_location_format}
                execute-keys <semicolon>xs<ret>
                set-register a "%reg{1}"
                set-register b "%reg{2}"
                set-register c "%reg{3}"
                try %{
                    # Is it an absolute path?
                    execute-keys s\A/.*<ret>
                } catch %{
                    set-register a "%opt{locations_root}%reg{a}"
                }
            }
            set-option buffer grep_current_line %val{cursor_line}
            evaluate-commands -try-client %opt{jumpclient} -verbatim -- edit -existing -- %reg{a} %reg{b} %reg{c}
            try %{ focus %opt{jumpclient} }
        }
    }
}

define-command locations-next -docstring %{
    locations-next
    Jump to next location listed in the current location list buffer, usually one of
    *diagnostics* *goto* *grep* *implementations* *lint-output* *make* *references* *symbols*

    %opt{locations_buffer} determines the buffer current location list buffer.
    %opt{locations_location_format} determines matching locations.
} -buffer-completion %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %opt{locations_buffer}
        set-register / %opt{locations_location_format}
        execute-keys ge %opt{grep_current_line}g<a-l> /<ret>
        locations-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %opt{locations_buffer}
            execute-keys gg %opt{grep_current_line}g
        }
    }
}

define-command locations-previous -docstring %{
    locations-previous
    Jump to previous location listed in the current location list buffer, usually one of
    *diagnostics* *goto* *grep* *implementations* *lint-output* *make* *references* *symbols*

    %opt{locations_buffer} determines the buffer current location list buffer.
    %opt{locations_location_format} determines matching locations.
} -buffer-completion %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %opt{locations_buffer}
        set-register / %opt{locations_location_format}
        execute-keys ge %opt{grep_current_line}g<a-h> <a-/><ret>
        locations-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %opt{locations_buffer}
            execute-keys gg %opt{grep_current_line}g
        }
    }
}

define-command -override locations-stack-push -docstring "record location list buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_locations_stack
        if printf '%s\n' "$@" | grep -Fxq -- "$kak_bufname"; then
            exit
        fi
        newbuf=$kak_bufname-$#
        echo "try %{ delete-buffer! $newbuf }"
        echo "rename-buffer $newbuf"
        echo "set-option -add global locations_stack %val{bufname}"
    }
    set-option global locations_buffer %val{bufname}
}

define-command -override locations-stack-pop -docstring "restore location list buffer" %{
    evaluate-commands %sh{
        eval set -- $kak_quoted_opt_locations_stack
        if [ $# -eq 0 ]; then 
            echo fail "locations-stack-pop: no location list buffer to pop"
            exit
        fi
        printf 'set-option global locations_stack'
        top=
        while [ $# -ge 2 ]; do 
            top=$1
            printf ' %s' "$1"
            shift
        done
        echo
        echo "delete-buffer $1"
        echo "set-option global locations_buffer '$top'"
    }
    try %{
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer %opt{locations_buffer}
            locations-jump
        }
    }
}
define-command -override locations-stack-clear -docstring "clear location list buffers" %{
    evaluate-commands %sh{
        eval set --  $kak_quoted_opt_locations_stack
        printf 'try %%{ delete-buffer %s }\n' "$@"
    }
    set-option global locations_stack
}

