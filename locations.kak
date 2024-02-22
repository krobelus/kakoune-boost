## Grep

define-command -override boost-grep -docstring "grep and select matches with <a-s>
works best if grepcmd uses a regex flavor similar to Kakoune's
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
        printf %s "map buffer normal <tab> '"
        printf %s '%S^<ret><a-h>/^.*?:\d+(?::\d+)?:<ret>'
        printf %s '<a-semicolon>l<a-l>'
        printf %s "s$(printf %s "$kak_main_reg_slash" | sed s/"'"/"''"/g"; s/</<lt>/g")<ret>"
        printf %s "'"
    }
}}
