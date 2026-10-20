"""Draw a territory proposal from current geography; never edits the playable world."""
import argparse
import copy
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def center(points):
    return sum(p[0] for p in points)/len(points), sum(p[1] for p in points)/len(points)


def edge_distance(point, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(0, min(1, ((point[0]-a[0])*dx+(point[1]-a[1])*dy)/max(1e-8, dx*dx+dy*dy)))
    return math.hypot(point[0]-a[0]-t*dx, point[1]-a[1]-t*dy)


def inside(point, points):
    result=False
    previous=points[-1]
    for current in points:
        if (current[1]>point[1])!=(previous[1]>point[1]):
            cross=current[0]+(previous[0]-current[0])*(point[1]-current[1])/(previous[1]-current[1])
            if point[0]<cross: result=not result
        previous=current
    return result


def proposal(world):
    draft = copy.deepcopy(world)
    draft['WORLD'] = {'width':10400,'height':7200}
    associations=[]
    for port in world['PORTS']:
        point=port['x'],port['y']
        associations.append(min(range(len(world['ISLANDS'])), key=lambda i:min(edge_distance(point,a,b) for a,b in zip(world['ISLANDS'][i]['points'],world['ISLANDS'][i]['points'][1:]+world['ISLANDS'][i]['points'][:1]))))
    scales={i:1.25 for i in range(len(world['ISLANDS']))}
    for i in scales:
        attached=[p for n,p in enumerate(world['PORTS']) if associations[n]==i]
        for n,p in enumerate(attached):
            for q in attached[n+1:]:
                scales[i]=max(scales[i],800/math.hypot(p['x']-q['x'],p['y']-q['y']))
    for index, island in enumerate(world['ISLANDS']):
        cx, cy = center(island['points'])
        draft['ISLANDS'][index]['conceptLocalScale']=scales[index]
        draft['ISLANDS'][index]['points'] = [[round(cx*4+(x-cx)*scales[index],2), round(cy*4+(y-cy)*scales[index],2)] for x,y in island['points']]
    for index, port in enumerate(world['PORTS']):
        p = port['x'],port['y']
        island_index = associations[index]
        cx, cy = center(world['ISLANDS'][island_index]['points'])
        draft['PORTS'][index]['x'] = round(cx*4+(port['x']-cx)*scales[island_index],2)
        draft['PORTS'][index]['y'] = round(cy*4+(port['y']-cy)*scales[island_index],2)
        draft['PORTS'][index]['conceptIsland'] = world['ISLANDS'][island_index]['name']
    return draft


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args=parser.parse_args()
    source=(ROOT/'game/data/world.json').read_bytes()
    world=json.loads(source)
    if world['WORLD']!={'width':2600,'height':1800}:
        raise ValueError('This concept is based on the v0.002 geometry; supply that original source before reusing it after a territory change.')
    draft=proposal(world)
    assert all(0<=x<=10400 and 0<=y<=7200 for island in draft['ISLANDS'] for x,y in island['points'])
    assert all(not inside((p['x'],p['y']),island['points']) for p in draft['PORTS'] for island in draft['ISLANDS']), 'A proposed port is inside land'
    args.out.mkdir(parents=True,exist_ok=True)
    positions={'status':'CONCEPT ONLY - not a playable world or save migration','sourceMapVersion':world['VERSION'],'proposedWorld':draft['WORLD'],'islandCenterScale':4,'localIslandRule':'1.25 except expanded dual-port coasts targeting at least800 units between ports','ports':[{'id':p['id'],'name':p['name'],'x':p['x'],'y':p['y'],'island':p['conceptIsland']} for p in draft['PORTS']],'islands':draft['ISLANDS'],'routes':world['ROUTES']}
    (args.out/'TERRITORY PLACEMENT DRAFT.json').write_text(json.dumps(positions,indent=2),encoding='utf-8')
    image=Image.new('RGB',(1920,1160),'#091f2b')
    draw=ImageDraw.Draw(image)
    font_path='C:/Windows/Fonts/segoeui.ttf'
    font=lambda n:ImageFont.truetype(font_path,n)
    draw.text((40,26),'BRASS TIDE  /  TERRITORY EXPANSION PLAN',font=font(36),fill='#dfbd7d')
    draw.text((40,82),'Concept for v0.005. Existing ports and original island identities retained; open sea and route choices expanded.',font=font(23),fill='#c5d6cc')
    def panel(x,data,title,subtitle):
        rect=(x,145,x+900,820)
        draw.rounded_rectangle(rect,18,fill='#163d49',outline='#3b655f',width=2)
        draw.text((x+24,165),title,font=font(27),fill='#dfbd7d')
        draw.text((x+24,207),subtitle,font=font(19),fill='#b1c9be')
        k=min(820/data['WORLD']['width'],500/data['WORLD']['height'])
        ox=x+45
        oy=275
        transform=lambda p:(ox+p[0]*k,oy+p[1]*k)
        for i in range(1,6):
            a=transform((i*data['WORLD']['width']/6,0))
            b=transform((i*data['WORLD']['width']/6,data['WORLD']['height']))
            draw.line((a,b),fill='#214a53',width=1)
        ports={p['id']:p for p in data['PORTS']}
        for a,b in data['ROUTES']:
            draw.line((transform((ports[a]['x'],ports[a]['y'])),transform((ports[b]['x'],ports[b]['y']))),fill='#3b665f',width=2)
        for island in data['ISLANDS']:
            points=[transform(p) for p in island['points']]
            draw.polygon(points,fill='#647c60',outline='#c9ba8b',width=2)
        for i,p in enumerate(data['PORTS']):
            px,py=transform((p['x'],p['y']))
            draw.ellipse((px-15,py-15,px+15,py+15),fill='#0e2935',outline='#dfbd7d',width=2)
            label=str(i+1)
            box=draw.textbbox((0,0),label,font=font(17))
            draw.text((px-(box[2]-box[0])/2,py-12),label,font=font(17),fill='#f0e6cb')
        length=500 if data['WORLD']['width']<5000 else 2000
        draw.line(((x+40,790),(x+40+length*k,790)),fill='#dfbd7d',width=3)
        draw.text((x+46+length*k,776),f'{length:,} world units',font=font(17),fill='#b1c9be')
    panel(40,world,'CURRENT  2,600 × 1,800','Small channels; nearby ports and crowded labels at wide zoom.')
    panel(980,draft,'PROPOSED  10,400 × 7,200','4× width and height = 16× area. Islands do not inflate 4×.')
    draw.text((40,846),'REGIONAL PLAY BY DEFAULT',font=font(26),fill='#dfbd7d')
    draw.text((40,891),'Show 2–4 nearby ports at readable size. Whole-territory view uses simple markers and priority labels.',font=font(23),fill='#c5d6cc')
    for i,p in enumerate(world['PORTS']):
        col=i%5
        row=i//5
        draw.text((40+col*376,947+row*43),f'{i+1:02d}  {p["name"]}',font=font(21),fill='#c5d6cc')
    draw.text((40,1057),'Dual-port coasts expanded toward at least 800 units between harbors. Route lines are schematic.',font=font(20),fill='#91b2a8')
    draw.text((40,1093),'Next checks: safe water routes, label spacing, travel time, wages/fuel, and old-save migration. No runtime data changed.',font=font(20),fill='#91b2a8')
    image.save(args.out/'TERRITORY CONCEPT.png')
    assert (ROOT/'game/data/world.json').read_bytes()==source
    assert all(0<=p['x']<=10400 and 0<=p['y']<=7200 for p in draft['PORTS'])
    distances=[min(math.hypot(p['x']-q['x'],p['y']-q['y']) for q in draft['PORTS'] if q['id']!=p['id']) for p in draft['PORTS']]
    print('Concept exported; current world bytes unchanged. Draft nearest-port range:',round(min(distances)),round(max(distances)))


if __name__=='__main__':main()
