define-command -override -hidden surround-on-insert-open -params 2 %{
    echo -debug "surround-on-insert-open"
    execute-keys -draft <\> a %arg{2} <esc>
}

define-command -override -hidden surround-on-delete-open -params 2 %{
    echo -debug "surround-on-delete-open"
    try %{
        evaluate-commands -draft -save-regs a -no-hooks %{
            set-register a %arg{2}
            execute-keys -draft "<a-;>l<a-k>\Q<c-r>a<ret>d"
        }
    }
}

define-command -override -hidden surround-on-insert-close -params 2 %{
    surround-on-delete-open %arg{@}
}

define-command -override -hidden surround-on-delete-close -params 2 %{
    surround-on-insert-open %arg{@}
}

define-command -hidden setup-surround-pair -params 2 -override %{
    evaluate-commands %sh{
        escapequote() { printf "%s" "$*" | sed "s/'/''/g"; }
        set -- $(escapequote "$1") $(escapequote "$2")
        set -- "$1" "$2" $(escapequote "$1") $(escapequote "$2")
        printf "%s\n" "hook window -group surround InsertChar '\Q$1\E' 'surround-on-insert-open ''$3'' ''$4'' '"
        printf "%s\n" "hook window -group surround InsertDelete '\Q$1\E' 'surround-on-delete-open ''$3'' ''$4'' '"
        [ "$1" != "$2" ] && printf "%s\n" "hook window -group surround InsertChar '\Q$2\E' 'surround-on-insert-close ''$3'' ''$4'' '"
        [ "$1" != "$2" ] && printf "%s\n" "hook window -group surround InsertDelete '\Q$2\E' 'surround-on-delete-close ''$3'' ''$4'' '"
    }
}

define-command surround-mode -override %§
    # TODO: Get these from a surround_pairs option
    setup-surround-pair "(" ")"
    setup-surround-pair "[" "]"
    setup-surround-pair "<" ">"
    setup-surround-pair "{" "}"
    setup-surround-pair "'" "'"
    setup-surround-pair '"' '"'
    setup-surround-pair '`' '`'

    # Disable https://github.com/alexherbo2/auto-pairs.kak in the surround mode
    # TODO: Is there a more intelligent way to do this? Maybe a more generic way
    # Maybe all hooks should be disabled, and ours marked -always, but that seems
    # Like a slippery slope as well
    try disable-auto-pairs
    execute-keys -with-hooks i

    hook window -group surround ModeChange pop:insert:.* %exp{
        remove-hooks window surround
        # TODO: Remember whether auto-pairs was enabled before
        try enable-auto-pairs
    }
§
