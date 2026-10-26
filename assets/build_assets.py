#!/usr/bin/env python3
"""Builds the WinDebloat Tool icons - Material 3 Expressive look, all artwork drawn for this project
(MIT like the code; no Google logo, no Material Symbols glyphs copied).

  assets/icon.svg, assets/icon-small.svg   app icon (detailed >= 40 px, simplified <= 32 px)
  assets/WinDebloatTool.ico                16 20 24 32 40 48 64 128 256
  assets/icon-256.png, assets/icon-512.png README / store size
  assets/icons/svg/<name>.svg              button icons, 24x24 grid
  assets/icons/<name>_<16|20|24|32>.png    rendered button icons

Style: every button icon is a bold, rounded, filled glyph on a tonal container (light "90" tone behind a
"30/40" tone glyph), so it reads at 16 px on light and dark buttons. Hero actions (START, Simple START) and
Cancel use a strong "40" container with a white glyph. Containers come from a small M3-Expressive-like shape
set: soft squircle (default), 9-scallop cookie (hero), circle (cancel). Glyph geometry sits on a 3 px
grid where it matters (24 px grid -> 2 px steps at 16 px) so the 16 px render stays crisp.

Needs: python3, cairosvg, ImageMagick (magick) for the .ico.   Run:  python3 assets/build_assets.py
"""
import math, os, subprocess
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- palette (tonal, M3 style: 90 container / 30-40 on it)
PAL = {
    'violet': {'c': '#EADDFF', 'on': '#4F378B', 'strong': '#6750A4', 'deep': '#21005D'},
    'blue':   {'c': '#D3E3FF', 'on': '#0B57B0', 'strong': '#1B6EF3', 'deep': '#001B3E'},
    'green':  {'c': '#C4EED0', 'on': '#146C2E', 'strong': '#1E8E3E', 'deep': '#002106'},
    'orange': {'c': '#FFDBC8', 'on': '#8F3F00', 'strong': '#F26B1D', 'deep': '#331200'},
    'red':    {'c': '#FFDAD6', 'on': '#B3261E', 'strong': '#D3302F', 'deep': '#410002'},
    'neutral': {'c': '#E6E1EC', 'on': '#45464F', 'strong': '#5D5E67', 'deep': '#1B1B21'},
}
YELLOW = '#FFC94D'   # sparkles / accents
WHITE = '#FFFFFF'


# ---------------------------------------------------------------- shapes
def _poly(pts):
    return 'M' + ' L'.join('%.2f %.2f' % p for p in pts) + ' Z'


def squircle(cx, cy, r, n=4.2, steps=96):
    """superellipse |x|^n + |y|^n = r^n - the soft M3 'squircle'"""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** (2 / n), c), cy + r * math.copysign(abs(s) ** (2 / n), s)))
    return _poly(pts)


def cookie(cx, cy, r, k=9, depth=0.075, rot=-90, steps=240):
    """scalloped 'cookie' / 'clover' shape: r(t) = r * (1 - depth + depth * cos(k t))"""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        rr = r * (1 - depth + depth * math.cos(k * (t - math.radians(rot))))
        pts.append((cx + rr * math.cos(t), cy + rr * math.sin(t)))
    return _poly(pts)


def star4(cx, cy, r, w=0.36):
    """soft 4-point sparkle"""
    q = r * w
    return ('M{0} {1} Q{2} {3} {4} {3} Q{2} {3} {0} {5} Q{6} {3} {7} {3} Q{6} {3} {0} {1} Z'
            .format(cx, cy - r, cx + q * 0.25, cy, cx + r, cy + r, cx - q * 0.25, cx - r))


def container(kind, color):
    if kind == 'cookie':
        d = cookie(12, 12, 11.9, k=9, depth=0.07)
    elif kind == 'circle':
        return '<circle cx="12" cy="12" r="11.4" fill="%s"/>' % color
    else:
        d = squircle(12, 12, 11.4)
    return '<path d="%s" fill="%s"/>' % (d, color)


# ---------------------------------------------------------------- app icon
# Our own "four panes" (soft, clover-like: big outer radius, small inner radius, tilted) - not the Microsoft
# logo - on a scalloped cookie, with a bold broom sweeping across and two sparkles.
def pane(x, y, s, ro, ri, corner):
    """rounded square, outer corner `corner` (tl, tr, bl, br) with radius ro, others ri"""
    r = {k: ri for k in ('tl', 'tr', 'br', 'bl')}
    r[corner] = ro
    return ('M{0} {1} H{2} A{3} {3} 0 0 1 {4} {5} V{6} A{7} {7} 0 0 1 {8} {9} H{10} A{11} {11} 0 0 1 {12} {13} V{14} '
            'A{15} {15} 0 0 1 {16} {17} Z').format(
        x + r['tl'], y, x + s - r['tr'], r['tr'], x + s, y + r['tr'], y + s - r['br'], r['br'], x + s - r['br'], y + s,
        x + r['bl'], r['bl'], x, y + s - r['bl'], y + r['tl'], r['tl'], x + r['tl'], y)


def app_svg(size_class):
    big = size_class == 'big'
    V = 256 if big else 32
    k = V / 256.0
    f = lambda v: round(v * k, 2)
    bg = cookie(V / 2, V / 2, V / 2 - (2 if big else 0.4), k=12, depth=0.045) if big else squircle(16, 16, 15.6, n=4.6)
    s, g, x0, y0 = 80, 12, 38, 42          # pane size, gap, origin (256 grid)
    if not big:
        s, g, x0, y0 = 84, 14, 32, 34
    panes = [(x0, y0, 'tl', '#6750A4'), (x0 + s + g, y0, 'tr', '#1B6EF3'), (x0, y0 + s + g, 'bl', '#1B6EF3'), (x0 + s + g, y0 + s + g, 'br', '#6750A4')]
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {0} {0}" width="{0}" height="{0}">'.format(V)]
    out.append('  <path d="%s" fill="#EADDFF"/>' % bg)
    if big:
        out.append('  <path d="%s" fill="none" stroke="#D0BCFF" stroke-width="3"/>' % cookie(V / 2, V / 2, V / 2 - 12, k=12, depth=0.045))
    out.append('  <g transform="rotate(-8 %s %s)">' % (f(128), f(124)))
    for (x, y, c, col) in panes:
        out.append('    <path d="%s" fill="%s"/>' % (pane(f(x), f(y), f(s), f(s * 0.5), f(s * 0.16), c), col))
    out.append('  </g>')
    # broom: upright, then turned - handle to the top right, bristles at the bottom left
    if big:
        out.append('''  <g transform="translate(176 156) rotate(40)">
    <rect x="-11" y="-118" width="22" height="122" rx="11" fill="#331200"/>
    <rect x="-7" y="-114" width="14" height="114" rx="7" fill="#FFB68A"/>
    <rect x="-26" y="-6" width="52" height="24" rx="12" fill="#331200"/>
    <rect x="-22" y="-2" width="44" height="16" rx="8" fill="#D3302F"/>
    <path d="M-24 18 H24 Q34 50 42 84 Q42 92 34 94 Q0 104 -34 94 Q-42 92 -42 84 Q-34 50 -24 18 Z" fill="#331200"/>
    <path d="M-20 22 H20 Q29 52 36 82 Q36 88 30 89.5 Q0 98 -30 89.5 Q-36 88 -36 82 Q-29 52 -20 22 Z" fill="#F26B1D"/>
    <path d="M-12 30 Q-16 60 -19 86 M0 30 V92 M12 30 Q16 60 19 86" stroke="#FFB68A" stroke-width="7" stroke-linecap="round" fill="none"/>
  </g>''')
        out.append('  <path d="%s" fill="%s" stroke="#331200" stroke-width="5" stroke-linejoin="round"/>' % (star4(212, 64, 26), YELLOW))
        out.append('  <path d="%s" fill="#FFFFFF" stroke="#331200" stroke-width="4" stroke-linejoin="round"/>' % star4(54, 214, 17))
    else:
        out.append('''  <g transform="translate(22.5 19.8) rotate(40)">
    <rect x="-2.1" y="-16.5" width="4.2" height="17" rx="2.1" fill="#331200"/>
    <rect x="-0.9" y="-15.3" width="1.8" height="15" rx="0.9" fill="#FFB68A"/>
    <path d="M-4.4 0 H4.4 L6.6 10.2 Q0 12.4 -6.6 10.2 Z" fill="#F26B1D" stroke="#331200" stroke-width="1.3" stroke-linejoin="round"/>
    <rect x="-4.6" y="-1.6" width="9.2" height="3.6" rx="1.8" fill="#D3302F" stroke="#331200" stroke-width="1"/>
  </g>''')
        # no sparkle below 40 px: it turns into noise at 16 px
    out.append('</svg>\n')
    return '\n'.join(out)


APP = app_svg('big')
APP_SMALL = app_svg('small')

# ---------------------------------------------------------------- button icons (24x24)
# (container shape, palette, strong?, glyph) - glyphs use {on} (glyph colour) and {bg} (container colour)
RS = 'stroke-linecap="round" stroke-linejoin="round"'
ICONS_DEF = {
    # folders / files: orange
    'folder': ('squircle', 'orange', False,
               '<path d="M4.5 7.5A1.5 1.5 0 0 1 6 6h3.9l1.8 1.8H18a1.5 1.5 0 0 1 1.5 1.5V16.5A1.5 1.5 0 0 1 18 18H6a1.5 1.5 0 0 1-1.5-1.5z" fill="{on}"/>'),
    'folder-open': ('squircle', 'orange', False,
                    '<path d="M5 16V8a1.5 1.5 0 0 1 1.5-1.5h3.4l1.8 1.8h4.8A1.5 1.5 0 0 1 18 9.8V11" fill="none" stroke="{on}" stroke-width="2.2" ' + RS + '/>'
                    '<path d="M7.6 11h12.2a.9.9 0 0 1 .85 1.2l-1.9 4.9A1.5 1.5 0 0 1 17.4 18H5.3a.8.8 0 0 1-.75-1.1l1.95-5.1A1.2 1.2 0 0 1 7.6 11z" fill="{on}"/>'),
    'package': ('squircle', 'orange', False,
                '<path d="M12 4.6 18.6 8v8L12 19.4 5.4 16V8z" fill="{on}" stroke="{on}" stroke-width="1.6" stroke-linejoin="round"/>'
                '<path d="M5.8 8.2 12 11.4l6.2-3.2M12 11.4v7.4" fill="none" stroke="{bg}" stroke-width="1.7" ' + RS + '/>'),
    # actions on blue
    'save': ('squircle', 'blue', False,
             '<path d="M4.5 6A1.5 1.5 0 0 1 6 4.5h9.6l3.9 3.9V18a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 18z" fill="{on}"/>'
             '<rect x="7.5" y="4.5" width="6" height="3" rx=".6" fill="{bg}"/><rect x="7.5" y="12" width="9" height="7.5" rx="1.5" fill="{bg}"/>'),
    'download': ('squircle', 'blue', False,
                 '<path d="M12 4.8v8.4M7.8 9.4l4.2 4.2 4.2-4.2" fill="none" stroke="{on}" stroke-width="3" ' + RS + '/>'
                 '<rect x="6" y="16.5" width="12" height="3" rx="1.5" fill="{on}"/>'),
    'refresh': ('squircle', 'blue', False,
                '<path d="M17.6 13a5.7 5.7 0 1 1-1.9-5.3" fill="none" stroke="{on}" stroke-width="2.6" stroke-linecap="round"/>'
                '<path d="M19 4.4v5.4h-5.4z" fill="{on}" stroke="{on}" stroke-width="1.2" stroke-linejoin="round"/>'),
    'globe': ('squircle', 'blue', False,
              '<circle cx="12" cy="12" r="7" fill="{on}"/>'
              '<path d="M12 5.4c-2.6 3.4-2.6 9.8 0 13.2M12 5.4c2.6 3.4 2.6 9.8 0 13.2M5.6 12h12.8" fill="none" stroke="{bg}" stroke-width="1.5" stroke-linecap="round"/>'),
    'eye': ('squircle', 'blue', False,
            '<path d="M3.8 12C5.6 8.6 8.6 6.6 12 6.6s6.4 2 8.2 5.4c-1.8 3.4-4.8 5.4-8.2 5.4S5.6 15.4 3.8 12z" fill="{on}"/>'
            '<circle cx="12" cy="12" r="3.2" fill="{bg}"/><circle cx="12" cy="12" r="1.5" fill="{on}"/>'),
    'check-all': ('squircle', 'blue', False,
                  '<rect x="4.5" y="4.5" width="15" height="15" rx="4.2" fill="{on}"/>'
                  '<path d="M8.4 12.2l2.5 2.5 4.8-5.2" fill="none" stroke="{bg}" stroke-width="2.4" ' + RS + '/>'),
    # neutral tools
    'clear-all': ('squircle', 'neutral', False,
                  '<rect x="6" y="6" width="12" height="12" rx="3" fill="none" stroke="{on}" stroke-width="3"/>'),
    'reset': ('squircle', 'neutral', False,
              '<path d="M6.4 13a5.7 5.7 0 1 0 1.9-5.3" fill="none" stroke="{on}" stroke-width="2.6" stroke-linecap="round"/>'
              '<path d="M5 4.4v5.4h5.4z" fill="{on}" stroke="{on}" stroke-width="1.2" stroke-linejoin="round"/>'
              '<circle cx="12" cy="13" r="1.8" fill="{on}"/>'),
    'wrench': ('squircle', 'neutral', False,
               '<path d="M14.9 4.8a4.4 4.4 0 0 0-4.6 5.9l-5 5a1.9 1.9 0 0 0 2.7 2.7l5-5a4.4 4.4 0 0 0 5.9-4.6l-2.6 2.6-2.7-.7-.7-2.7z" fill="{on}" stroke="{on}" stroke-width="1" stroke-linejoin="round"/>'),
    'sliders': ('squircle', 'violet', False,
                '<path d="M5.5 7.5h13M5.5 16.5h13" stroke="{on}" stroke-width="3" stroke-linecap="round"/>'
                '<circle cx="9" cy="7.5" r="3.4" fill="{on}" stroke="{bg}" stroke-width="1.5"/>'
                '<circle cx="15" cy="16.5" r="3.4" fill="{on}" stroke="{bg}" stroke-width="1.5"/>'),
    # status
    'shield-check': ('squircle', 'green', False,
                     '<path d="M12 4.4l6.4 2.5v4.7c0 3.7-2.6 6.6-6.4 7.8-3.8-1.2-6.4-4.1-6.4-7.8V6.9z" fill="{on}" stroke="{on}" stroke-width="1" stroke-linejoin="round"/>'
                     '<path d="M9 11.8l2.2 2.2 4-4.3" fill="none" stroke="{bg}" stroke-width="2.2" ' + RS + '/>'),
    'stop': ('circle', 'red', True,
             '<path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" stroke="#FFFFFF" stroke-width="2.8" stroke-linecap="round"/>'),
    # hero actions: strong container, white glyph, warm accent
    'broom': ('cookie', 'violet', True,
              '<g transform="rotate(40 12 12)"><rect x="10.8" y="2.6" width="2.4" height="9" rx="1.2" fill="#FFFFFF"/>'
              '<path d="M8.6 12.4h6.8l1.7 6.6q-5.1 1.8-10.2 0z" fill="#FFB68A" stroke="#FFFFFF" stroke-width="1.2" stroke-linejoin="round"/>'
              '<rect x="8.4" y="10.6" width="7.2" height="2.6" rx="1.3" fill="#FFFFFF"/></g>'),
    'rocket': ('cookie', 'orange', True,
               '<g transform="rotate(45 12 12)">'
               '<path d="M12 2.6c3.3 2.2 4.6 6 3.7 10.4l-1.4 2.6H9.7l-1.4-2.6C7.4 8.6 8.7 4.8 12 2.6z" fill="#FFFFFF"/>'
               '<circle cx="12" cy="8.6" r="1.9" fill="{strong}"/>'
               '<path d="M8.4 11.4 5.6 14.6l.6 3 3.2-2zM15.6 11.4l2.8 3.2-.6 3-3.2-2z" fill="#FFFFFF"/>'
               '<path d="M10 16.4h4L12 21z" fill="' + YELLOW + '" stroke="' + YELLOW + '" stroke-width="1.2" stroke-linejoin="round"/></g>'),
}


def icon_svg(name):
    shape, pal, strong, glyph = ICONS_DEF[name]
    p = PAL[pal]
    bgc = p['strong'] if strong else p['c']
    g = glyph.replace('{on}', p['on']).replace('{bg}', bgc).replace('{strong}', p['strong'])
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\n  %s\n  %s\n</svg>\n' % (container(shape, bgc), g)


ICONS = {n: icon_svg(n) for n in ICONS_DEF}
SIZES_BTN = [16, 20, 24, 32]
SIZES_ICO = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def render(svg, size, path):
    cairosvg.svg2png(bytestring=svg.encode(), write_to=path, output_width=size, output_height=size)


def main():
    with open(os.path.join(HERE, 'icon.svg'), 'w', newline='\n') as f: f.write(APP)
    with open(os.path.join(HERE, 'icon-small.svg'), 'w', newline='\n') as f: f.write(APP_SMALL)
    tmp = os.path.join(HERE, '_ico')
    os.makedirs(tmp, exist_ok=True)
    parts = []
    for s in SIZES_ICO:
        p = os.path.join(tmp, '%d.png' % s)
        render(APP_SMALL if s <= 32 else APP, s, p)
        parts.append(p)
    for s in (256, 512):
        render(APP, s, os.path.join(HERE, 'icon-%d.png' % s))
    # ImageMagick: 32-bit BMP entries up to 128 px (readable by .NET 2.0's Icon class), PNG for 256
    subprocess.check_call(['magick'] + parts + [os.path.join(HERE, 'WinDebloatTool.ico')])
    for p in parts: os.remove(p)
    os.rmdir(tmp)
    idir = os.path.join(HERE, 'icons')
    for name, svg in ICONS.items():
        with open(os.path.join(idir, 'svg', name + '.svg'), 'w', newline='\n') as f: f.write(svg)
        for s in SIZES_BTN:
            render(svg, s, os.path.join(idir, '%s_%d.png' % (name, s)))
    print('ok: %d button icons x %d sizes, app icon %s' % (len(ICONS), len(SIZES_BTN), SIZES_ICO))


if __name__ == '__main__':
    main()
