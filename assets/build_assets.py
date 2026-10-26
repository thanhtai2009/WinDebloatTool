#!/usr/bin/env python3
"""Builds the WinDebloat Tool icons (all artwork drawn for this project, MIT like the code).

  assets/icon.svg, assets/icon-small.svg   app icon (detailed >= 40 px, simplified <= 32 px)
  assets/WinDebloatTool.ico                16 20 24 32 40 48 64 128 256
  assets/icon-256.png, assets/icon-512.png README / store size
  assets/icons/svg/<name>.svg              button icons, 24x24 grid
  assets/icons/<name>_<16|20|24|32>.png    rendered button icons

Needs: python3, cairosvg, ImageMagick (magick) for the .ico.   Run:  python3 assets/build_assets.py
"""
import os, subprocess, io
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- app icon
# Our own stylised "window panes" (tilted, rounded, one shared gradient, unequal gaps) - not the Microsoft logo -
# with a broom sweeping across them and a few sparkles / dust.
APP = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="pane" x1="30" y1="20" x2="200" y2="210" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#7AD7FF"/><stop offset="0.45" stop-color="#2B9AF3"/><stop offset="1" stop-color="#0A4FB4"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.45"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="handle" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#D99A5B"/><stop offset="1" stop-color="#8E5626"/>
    </linearGradient>
    <linearGradient id="bristle" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFD15C"/><stop offset="1" stop-color="#F08C1A"/>
    </linearGradient>
  </defs>
  <g transform="rotate(-11 118 122)">
    <rect x="34" y="38" width="76" height="76" rx="16" fill="url(#pane)"/>
    <rect x="120" y="38" width="76" height="76" rx="16" fill="url(#pane)"/>
    <rect x="34" y="124" width="76" height="76" rx="16" fill="url(#pane)"/>
    <rect x="120" y="124" width="76" height="76" rx="16" fill="url(#pane)"/>
    <rect x="40" y="42" width="64" height="30" rx="12" fill="url(#shine)"/>
    <rect x="126" y="42" width="64" height="30" rx="12" fill="url(#shine)"/>
  </g>
  <!-- broom, drawn upright then turned: handle to the top right, bristles sweeping at the bottom left -->
  <g transform="translate(170 150) rotate(42)">
    <rect x="-8" y="-106" width="16" height="110" rx="8" fill="url(#handle)" stroke="#5E3612" stroke-width="3"/>
    <rect x="-21" y="-2" width="42" height="18" rx="5" fill="#C42B1C" stroke="#7A1A10" stroke-width="3"/>
    <path d="M-20 16 H20 L36 86 Q0 100 -36 86 Z" fill="url(#bristle)" stroke="#8A4B08" stroke-width="3" stroke-linejoin="round"/>
    <path d="M-10 22 L-18 86 M0 22 L0 91 M10 22 L18 86" stroke="#B8650C" stroke-width="3.5" stroke-linecap="round" fill="none"/>
  </g>
  <!-- dust swept away + sparkles -->
  <g fill="#9FB3C8"><circle cx="58" cy="226" r="7"/><circle cx="36" cy="208" r="5"/><circle cx="30" cy="232" r="4"/></g>
  <path d="M214 176 l6 15 15 6 -15 6 -6 15 -6 -15 -15 -6 15 -6 z" fill="#FFFFFF" stroke="#2B9AF3" stroke-width="3" stroke-linejoin="round"/>
  <path d="M232 132 l3.5 8.5 8.5 3.5 -8.5 3.5 -3.5 8.5 -3.5 -8.5 -8.5 -3.5 8.5 -3.5 z" fill="#FFD15C" stroke="#E08A00" stroke-width="2" stroke-linejoin="round"/>
</svg>
'''

# simplified for 16-32 px: fewer details, thicker shapes, no gradients that turn to mud
APP_SMALL = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">
  <defs>
    <linearGradient id="p" x1="3" y1="3" x2="26" y2="27" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#4CC2FF"/><stop offset="1" stop-color="#0F5FC4"/>
    </linearGradient>
  </defs>
  <g transform="rotate(-11 14.5 15)">
    <rect x="3" y="4" width="10.5" height="10.5" rx="2.4" fill="url(#p)"/>
    <rect x="15" y="4" width="10.5" height="10.5" rx="2.4" fill="url(#p)"/>
    <rect x="3" y="16" width="10.5" height="10.5" rx="2.4" fill="url(#p)"/>
    <rect x="15" y="16" width="10.5" height="10.5" rx="2.4" fill="url(#p)"/>
  </g>
  <g transform="translate(22 19) rotate(42)">
    <rect x="-1.4" y="-17" width="2.8" height="17.5" rx="1.4" fill="#A86A33" stroke="#5E3612" stroke-width="0.9"/>
    <path d="M-3.6 0 H3.6 L6.2 10 Q0 12 -6.2 10 Z" fill="#FFB900" stroke="#8A4B08" stroke-width="1" stroke-linejoin="round"/>
    <rect x="-3.8" y="-1" width="7.6" height="2.6" rx="0.8" fill="#C42B1C"/>
  </g>
</svg>
'''

# ---------------------------------------------------------------- button icons (24x24, Fluent-like colours)
INK = '#323130'
SW = 'stroke="%s" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"' % INK
ICONS = {
    'folder-open': f'''<path d="M3 19V6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h7.5A1.5 1.5 0 0 1 20 8.5V10" fill="#E8A317" {SW}/>
  <path d="M2.7 19.2 5.1 11.3A1.8 1.8 0 0 1 6.8 10h14.4a.9.9 0 0 1 .86 1.16l-2.3 7.6A1.8 1.8 0 0 1 18 20H3.5a.8.8 0 0 1-.8-.8z" fill="#FFC83D" {SW}/>''',
    'folder': f'''<path d="M3 18.5V6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h8.5A1.5 1.5 0 0 1 21 8.5v10a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z" fill="#FFC83D" {SW}/>
  <path d="M3 10h18" {SW} fill="none"/>''',
    'save': f'''<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H16l4 4v10.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5z" fill="#0F6CBD" {SW}/>
  <rect x="8" y="4" width="7" height="5" fill="#DCEBFA" {SW}/>
  <rect x="7" y="13" width="10" height="7" fill="#FFFFFF" {SW}/>''',
    'globe': f'''<circle cx="12" cy="12" r="9" fill="#4CC2FF" {SW}/>
  <ellipse cx="12" cy="12" rx="3.8" ry="9" fill="none" {SW}/>
  <path d="M3 12h18M4.6 7.5h14.8M4.6 16.5h14.8" fill="none" {SW}/>''',
    'refresh': '''<path d="M19.2 12.5A7.2 7.2 0 1 1 17 7.2" fill="none" stroke="#0F6CBD" stroke-width="2.3" stroke-linecap="round"/>
  <path d="M18.5 3.5v4.8h-4.8" fill="none" stroke="#0F6CBD" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>''',
    'download': f'''<path d="M12 3.5v10.5M7.5 9.8 12 14.3l4.5-4.5" fill="none" stroke="#0F6CBD" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M4 15.5v3A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-3" fill="none" {SW}/>''',
    'reset': '''<path d="M4.8 12.5A7.2 7.2 0 1 0 7 7.2" fill="none" stroke="#605E5C" stroke-width="2.3" stroke-linecap="round"/>
  <path d="M5.5 3.5v4.8h4.8" fill="none" stroke="#605E5C" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="12" cy="12.5" r="2" fill="#0F6CBD"/>''',
    'check-all': '''<rect x="3.5" y="3.5" width="17" height="17" rx="3.5" fill="#0F6CBD" stroke="#0B4F8C" stroke-width="1.4"/>
  <path d="M7.5 12.3l3 3 6-6.5" fill="none" stroke="#FFFFFF" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>''',
    'clear-all': '''<rect x="3.5" y="3.5" width="17" height="17" rx="3.5" fill="#FFFFFF" stroke="#605E5C" stroke-width="1.8"/>''',
    'eye': f'''<path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12z" fill="#DCEBFA" {SW}/>
  <circle cx="12" cy="12" r="3.4" fill="#0F6CBD" {SW}/>''',
    'shield-check': '''<path d="M12 2.8l7.5 2.9v5.9c0 4.5-3.1 8.3-7.5 9.6-4.4-1.3-7.5-5.1-7.5-9.6V5.7z" fill="#13A10E" stroke="#0B5E09" stroke-width="1.5" stroke-linejoin="round"/>
  <path d="M8.5 12.1l2.4 2.4 4.6-5" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>''',
    'wrench': f'''<g transform="rotate(45 12 12)">
    <rect x="10.4" y="9" width="3.2" height="13.5" rx="1.6" fill="#8A8886" {SW}/>
    <path d="M10.2 1.34V4.8h3.6V1.34A5 5 0 1 1 10.2 1.34z" fill="#8A8886" {SW}/>
    <rect x="10.95" y="9.3" width="2.1" height="2.4" fill="#8A8886"/>
  </g>''',
    'broom': '''<g transform="rotate(40 12 12)">
    <rect x="11" y="0.8" width="2" height="10" rx="1" fill="#A86A33" stroke="#5E3612" stroke-width="0.9"/>
    <path d="M8.6 11.6h6.8l2.1 9.2q-5.5 1.6-11 0z" fill="#FFB900" stroke="#8A4B08" stroke-width="1.2" stroke-linejoin="round"/>
    <path d="M10.6 13.5l-.7 6.6M12 13.5v7M13.4 13.5l.7 6.6" stroke="#C56A00" stroke-width="0.9" stroke-linecap="round"/>
    <rect x="8.4" y="10" width="7.2" height="2.2" rx="0.7" fill="#C42B1C"/>
  </g>
  <path d="M19.5 15.5l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z" fill="#0F6CBD"/>''',
    'stop': '''<circle cx="12" cy="12" r="9" fill="#C42B1C" stroke="#86190F" stroke-width="1.4"/>
  <path d="M8.8 8.8l6.4 6.4M15.2 8.8l-6.4 6.4" stroke="#FFFFFF" stroke-width="2.3" stroke-linecap="round"/>''',
    # preset: three sliders
    'sliders': '''<path d="M4 6.5h16M4 12h16M4 17.5h16" stroke="#605E5C" stroke-width="2" stroke-linecap="round"/>
  <circle cx="9" cy="6.5" r="2.4" fill="#0F6CBD" stroke="#0B4F8C" stroke-width="1.2"/>
  <circle cx="15.5" cy="12" r="2.4" fill="#0F6CBD" stroke="#0B4F8C" stroke-width="1.2"/>
  <circle cx="7" cy="17.5" r="2.4" fill="#0F6CBD" stroke="#0B4F8C" stroke-width="1.2"/>''',
    # update packages: a box with a down arrow
    'package': '''<path d="M3.5 8.2L12 4l8.5 4.2v8.6L12 21l-8.5-4.2z" fill="#F7D79B" stroke="#8A5A12" stroke-width="1.4" stroke-linejoin="round"/>
  <path d="M3.5 8.2L12 12.4l8.5-4.2M12 12.4V21" fill="none" stroke="#8A5A12" stroke-width="1.4" stroke-linejoin="round"/>
  <path d="M12 1.2v6.3M9.4 5l2.6 2.6L14.6 5" fill="none" stroke="#0F6CBD" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>''',
}
SIZES_BTN = [16, 20, 24, 32]
SIZES_ICO = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def svg_icon(body):
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\n  %s\n</svg>\n' % body


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
    for name, body in ICONS.items():
        svg = svg_icon(body)
        with open(os.path.join(idir, 'svg', name + '.svg'), 'w', newline='\n') as f: f.write(svg)
        for s in SIZES_BTN:
            render(svg, s, os.path.join(idir, '%s_%d.png' % (name, s)))
    print('ok: %d button icons x %d sizes, app icon %s' % (len(ICONS), len(SIZES_BTN), SIZES_ICO))


if __name__ == '__main__':
    main()
