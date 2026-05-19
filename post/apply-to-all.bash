# apply theme to all writeable pts
_tty_theme_post_apply_to_all() {
    local pts seq
    (( ${UID:-0} )) &&
        [[ -z "${SSH_TTY:-}${SUDO_TTY:-}" ]] &&
        seq="$(TERM=xterm _tty_theme_sequence "$@")" ||
        return 0
    for pts in /dev/pts/*; do
        ! [[ -c "$pts" && -w "$pts" ]] || (
            # this blocks sometimes, give up after one second
            timeout 1 cat &
        ) < <(printf %s "$seq") > "$pts" 2>&-
    done
}

TTY_THEME_POST+=(_tty_theme_post_apply_to_all)
