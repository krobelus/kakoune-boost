# kakoune-boost

This is a place for work-in-progress and experimental scripts that are
intended to be added to the [Kakoune editor](https://github.com/mawww/kakoune).

If a change graduates to a ready-to-use Kakoune patch, it should be removed
from kakoune-boost. This keeps us honest - we should nurse patches in our
individual forks.

# Usage

We currently require a development version of Kakoune (>= 2024-02) and Git.

    git clone https://github.com/krobelus/kakoune-boost ~/.config/kak/autoload/
    kak -e '
        map global user g %{:enter-user-mode git<ret>} -docstring git...
    '

The scripts are idempotent; after making a change you can source them again,
no need to restart the editor.

# Contributing

Send feedback and patches to [~krobelus/kakoune@lists.sr.ht](mailto:~krobelus/kakoune@lists.sr.ht) (see
[public archives](https://lists.sr.ht/~krobelus/kakoune)) or use GitHub or IM.
