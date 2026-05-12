#!/bin/bash

# apply the theme and store it for auto loading
_tty_theme() {
    local theme="$*"
    local colors
    colors="$(_tty_theme_get "$theme")" || return 1
    read -ra colors <<<"$colors"
    _tty_theme_apply "${colors[@]}" || return 1
    export TTY_THEME="$theme"

    # post function to override, gets passed theme colors as parameters
    ! command -v _tty_theme_post >/dev/null ||
        _tty_theme_post "${colors[@]}" ||
        return 1

    local config="${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme"
    local profile
    read -r profile _ <<<"${TTY_THEME_PROFILE:-default}"
    mkdir -p -- "$config"
    {
        printf '%s' "$theme"
        printf ',%s' "${colors[@]}"
        printf '\n'
    } > "$config/$profile.theme"
}

# generate and print control sequences
_tty_theme_apply() {
    local colors=("$@")
    (( 16 <= ${#colors[@]} <= 19 )) || return 1
    local fg="${colors[16]:-"${colors[7]}"}"
    local bg="${colors[17]:-"${colors[0]}"}"
    local cur="${colors[18]:-"$fg"}"
    local sequence
    case "${TERM%%-*}" in
        linux) _tty_theme_format 0 $'\e]P%X%02x%02x%02x' \
            "$bg" "${colors[@]:1:6}" "$fg" "${colors[@]:8:8}" &&
            printf $'\e[2J\e[H';;
        *) mapfile -d $'\a' sequence < <(
                _tty_theme_format 10 $'\e]%d;rgb:%02x/%02x/%02x\a' \
                    "$fg" "$bg" "$cur"
                pattern=$'\e]4;%d;rgb:%02x/%02x/%02x\a'
                _tty_theme_color256 "$pattern" "${colors[@]}" ||
                    _tty_theme_format 0 "$pattern" "${colors[@]:0:16}"
            );;&  # continue to ...
        # ... optional passthrough encapsulation for tmux and screen
        tmux) printf $'\ePtmux;%s\e\\' "${sequence[@]//$'\e'/$'\e\e'}";;
        screen) printf $'\eP%s\e\\' "${sequence[@]}";;
        *) printf %s "${sequence[@]}";;
    esac
    export TTY_THEME_COLORS="${colors[*]}"
}

# generate control sequences for the 256 color palette
_tty_theme_color256() {
    local pattern="$1" colors=("${@:2}")
    (( ${TTY_THEME_COLOR256:-1} )) || return 1
    local script
    script="$(readlink -f "${BASH_SOURCE[0]}")" &&
        awk -f "${script%.*}256.awk" \
            -v harmonious="${TTY_THEME_COLOR256_HARMONIOUS:-0}" \
            -v pattern="$pattern" <<<"${colors[*]}"
}

# update theme database
_tty_theme_update() {
    local file="$1"
    local url="${TTY_THEME_URL:-https://raw.githubusercontent.com/Gogh-Co/Gogh/master/data/themes.csv}"
    local order="${TTY_THEME_HEADERS:-"name$(
        printf ' color_%02d' {1..16}) foreground background cursor"}"
    local update="${TTY_THEME_UPDATE:-1}"
    local max_age="-${TTY_THEME_UPDATE_INTERVAL:-1 week}"
    local curl tmp ec=0

    [[ -n "$file" ]] || return 1

    # return if update is disabled
    (( update > 0 )) || return 0

    # create temp file
    [[ "$file" != */* ]] || [[ -d "${file%/*}" ]] ||
        mkdir -p -- "${file%/*}" || return 1
    tmp="$(mktemp "$file.XXXXXX")" || return 1

    # update continue if database is older than max_age
    if (( update >= 2 )) ||
            touch -d "$max_age" "$tmp" &&
            [[ "$tmp" -nt "$file" ]]; then
        curl=(-SsLm10 --etag-save "$tmp.etag" -o "$tmp")

        # make curl check against stored timestamp and etag
        if (( update < 3 )); then
            [[ ! -f "$file" ]] || curl+=(--time-cond "$file")
            [[ ! -f "$file.etag" ]] || curl+=(--etag-compare "$file.etag")
        fi

        # download database, size is zero if etag and date check triggered
        if ec=1 && curl "${curl[@]}" "$url" && ec=0 && [[ -s "$tmp" ]]; then
            {
                local fields field colors name
                local -A header

                # create a header to index mapping
                IFS=',' read -ra fields || return 1
                for i in "${!fields[@]}"; do
                    header["${fields[i]}"]="$i"
                done

                # set the required order
                read -ra order <<<"$order"
                while IFS=',' read -ra fields; do
                    name="${fields[${header["${order[0]}"]}]}"
                    [[ -n "$name" ]] || continue
                    colors=()

                    # extract and validate colors in the correct order
                    for field in "${order[@]:1}"; do
                        field="${fields[${header["$field"]}]}"
                        [[ "${field,,}" =~ [0-9a-f]{1,6} ]] || continue 2
                        colors+=("0x${BASH_REMATCH[0]}")
                    done
                    printf '%s%s\n' "$name" "$(printf ",%06x" "${colors[@]}")"
                done
            } < "$tmp" > "$file"
            touch -r "$tmp" -- "$file"
            mv -- "$tmp.etag" "$file.etag"
        else
            rm -f -- "$tmp.etag"
        fi
    fi
    rm -f -- "$tmp"
    return "$ec"
}

# output the theme database, optinally trigger update
_tty_theme_data() {
    local config="${XDG_CACHE_HOME:-"$HOME/.config"}/tty-theme"
    local cache="${XDG_CACHE_HOME:-"$HOME/.cache"}/tty-theme"
    local file="$config/themes.csv"

    if [[ ! -f "$file" ]]; then
        file="$cache/${file##*/}"
        _tty_theme_update "$file" || return 1
    fi

    [[ -f "$file" ]] || return 1
    local line
    while read -r line; do
        echo "$line"
    done <"$file"
}

# get colors for specified theme
_tty_theme_get() {
    local theme="$*"
    local fields
    while IFS=',' read -ra fields; do
        if [[ "${fields[0]}" == "$theme" ]]; then
            echo "${fields[*]:1}"
            return 0
        fi
    done < <(_tty_theme_data)
    return 1
}

# list themes according to pattern
_tty_theme_list() {
    local pattern="${1:-%s\\n}"
    local theme
    while IFS=',' read -r theme _; do
        # shellcheck disable=SC2059
        printf -- "$pattern" "$theme"
    done < <(_tty_theme_data)
}

# format index and colors according to pattern with the index starting at offset
# or omitted if less than zero
_tty_theme_format() {
    local offset="$1" pattern="$2" colors=("${@:3}")
    local i color
    for i in "${!colors[@]}"; do
        color=$((16#${colors[i]}))
        # shellcheck disable=SC2046,SC2059
        printf -- "$pattern" $( (( offset < 0 )) || echo $((i + offset)) ) \
            $((color >> 16 & 0xff)) $((color >> 8 & 0xff)) $((color & 0xff)) ||
            return 1
    done
}

# generate theme preview
_tty_theme_preview() {
    local theme="$*"

    local colors fg bg cur
    colors="$(_tty_theme_get "$theme")" || return 1
    read -ra colors <<<"$colors"
    mapfile -t colors < <(_tty_theme_format -1 '%d;%d;%d\n' "${colors[@]}")
    fg="${colors[16]:-"${colors[7]}"}" bg="${colors[17]:-"${colors[0]}"}"
    cur="${colors[18]:-"$fg"}" colors=("${colors[@]:0:16}")

    local color inv i
    # line start, line end
    local ls le=$'\e[0m\n'
    # block width, block count, space before, row count
    local bw=8 bc=8 sp=0 r=0 i
    local tw="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-64}}"
    local th="${FZF_PREVIEW_LINES:-0}"

    # blocks per line, min 1, max 8
    bc=$(( bc=(tw / bw), bc < 1 ? 1 : (bc > 8 ? 8 : bc) ))
    sp=$(((tw - bc * bw) / 2))
    ls="$(printf '\e[0;38;2;%s;48;2;%sm' "$fg" "$bg")"
    theme="${theme##*/}" && theme="${theme%.*}" && theme="${theme:0:tw}"

    printf '%s%*s%s' "$ls" "$tw" '' "$le" && (( ++r ))
    # center theme name followed by cursor
    printf '%s\e[1m%*s\e[5;38;2;%sm█%s%*s%s' \
        "$ls" $((tw / 2 + ${#theme} / 2)) "$theme" "$cur" "$ls" \
        $((tw / 2 - ${#theme} / 2 - 1 + tw % 2)) '' "$le" && (( ++r ))
    printf '%s%*s%s' "$ls" "$tw" '' "$le" && (( ++r ))
    # print blocks
    for inv in 0 1; do
        i=0
        while (( i < ${#colors[@]} )); do
            printf '%s%*s' "$ls" "$sp" ''
            (( !inv )) || printf '\e[7m'
            for color in "${colors[@]:(i/bc)*bc:bc}"; do
                # shellcheck disable=SC2086
                printf '\e[38;2;%sm %02x%02x%02x ' "$color" ${color//\;/ }
                ((++i % bc)) || break
            done
            printf '%s%*s%s' "$ls" \
                $((tw - sp - bw * ((i - 1) % bc + 1))) '' "$le" && (( ++r ))
        done
        printf '%s%*s%s' "$ls" "$tw" '' "$le" && (( ++r ))
    done
    # fill till bottom, fzf only, see $th
    while (( r < th )); do
        printf '%s%*s%s' "$ls" "$tw" '' "$le" && (( ++r ))
    done
}

# restores the current theme, optionally runs the passed command first
# shellcheck disable=SC2120
_tty_theme_restore() {
    local cmd=("$@") ec=0
    (( !${#cmd[@]} )) || "${cmd[@]}"; ec=$?
    if [[ -n "${TTY_THEME:-}" && -n "${TTY_THEME_COLORS:-}" ]]; then
        local colors
        read -ra colors <<<"$TTY_THEME_COLORS"
        _tty_theme_apply "${colors[@]}"
    else
        local config="${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme"
        local profiles="${TTY_THEME_PROFILE:-"$TERM ${TERM%%-*} default"}"
        local theme
        read -ra profiles <<<"$profiles"
        for theme in "${profiles[@]}"; do
            printf -v theme '%s/%s.theme' "$config" "$theme"
            if [[ -f "$theme" ]]; then
                IFS=',' read -ra theme <"$theme"
                ! _tty_theme_apply "${theme[@]:1:20}" ||
                    export TTY_THEME="${theme[0]:-unknown}"
                break
            fi
        done
    fi
    return "$ec"
}

if [[ -n "${PS1:-}" ]]; then
    alias tty-theme=_tty_theme
    alias tty-theme-preview=_tty_theme_preview
    alias reset='_tty_theme_restore reset'

    if [[ -v BASH_COMPLETION_VERSINFO ]]; then
        _comp_tty_theme() {
            (( COMP_CWORD <= 1 )) || return
            compgen -V COMPREPLY -W "$(_tty_theme_list '%q\n')" \
                -- "${COMP_WORDS[COMP_CWORD]}"
        }
        complete -F _comp_tty_theme -o fullquote -o nospace tty-theme

        if command -v _fzf_complete >/dev/null; then
            _fzf_tty_theme_completion() {
                (( COMP_CWORD <= 1 )) || return
                local cur
                # shellcheck disable=SC2162
                read cur <<<"${COMP_WORDS[COMP_CWORD]}"
                COMP_WORDS[COMP_CWORD]="${cur//[\"\']/}"
                FZF_COMPLETION_TRIGGER='' TTY_THEME_UPDATE=0 \
                    _fzf_complete \
                    --preview="$(printf '. %q && _tty_theme_preview {}' \
                        "${BASH_SOURCE[0]}")" \
                    --preview-window='right,noinfo,<68(bottom,9)' \
                    --bind=resize:refresh-preview \
                    -- "$@" < <(_tty_theme_list | sort)
            }
            _fzf_orig_completion_tty_theme=_comp_tty_theme
            complete -F _fzf_tty_theme_completion \
                -o fullquote -o nospace tty-theme
            unalias tty-theme-preview
        else
            complete -F _comp_tty_theme -o fullquote tty-theme-preview
        fi
    fi
fi

# shellcheck disable=SC1091
[[ ! -f "${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme/config.sh" ]] ||
    . "${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme/config.sh"

(( ! ${TTY_THEME_AUTOLOAD:-1} )) ||
    [[ -n "${TTY_THEME:-}${SUDO_TTY:-}${SSH_TTY:-}" ]] ||
    _tty_theme_restore
