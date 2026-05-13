#!/bin/bash

# apply the theme and store it for auto loading
_tty_theme() {
    local theme="$*"
    local colors
    if [[ -z "$theme" ]] || ! colors="$(_tty_theme_get "$theme")"; then
        theme="$(_tty_theme_fzf fzf --query="$theme")" || return 1
        colors="$(_tty_theme_get "$theme")" || return 1
    fi
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
    local config="${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme"
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

    local colors
    colors="$(_tty_theme_get "$theme")" || return 1
    read -ra colors <<<"$colors"

    local colors16 fg bg cur
    mapfile -t colors16 < <(_tty_theme_format -1 '%d;%d;%d\n' "${colors[@]}")
    fg="${colors16[16]:-"${colors16[7]}"}"
    bg="${colors16[17]:-"${colors16[0]}"}"
    cur="${colors16[18]:-"$fg"}"

    local colors256
    mapfile -t colors256 < <(_tty_theme_color256 '%d:%d;%d;%d\n' "${colors[@]}")
    colors256=("${colors256[@]#*:}")

    local tw="${FZF_PREVIEW_COLUMNS:-"${COLUMNS:-0}"}"
    local th="${FZF_PREVIEW_LINES:-0}"
    (( tw )) || tw="$(tput cols)" || tw=64

    local ls le=$'\e[0m\n' spacer
    ls="$(printf '\e[0;38;2;%s;48;2;%sm' "$fg" "$bg")"
    spacer="$(printf '%s%*s%s' "$ls" "$tw" '' "$le")"

    local line lines=0
    while IFS='' read -r line; do
        echo "$line" && (( ++lines ))
    done < <(
        print_block() {
            local bw="$1" bcs="$2" callback="$3" colors=("${@:4}")
            local bc bn idx=0

            # find the highest block count that fits into the terminal
            IFS=, read -ra bcs <<<"$bcs"
            for bc in "${bcs[@]}"; do
                (( bc * bw > tw )) || break
            done

            # cancel preview if there is not enough space left
            if (( th > 0 && lines + ${#colors[@]} / bc + 1 > th )); then
                print_space
                exit 0
            fi

            local sp=$(((tw - bc * bw) / 2))
            while (( idx < ${#colors[@]} )); do
                printf '%s%*s' "$ls" "$sp" ''
                for (( bn = 0; bn < bc; bn++ )); do
                    "${callback}" "${colors[idx]}" $((idx++)) "$bw"
                done
                printf '%s%*s%s' "$ls" $((tw - sp - bw * bn)) '' "$le" &&
                    (( ++ lines ))
            done
        }
        # shellcheck disable=SC2329,SC2086
        print_fg() { printf '\e[1;38;2;%sm %02x%02x%02x ' "$1" ${1//\;/ }; }
        # shellcheck disable=SC2329
        print_bg() { printf '\e[48;2;%sm%*s' "$1" "$3" ''; }
        print_space() { echo "$spacer" && (( ++ lines )) }

        print_space
        # center theme name followed by cursor
        (( ${#theme} < tw )) || theme="${theme:0:tw-4}..."
        printf '%s\e[1m%*s\e[5;38;2;%sm█%s%*s%s' \
            "$ls" $((tw / 2 + ${#theme} / 2)) "$theme" "$cur" "$ls" \
            $((tw / 2 - ${#theme} / 2 - 1 + tw % 2)) '' "$le" && (( ++ lines ))
        print_space

        print_block 8 8,4,2,1 print_fg "${colors16[@]:0:16}"
        print_space
        print_block 6 8,4,2,1 print_bg "${colors16[@]:0:16}"

        if (( ${#colors256[@]} )); then
            print_block 2 24,12,6,3 print_bg "${colors256[@]:232:24}"

            # sort palette into 6x6 blocks
            local colors216=() idx=0 bw=2 bn=0 bc
            for bc in 36 18 12 6; do
                (( tw < bc * bw )) || break
            done
            print_space
            while (( idx < 216 )); do
                colors216+=("${colors256[16+(idx++)]}")
                if (( ++bn == bc )); then
                    (( bn = 0, !(idx % 36) || (idx -= (bc / 6 - 1) * 36) ))
                else
                    (( idx % 6 || (idx += 30) ))
                fi
            done
            print_block "$bw" "$bc" print_bg "${colors216[@]}"
        fi
        print_space
    )

    # fill till bottom, fzf only, see $th
    while (( lines++ < th )); do
        echo "$spacer"
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

# fzf wrapper to be used by theme selector and bash completion
_tty_theme_fzf() {
    local fzf="${1:-fzf}" fzf_args=("${@:2}")
    command -v "$fzf" >/dev/null || return 1
    local cmd="$(printf '. %q &&' "${BASH_SOURCE[0]}")"
    SHELL="$BASH" \
        _TTY_THEME_LOAD_CONFIG=0 \
        TTY_THEME_AUTOLOAD=0 \
        TTY_THEME_COLOR256="${TTY_THEME_COLOR256:-}" \
        TTY_THEME_COLOR256_HARMONIOUS="${TTY_THEME_COLOR256_HARMONIOUS:-}" \
        TTY_THEME_UPDATE=0 \
        "$fzf" --reverse \
            --preview="$cmd _tty_theme_preview {}" \
            --preview-window='75%,right,noinfo,<68(67%,bottom)' \
            --bind=resize:refresh-preview \
            "${fzf_args[@]}" < <(_tty_theme_list | sort)
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
                FZF_COMPLETION_TRIGGER='' _tty_theme_fzf _fzf_complete -- "$@"
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
(( ! ${_TTY_THEME_LOAD_CONFIG:-1} )) ||
    [[ ! -f "${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme/config.sh" ]] ||
    . "${XDG_CONFIG_HOME:-"$HOME/.config"}/tty-theme/config.sh"

(( ! ${TTY_THEME_AUTOLOAD:-1} )) ||
    [[ -n "${TTY_THEME:-}${SUDO_TTY:-}${SSH_TTY:-}" ]] ||
    _tty_theme_restore
