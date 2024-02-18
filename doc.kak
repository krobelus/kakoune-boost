define-command -override doc-key -docstring "show the documentation of a key in normal mode" %{
    # Read a single key.
    evaluate-commands -verbatim on-key %{
        # Switch to the documentation of keys, or open it.
        try %{
            buffer *doc-keys*
        } catch %{
            doc keys
        }
        # Jump to the line where this key is documented.
        evaluate-commands execute-keys %sh{
            kakquote() { printf %s "$*" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"; }
            key=$(printf %s "$kak_key" |
            sed '
            s/<semicolon>/;/;
            s/-semicolon/-;/;
            s/</<lt>/;
            ')
            kakquote "$(printf "/^\Q%s<ret>vv" "$key")"
        }
    }
}
