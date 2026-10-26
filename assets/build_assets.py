#!/usr/bin/env python3
"""Builds the WinDebloat Tool icons (all artwork drawn for this project, MIT like the code; no Google logo, no
Material Symbols glyphs copied - the button icons only follow the "Rounded" look: round caps/joins, one weight).

  assets/icon.svg, assets/icon-small.svg   app icon (detailed >= 40 px, simplified <= 32 px) - option A by default
  assets/WinDebloatTool.ico                16 20 24 32 40 48 64 128 256
  assets/icon-256.png, assets/icon-512.png README / store size
  assets/alt/icon-<a|b>[-small].svg, assets/alt/icon-<a|b>-512.png   both app-icon options, for comparison
  assets/icons/svg/<name>.svg              button icons, 24x24 grid (24 px weight)
  assets/icons/<name>_<16|20|24|32>.png    rendered button icons (stroke weight tuned per size)

App icon: one indigo tonal family, soft gradient, faint layered shadow, no outlines.
  A  "Night"  deep indigo squircle, three light panes, the fourth pane swept away by a minimal broom (warm accent)
  B  "Paper"  pale lavender arch, three indigo panes, the fourth replaced by an indigo broom and a soft sweep
Button icons: monochrome #1F1F23 (follows the light button text), round caps, the same stroke weight on every
icon (1.5 px at 16, 1.75 at 20, 2 at 24, 2.5 at 32), 3 px padding on the 24 grid. Only START / START (Simple)
use the brand indigo, Cancel a muted red.

Needs: python3, cairosvg, ImageMagick (magick) for the .ico.
Run:  python3 assets/build_assets.py [A|B]     (A = default app icon)
"""
import os, subprocess, sys
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- palette (indigo tonal family + one accent)
INDIGO = {'950': '#15173F', '900': '#1E2257', '800': '#262B72', '700': '#333A99', '600': '#4C55C7', '500': '#6670DB',
          '400': '#8C93F0', '300': '#AEB3F7', '200': '#CDD0FF', '100': '#E6E7FF', '50': '#F5F5FF'}
ACCENT = ('#FFC8A8', '#FF9F7A')   # warm apricot, only on the broom head of option A
INK = '#1F1F23'                   # button glyphs (light buttons)
BRAND = INDIGO['600']             # START / START (Simple)
MUTED_RED = '#B3463C'             # Cancel


def squircle(cx, cy, r, n=5.0, steps=120):
    import math
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** (2 / n), c), cy + r * math.copysign(abs(s) ** (2 / n), s)))
    return 'M' + ' L'.join('%.2f %.2f' % p for p in pts) + ' Z'


def arch(x0, y0, x1, y1, rt, rb):
    """M3 'arch': big round top corners, smaller bottom corners"""
    return ('M{a} {y0} H{b} A{rt} {rt} 0 0 1 {x1} {c} V{d} A{rb} {rb} 0 0 1 {e} {y1} H{f} A{rb} {rb} 0 0 1 {x0} {d} V{c} '
            'A{rt} {rt} 0 0 1 {a} {y0} Z').format(a=x0 + rt, b=x1 - rt, c=y0 + rt, d=y1 - rb, e=x1 - rb, f=x0 + rb,
                                                 x0=x0, x1=x1, y0=y0, y1=y1, rt=rt, rb=rb)


def rrect(x, y, w, h, r, fill, extra=''):
    return '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="%s"%s/>' % (x, y, w, h, r, fill, extra)


# ---------------------------------------------------------------- app icons
def app_icon(option, small):
    V = 32.0 if small else 256.0
    k = V / 256.0
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %g %g" width="%g" height="%g">' % (V, V, V, V)]
    dark = option == 'A'
    out.append('''  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">%s</linearGradient>
    <linearGradient id="hl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="%s"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
    <linearGradient id="acc" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
    <linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s" stop-opacity="0"/><stop offset="1" stop-color="%s" stop-opacity="0.85"/></linearGradient>
  </defs>''' % (
        ('<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>' % (INDIGO['600'], INDIGO['900'])) if dark else
        ('<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>' % (INDIGO['50'], INDIGO['200'])),
        '0.16' if dark else '0.7', ACCENT[0], ACCENT[1], INDIGO['400'], INDIGO['400']))
    # container
    if dark:
        shape = squircle(V / 2, V / 2, V / 2 - (0.5 if small else 6), n=5.0)
    else:
        m = 0.5 if small else 8
        shape = arch(m, m, V - m, V - m, (V - 2 * m) * (0.42 if not small else 0.38), (V - 2 * m) * 0.2)
    if not small:   # faint grounding shadow under the container (layered, no blur filter needed)
        for dy, op in ((6, 0.05), (3, 0.06)):
            out.append('  <path d="%s" fill="%s" fill-opacity="%s" transform="translate(0 %d)"/>' % (shape, INDIGO['950'], op, dy))
    out.append('  <path d="%s" fill="url(#bg)"/>' % shape)
    out.append('  <path d="%s" fill="url(#hl)"/>' % shape)
    # panes (2 x 2, three shown, the fourth swept away)
    if small:
        x0, y0, s, g, r = 7.0, 7.0, 8.2, 1.6, 2.2
    else:
        x0, y0, s, g, r = 58.0, 58.0, 64.0, 12.0, 17.0
    if dark:
        cols = ['#FFFFFF', INDIGO['200'], INDIGO['300']]
        ghost = ('#FFFFFF', 0.10)
    else:
        cols = [INDIGO['700'], INDIGO['500'], INDIGO['400']]
        ghost = (INDIGO['600'], 0.10)
    pos = [(x0, y0), (x0 + s + g, y0), (x0, y0 + s + g)]
    if not small:   # soft depth below the panes
        sh = INDIGO['950'] if dark else INDIGO['700']
        for (px, py) in pos:
            out.append(rrect(px, py + 5, s, s, r, sh, ' fill-opacity="%s"' % ('0.22' if dark else '0.10')))
    for (px, py), c in zip(pos, cols):
        out.append(rrect(px, py, s, s, r, c))
    gx, gy = x0 + s + g, y0 + s + g
    if not small:
        out.append(rrect(gx, gy, s, s, r, ghost[0], ' fill-opacity="%s"' % ghost[1]))
    # broom: sweeps across the fourth pane (drawn upright in a local frame, then turned 45 degrees)
    if small:
        bx, by, sc = gx + s * 0.55, gy + s * 0.45, k * 8.0 / 8.0
        hand = INDIGO['100'] if dark else INDIGO['800']
        head = 'url(#acc)' if dark else INDIGO['800']
        out.append('''  <g transform="translate(%.2f %.2f) rotate(45)">
    <rect x="-1.15" y="-10.5" width="2.3" height="9.5" rx="1.15" fill="%s"/>
    <path d="M-3.2 -0.6 H3.2 L4.6 5.6 Q0 7.2 -4.6 5.6 Z" fill="%s"/>
  </g>''' % (bx, by, hand, head))
    else:
        bx, by = gx + s * 0.70, gy + s * 0.36
        hand = INDIGO['100'] if dark else INDIGO['800']
        head = 'url(#acc)' if dark else INDIGO['800']
        band = INDIGO['200'] if dark else INDIGO['600']
        if not dark:   # soft sweep under the broom
            out.append('  <path d="M%.1f %.1f Q%.1f %.1f %.1f %.1f" fill="none" stroke="url(#sweep)" stroke-width="9" stroke-linecap="round"/>'
                       % (gx - 10, gy + s + 2, gx + s * 0.45, gy + s + 12, gx + s + 14, gy + s - 6))
        out.append('''  <g transform="translate(%.1f %.1f) rotate(45)">
    <rect x="-6" y="-74" width="12" height="62" rx="6" fill="%s"/>
    <rect x="-17" y="-16" width="34" height="13" rx="6.5" fill="%s"/>
    <path d="M-17 1 H17 Q22 1 23.2 6 L29 34 Q30 40 24 41.4 Q0 47 -24 41.4 Q-30 40 -29 34 L-23.2 6 Q-22 1 -17 1 Z" fill="%s"/>
  </g>''' % (bx, by, hand, band, head))
    out.append('</svg>\n')
    return '\n'.join(out)


# ---------------------------------------------------------------- button icons (24 grid, stroke weight per size)
SW_PX = {16: 1.5, 20: 1.75, 24: 2.0, 32: 2.5}


def glyph(name, sw):
    C = INK
    if name in ('broom', 'rocket'):
        C = BRAND
    if name == 'stop':
        C = MUTED_RED
    st = 'fill="none" stroke="%s" stroke-width="%.3f" stroke-linecap="round" stroke-linejoin="round"' % (C, sw)
    fl = 'fill="%s"' % C
    g = {
        'folder': '<path d="M3.5 7A1.5 1.5 0 0 1 5 5.5h3.9l1.8 1.8H19a1.5 1.5 0 0 1 1.5 1.5v8.7A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5z" %s/>' % fl,
        'folder-open': '<path d="M4 18.2V7a1.5 1.5 0 0 1 1.5-1.5h3.4l1.8 1.8h6.8A1.5 1.5 0 0 1 19 8.8V10.5" %s/>'
                       '<path d="M6.6 10.8h13.9a.9.9 0 0 1 .86 1.16l-1.85 6A1.5 1.5 0 0 1 18.07 19H4.6a.8.8 0 0 1-.76-1.05l1.9-6.5a.9.9 0 0 1 .86-.65z" %s/>' % (st, fl),
        'save': '<path d="M5.5 4.5h10.3l3.7 3.7v10.3a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1z" %s/>'
                '<path d="M8 4.8v3.4h6V4.8" %s/><circle cx="12" cy="14.5" r="2.3" %s/>' % (st, st, fl),
        'download': '<path d="M12 4.5v10M7.8 10.5 12 14.7l4.2-4.2M5 19.5h14" %s/>' % st,
        'refresh': '<path d="M19.3 12.6A7.3 7.3 0 1 1 17.2 7" %s/><path d="M19.5 4v4.5H15" %s/>' % (st, st),
        'reset': '<path d="M4.7 12.6A7.3 7.3 0 1 0 6.8 7" %s/><path d="M4.5 4v4.5H9" %s/>' % (st, st),
        'globe': '<circle cx="12" cy="12" r="8.5" %s/><ellipse cx="12" cy="12" rx="3.6" ry="8.5" %s/><path d="M3.5 12h17" %s/>' % (st, st, st),
        'eye': '<path d="M2.8 12C4.8 8 8.1 6 12 6s7.2 2 9.2 6c-2 4-5.3 6-9.2 6s-7.2-2-9.2-6z" %s/><circle cx="12" cy="12" r="3" %s/>' % (st, fl),
        'check-all': '<rect x="4" y="4" width="16" height="16" rx="3.5" %s/><path d="M8.2 12.3l2.6 2.6 5-5.3" %s/>' % (st, st),
        'clear-all': '<rect x="4" y="4" width="16" height="16" rx="3.5" %s/>' % st,
        'shield-check': '<path d="M12 3.6 18.8 6.3v5c0 4-2.8 7.4-6.8 8.8-4-1.4-6.8-4.8-6.8-8.8v-5z" %s/><path d="M9.1 11.9l2.1 2.1 3.9-4.1" %s/>' % (st, st),
        'wrench': '<path d="M14.7 4.2a4.7 4.7 0 0 0-4.6 6.2l-5.3 5.3a2 2 0 0 0 2.9 2.9l5.3-5.3a4.7 4.7 0 0 0 6.2-4.6l-2.7 2.7-2.6-.6-.6-2.6z" %s stroke="%s" stroke-width="%.3f" stroke-linejoin="round"/>' % (fl, C, sw * 0.45),
        'sliders': '<path d="M4 8h16M4 16h16" %s/><circle cx="9" cy="8" r="2.6" %s/><circle cx="15" cy="16" r="2.6" %s/>' % (st, fl, fl),
        'package': '<path d="M12 3.6 19.5 7.6v8.8L12 20.4l-7.5-4V7.6z" %s/><path d="M4.8 7.8 12 11.7l7.2-3.9M12 11.7v8.5" %s/>' % (st, st),
        'stop': '<circle cx="12" cy="12" r="8.5" %s/><path d="M9.2 9.2l5.6 5.6M14.8 9.2l-5.6 5.6" %s/>' % (st, st),
        'broom': '<g transform="translate(12 12) scale(1.1) translate(-12 -12) rotate(42 12 12)"><path d="M12 2v8" %s/>'
                 '<rect x="8.6" y="9.4" width="6.8" height="2.6" rx="1.3" %s/>'
                 '<path d="M8.7 13.2h6.6l1.6 6.2q-5 1.8-9.8 0z" %s stroke="%s" stroke-width="%.3f" stroke-linejoin="round"/></g>' % (st, fl, fl, C, sw * 0.5),
        'rocket': '<g transform="translate(12 12) scale(1.12) translate(-12 -12) rotate(45 12 12)">'
                  '<path fill-rule="evenodd" d="M12 2.6c3.2 2.2 4.5 6 3.6 10.4l-1.4 2.6H9.8l-1.4-2.6C7.5 8.6 8.8 4.8 12 2.6zM13.8 8.8a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0z" %s/>'
                  '<path d="M8.5 11.6 5.8 14.6l.5 2.8 3.1-1.9zM15.5 11.6l2.7 3-.5 2.8-3.1-1.9z" %s/>'
                  '<path d="M10.6 17.4h2.8L12 20.6z" %s stroke="%s" stroke-width="%.3f" stroke-linejoin="round"/></g>' % (fl, fl, fl, C, sw * 0.4),
    }[name]
    return g


NAMES = ['broom', 'check-all', 'clear-all', 'download', 'eye', 'folder', 'folder-open', 'globe', 'package', 'refresh',
         'reset', 'rocket', 'save', 'shield-check', 'sliders', 'stop', 'wrench']


def icon_svg(name, size=24):
    sw = SW_PX[size] * 24.0 / size
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\n  %s\n</svg>\n' % glyph(name, sw)


SIZES_BTN = [16, 20, 24, 32]
SIZES_ICO = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def render(svg, size, path):
    cairosvg.svg2png(bytestring=svg.encode(), write_to=path, output_width=size, output_height=size)


def write(path, text):
    with open(path, 'w', newline='\n') as f: f.write(text)


def main():
    default = (sys.argv[1] if len(sys.argv) > 1 else 'A').upper()
    alt = os.path.join(HERE, 'alt')
    os.makedirs(alt, exist_ok=True)
    for o in ('A', 'B'):
        write(os.path.join(alt, 'icon-%s.svg' % o.lower()), app_icon(o, False))
        write(os.path.join(alt, 'icon-%s-small.svg' % o.lower()), app_icon(o, True))
        render(app_icon(o, False), 512, os.path.join(alt, 'icon-%s-512.png' % o.lower()))
    APP, APP_SMALL = app_icon(default, False), app_icon(default, True)
    write(os.path.join(HERE, 'icon.svg'), APP)
    write(os.path.join(HERE, 'icon-small.svg'), APP_SMALL)
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
    for name in NAMES:
        write(os.path.join(idir, 'svg', name + '.svg'), icon_svg(name, 24))
        for s in SIZES_BTN:
            render(icon_svg(name, s), s, os.path.join(idir, '%s_%d.png' % (name, s)))
    print('ok: app icon %s (+ alt A/B), %d button icons x %d sizes' % (default, len(NAMES), len(SIZES_BTN)))


if __name__ == '__main__':
    main()
