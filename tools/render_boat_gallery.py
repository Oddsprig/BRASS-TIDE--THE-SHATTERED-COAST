"""Rasterise exact BoatArt primitives captured by boat_gallery.gd; no game window."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def panel_image(panel, scale=2):
    image = Image.new('RGB', (int(panel['width'])*scale, int(panel['height'])*scale), panel['background'])
    draw = ImageDraw.Draw(image, 'RGBA')
    for primitive in panel['primitives']:
        color = tuple(round(max(0, min(1, x))*255) for x in primitive['c'])
        points = [(x*scale, y*scale) for x, y in primitive['pts']]
        kind = primitive['t']
        if kind == 'poly':
            draw.polygon(points, fill=color)
        elif kind in ('line', 'seg'):
            draw.line(points, fill=color, width=max(1, round(primitive.get('w', 1)*scale)), joint='curve')
        elif kind == 'circle':
            x, y = points[0]
            radius = primitive['r']*scale
            draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=color)
        else:
            raise ValueError(f'Unrecognised captured primitive {kind}')
    return image.resize((int(panel['width']), int(panel['height'])), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--label',default='v0.006')
    args = parser.parse_args()
    data = json.loads(args.capture.read_text(encoding='utf-8'))
    assert data['failures'] == 0, 'Do not preview a failed capture as a passing gallery'
    args.out.mkdir(parents=True, exist_ok=True)
    panels = data['panels']
    images = {panel['id']: panel_image(panel) for panel in panels}
    font_path = Path('C:/Windows/Fonts/segoeui.ttf')
    font = ImageFont.truetype(str(font_path), 17) if font_path.exists() else ImageFont.load_default()
    title_font = ImageFont.truetype(str(font_path), 29) if font_path.exists() else font
    gallery = data.get('gallery', {})
    hull_ids = gallery.get('hull_ids')
    hull_panels = ([p for p in panels if p['id'] in hull_ids] if hull_ids
                   else panels[:int(data.get('summary', {}).get('hulls', 24))])
    count = len(hull_panels)
    rows = max(1, (count+3)//4)
    sheet = Image.new('RGB', (1920, 70+rows*350), '#0b242f')
    draw = ImageDraw.Draw(sheet)
    heading = gallery.get('title', 'ORIGINAL HULLS')
    draw.text((24, 16), f'BRASS TIDE  {args.label}  |  {count} {heading}', font=title_font, fill='#dfbd7d')
    for i, panel in enumerate(hull_panels):
        x, y = (i % 4)*480, 70+(i//4)*350
        sheet.paste(images[panel['id']].resize((480, 315), Image.Resampling.LANCZOS), (x, y))
        draw.text((x+14, y+321), panel['title'], font=font, fill='#dfdccc')
    sheet.save(args.out/f'Brass Tide {args.label} - Fleet gallery.png')
    detail_panels = [p for p in panels if p['id'] in ('lod0','fitted_all_families','damaged','projectiles')]
    detail = Image.new('RGB', (1280, 910), '#0b242f')
    dd = ImageDraw.Draw(detail)
    dd.text((24, 14), 'BOAT DETAIL / FITTINGS / DAMAGE / PROJECTILES', font=title_font, fill='#dfbd7d')
    for i, panel in enumerate(detail_panels):
        x, y = (i % 2)*640, 60+(i//2)*425
        detail.paste(images[panel['id']], (x, y))
        dd.text((x+12, y+390), panel['title'], font=font, fill='#dfdccc')
    if detail_panels:
        detail.save(args.out/f'Brass Tide {args.label} - Boat detail.png')
    wakes = [images[p['id']] for p in panels if p['id'].startswith('wake_frame')]
    if wakes:
        wakes[0].save(args.out/f'Brass Tide {args.label} - Wake study.gif', save_all=True, append_images=wakes[1:], duration=550, loop=0)
    print(f'Rendered {len(images)} captured panels; {count} hulls: {args.out}')


if __name__ == '__main__':
    main()
