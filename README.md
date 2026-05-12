# tty-theme

Yet another tool to customize your TTY's color palette. This one tries to have
minimal dependencies. It uses terminal control sequences to set the colors and
should work on most modern terminal emulators.

## TL;DR

Source `tty-theme.bash` in your `.bashrc`, type `tty-theme <TAB>` and select
a theme.

https://github.com/user-attachments/assets/eda2cfe8-7354-4a03-bdb5-c73d97a248ed

## Requirements

The only definite requirement is `bash`.

For theme selection [`fzf`][1] is recommended, it provides an interactive theme
selector with preview through its completion feature. If `fzf` is not available,
`tty-theme-preview` can be used for preview.

By default, the database is automatically downloaded from the [Gogh project][2]
([csv][3]). For that, `curl` is required.

Finally, for generating the 256 color palette from the base colors according to
[Jake Stewart's write-up][4], a POSIX `awk` is needed.

## Structure

The `~/.config/tty-theme/config.sh` can be used to make some adjustments
(see `config.sh.example`). Although, those variables can come from anywhere
else and can also be changed at runtime.

The database is downloaded to and converted to `~/.cache/tty-theme/themes.csv`.
A custom database can be provided in `~/.config/tty-theme/themes.csv` instead.

The format has to be CSV, separated by `,` and unquoted. The fields have to be
`name`, `color 1` to `color 16` and optionally `foreground`, `background` and
`cursor` color.

The current theme is stored in `~/.config/tty-theme/default.theme`. When the
main script is sourced, this is automatically applied by default, unless a
preferred `$TERM.theme` or `${TERM%%-*}.theme` exists. This feature does not
require the database, all colors are stored within the theme.
The theme is _not_ auto loaded if `$SSH_TTY` or `$SUDO_TTY` is are set.
The name of the current theme is stored in `$TTY_THEME` and the colors are in
`$TTY_THEME_COLORS`.

If a command or function `_tty_theme_post` is defined, it gets executed after
applying the theme and before saving it. It gets the theme colors as parameters.


[1]: https://github.com/junegunn/fzf
[2]: https://github.com/Gogh-Co/Gogh
[3]: https://raw.githubusercontent.com/Gogh-Co/Gogh/master/data/themes.csv
[4]: https://gist.github.com/jake-stewart/0a8ea46159a7da2c808e5be2177e1783
