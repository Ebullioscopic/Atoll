#!/usr/bin/env python3
"""Regenerate branding and notices only. Never edits Swift code, workflows or credentials."""
from pathlib import Path
import re
import shutil
import sys

root = Path(__file__).resolve().parents[1]
resources = root / 'ToolIsle/App/Resources'
resources.mkdir(parents=True, exist_ok=True)
for name in ['LICENSE', 'NOTICE', 'COPYRIGHT_ASSETS', 'TRADEMARKS']:
    shutil.copy2(root / name, resources / name)
(resources / 'THIRD_PARTY_LICENSES').write_text(
    'ToolIsle uses MarkdownUI 2.4.1 (MIT).\n'
    'The build script adds the full license notices of resolved dependencies to the application.\n'
    'Original Atoll notices remain in NOTICE and COPYRIGHT_ASSETS.\n', encoding='utf-8')

if '--skip-icons' not in sys.argv:
    import cairosvg
    from PIL import Image, ImageDraw, ImageFont
    svg = (root / 'ToolIsle/Brand/toolisle-logo.svg').read_text()
    padded = svg.replace('viewBox="0 0 64 64"', 'viewBox="-7 -7 78 78"')
    mono = re.sub(r'#[0-9a-fA-F]{6}', '#000000', padded)
    for name, vector, size in [('AppIcon', padded, 1024), ('MenuBarTemplate', mono, 36)]:
        cairosvg.svg2png(bytestring=vector.encode(), write_to=str(resources / (name + '.png')), output_width=size, output_height=size)
    dev = Image.open(resources / 'AppIcon.png').convert('RGBA')
    draw = ImageDraw.Draw(dev)
    draw.rounded_rectangle((690, 770, 990, 920), radius=28, fill='white', outline='#5148d6', width=6)
    draw.text((738, 793), 'DEV', font=ImageFont.load_default(size=90), fill='#5148d6')
    dev.save(resources / 'AppIconDev.png')
    for name in ['AppIcon', 'AppIconDev']:
        folder = resources / (name + '.iconset'); folder.mkdir(exist_ok=True)
        image = Image.open(resources / (name + '.png'))
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                suffix = '@2x' if scale == 2 else ''
                image.resize((size * scale, size * scale), Image.Resampling.LANCZOS).save(folder / f'icon_{size}x{size}{suffix}.png')
    (root / '.github/assets/toolisle-logo.svg').write_text(svg)
print('ToolIsle branding and legal resources regenerated; application code is unchanged.')
