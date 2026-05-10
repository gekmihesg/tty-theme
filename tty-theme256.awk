#!/bin/awk -f
# Translated from
#  https://github.com/jake-stewart/color256/blob/49ffa647eb71d4510a8c2876c74cd5ae48566c9b/color256.py
#
# Expects 16 colors on the first input line, optionally followed by foreground
# and background color. Further fields or lines are ignored.
# Variables pattern and harmonious can be passed to overwrite the default.
# The pattern must pick up index, red, green and blue.
#

function hex_to_num(hex,   c, i, n) {
    n = 0
    for (i = 1; i <= length(hex); i++) {
        c = substr(hex, i, 1)
        n = n * 16 + index("123456789abcdef", c)
    }
    return n
}

function hex_to_rgb(hex, rgb,   n) {
    n = hex_to_num(hex)
    rgb[0] = int(n / 2**16) % 2**8
    rgb[1] = int(n / 2**8) % 2**8
    rgb[2] = int(n) % 2**8
}

function rgb_to_lab(rgb, lab,   a, b, c, i) {
    hex_to_rgb(rgb, a)

    for (i in a) {
        c = a[i] / 255
        a[i] = (c <= 0.04045) ? (c / 12.92) : (((c + 0.055) / 1.055) ** 2.4)
    }

    b[0] = (a[0] * 0.4124 + a[1] * 0.3576 + a[2] * 0.1805) / 0.95047
    b[1] = (a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722) / 1.0
    b[2] = (a[0] * 0.0193 + a[1] * 0.1192 + a[2] * 0.9505) / 1.08883

    for (i in b) {
        a[i] = b[i] > 0.008856  ?  b[i] ** (1 / 3)  :  7.787 * b[i] + 16 / 116
    }

    lab[0] = 116 * a[1] - 16
    lab[1] = 500 * (a[0] - a[1])
    lab[2] = 200 * (a[1] - a[2])
}

function lab_to_rgb(lab, rgb,   a, b, c, i) {
    a[1] = (lab[0] + 16) / 116
    a[0] = lab[1] / 500 + a[1]
    a[2] = a[1] - lab[2] / 200

    for (i in a) {
        b[i] = a[i]**3 > 0.008856 ? a[i]**3 : (a[i] - 16/116) / 7.787
    }
    b[0] *= 0.95047; b[1] *= 1.0; b[2] *= 1.08883

    a[0] = b[0] * 3.2406 + b[1] * -1.5372 + b[2] * -0.4986
    a[1] = b[0] * -0.9689 + b[1] * 1.8758 + b[2] * 0.0415
    a[2] = b[0] * 0.0557 + b[1] * -0.2040 + b[2] * 1.0570

    for (i in a) {
        c = a[i]
        c = c <= 0.0031308 ? 12.92 * c : 1.055 * c**(1/2.4) - 0.055
        c = int(c * 255 + 0.5)
        rgb[i] = c < 0 ? 0 : c > 255 ? 255 : c
    }
}

function lerp_lab(t, lab1, lab2, lab,   i) {
    for (i = 0; i < 3; i++) {
        lab[i] = lab1[i] + t * (lab2[i] - lab1[i])
    }
}

NF >= 16 {
    for (i = 1; i <= 18 && i <= NF; i++) {
        $i = tolower($i)
        sub(/^(0x|#)/, "", $i)
        if ($i !~ /^[0-9a-f]+$/) exit 1
    }

    fg = NF >= 17 ? $17 : $8
    bg = NF >= 18 ? $18 : $1

    is_light_theme = hex_to_num(fg) < hex_to_num(bg)
    invert = is_light_theme && !harmonious

    if (!pattern) {
        pattern = "\033]4;%d;rgb:%02x/%02x/%02x\a"
    }

    rgb_to_lab(invert ? fg : bg, base8_lab0)
    rgb_to_lab($2, base8_lab1)
    rgb_to_lab($3, base8_lab2)
    rgb_to_lab($4, base8_lab3)
    rgb_to_lab($5, base8_lab4)
    rgb_to_lab($6, base8_lab5)
    rgb_to_lab($7, base8_lab6)
    rgb_to_lab(invert ? bg : fg, base8_lab7)

    idx = 0
    for (i = 0; i < 16; i++) {
        hex_to_rgb($(i+1), rgb)
        printf(pattern, idx++, rgb[0], rgb[1], rgb[2])
    }
    for (r = 0; r < 6; r++) {
        lerp_lab(r / 5, base8_lab0, base8_lab1, c0)
        lerp_lab(r / 5, base8_lab2, base8_lab3, c1)
        lerp_lab(r / 5, base8_lab4, base8_lab5, c2)
        lerp_lab(r / 5, base8_lab6, base8_lab7, c3)
        for (g = 0; g < 6; g++) {
            lerp_lab(g / 5, c0, c1, c4)
            lerp_lab(g / 5, c2, c3, c5)
            for (b = 0; b < 6; b++) {
                lerp_lab(b / 5, c4, c5, c6)
                lab_to_rgb(c6, rgb)
                printf(pattern, idx++, rgb[0], rgb[1], rgb[2])
            }
        }
    }
    for (i = 1; i < 25; i++) {
        lerp_lab(i / 25, base8_lab0, base8_lab7, c)
        lab_to_rgb(c, rgb)
        printf(pattern, idx++, rgb[0], rgb[1], rgb[2])
    }

    exit 0
}

{ exit 1 }
