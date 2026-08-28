# Agent notes — vt-d

Project facts for agents. Workstation/env facts live only in `$CODE_ROOT/MEMORIES.md`.

- DUB package name is `vt-d`; GitHub repo is `dlang-supplemental/vt-d`
- Pure logic: parse VT/ANSI byte streams into a character-cell `Screen` — no PTY, windowing, or GPU
- Sibling PTY bindings: [`pty-d`](https://github.com/dlang-supplemental/pty-d) (ConPTY + POSIX)
- Host wiring (ConPTY + vt-d + dew) is still open — see OpenShellOrg shell-architecture inventory
- Categories: `library.tui`, `library.development.parsing`
- Publish via sibling `dub-publish` / `dubx`
