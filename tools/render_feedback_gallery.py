"""Render recorded Godot feedback primitives into PNG and animation, with no game window."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_boat_gallery import panel_image


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('capture', type=Path)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--label', default='v0.007')
    args = ap.parse_args()
    data = json.loads(args.capture.read_text(encoding='utf-8'))
    assert data['failures'] == 0, 'Capture contains invalid geometry'
    args.out.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 18)
    title = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 26)
    frames = []
    for frame in data['frames']:
        image = Image.new('RGB', (1040, 960), '#0b242f')
        draw = ImageDraw.Draw(image)
        draw.text((20, 12), f'BRASS TIDE {args.label} | ENGINES / IMPACTS / SINKING', font=title, fill='#dfbd7d')
        for i, panel in enumerate(frame['panels']):
            x, y = (i % 2)*520, 60+(i//2)*445
            image.paste(panel_image(panel), (x, y))
            draw.text((x+18, y+400), panel['title'], font=font, fill='#d5dfce')
        draw.text((20, 932), 'Captured game drawing calls - controlled fixtures, no crew or fluid simulation', font=font, fill='#9db5a8')
        frames.append(image)
    frames[0].save(args.out/f'Brass Tide {args.label} - Combat animation.gif', save_all=True, append_images=frames[1:], duration=83, loop=0, optimize=False)
    frames[15].save(args.out/f'Brass Tide {args.label} - Engines and damage.png')
    frames[2].save(args.out/f'Brass Tide {args.label} - Impact and explosion.png')
    print(f'Rendered {len(frames)} exact feedback frames: {args.out}')


if __name__ == '__main__':
    main()
