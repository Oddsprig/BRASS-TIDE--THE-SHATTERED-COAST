"""33 original hull recipes over the existing 042 CPU model primitives.

Import declares recipes only. Root alone constructs/bakes them. No textures,
randomness, engines, subprocesses, installed guns or external art are used.
Stations are a frozen copy of the actual HullProfiles contract at a157241.
"""
import json
from math import cos, sin, pi, hypot
from pathlib import Path

REVISION = "049-roster-source-r1"
CATALOG = json.loads(Path(__file__).with_name("catalog.json").read_text(encoding="utf-8"))


class Yard:
    """Small shared dockyard parts; each design below specifies its own layout."""
    def __init__(self, hull_id, api):
        self.api = api
        self.data = CATALOG[hull_id]
        self.m = api["Model"](hull_id, self.data["size"])
        d = self.data
        self.m.sockets = api["sockets_for"](hull_id, d["size"], d["role"], d["tier"], d["faction"])
        self.clearance = []

    def point(self, x, y, z):
        return self.m.p(x, y, z)

    def block(self, name, x, y, length, width, bottom, top, mat, bevel=.35, yaw=0):
        self.api["box"](self.m, name, self.point(x, y, (top+bottom)/2),
                        (length*self.m.size, width*self.m.size, top-bottom), mat, bevel, yaw)

    def pipe(self, name, points, radius=.28, mat="steel", closed=False):
        self.api["tube"](self.m, name, [self.point(*p) for p in points], radius, mat, 8, closed)

    def drum(self, name, x, y, radius, bottom, top, mat="steel"):
        self.api["lathe"](self.m, name, self.point(x, y, 0),
            [(0,bottom),(radius*.90,bottom),(radius,bottom+.25),
             (radius,top-.25),(radius*.90,top),(0,top)], mat, 16)

    def house(self, x=-.30, length=.66, width=.46, top=17, mat="ivory", roof="teal_light"):
        self.block("wheelhouse_walls",x,0,length,width,8.5,top-1.2,mat,.65)
        self.block("separate_roof_eave",x,0,length+.045,width+.045,top-1.2,top,roof,.48)
        # A broad glazing band reads at normal zoom; no window-sized pinpricks.
        for side in (-1,1):
            self.block("side_glazing",x,side*(width/2+.003),length*.76,.018,top-4,top-1.7,"glass",.12)
            self.block("window_sill",x,side*(width/2+.014),length*.80,.023,top-4.4,top-4,"ivory",.12)
        self.block("forward_glazing",x+length/2+.003,0,.018,width*.76,top-4,top-1.7,"glass",.12)

    def cockpit(self, x=-.28, length=.66, width=.46, stepped=False):
        self.block("open_cockpit_recess",x,0,length,width,8.4,8.9,"seam",.45)
        self.block("cockpit_sole",x,0,length-.07,width-.07,8.9,9.1,"deck",.35)
        for y in (-width*.24,width*.24):
            self.block("fixed_helm_seat",x-.12,y,.17,.15,9.1,11.7,"canvas",.35)
            if stepped:self.block("raised_aft_bench",x-.26,y,.11,.16,9.1,12.8,"ivory",.3)
        self.block("helm_console",x+length*.36,0,.075,width*.90,9.0,13.3,"teal_light",.4)
        self.block("raked_windscreen",x+length*.41,0,.025,width*.95,13.3,15.8,"glass",.25)

    def motor(self, x=-1.0, y=0, length=.32, width=.36, top=12.8, mat="machinery"):
        self.api["engine"](self.m,x,y,8.6,length,width,top,mat)

    def funnel(self, x, y, height=21, radius=.95, mat="brass"):
        self.drum("exhaust_trunk",x,y,radius,12.0,height,mat)
        self.drum("exhaust_dark_mouth",x,y,radius*.76,height-.08,height+.05,"seam")
        self.pipe("exhaust_intake",[(x+.08,y,11),(x+.08,y,14),(x,y,15)],.26,"steel")

    def shaft(self, y, jet=False):
        stern = self.data["stations"][0][0]
        # Compact transom motors leave the centerline aft well completely empty.
        if jet:
            self.block("jet_pump_casing",stern-.04,y,.24,.16,6.0,10.3,"armor_light",.6)
            self.pipe("jet_nozzle",[(stern+.02,y,3.5),(stern-.13,y,3.5)],.8,"steel")
            self.drum("jet_service_cover",stern-.04,y,1.0,10.3,10.7,"ivory")
        else:
            self.api["drive"](self.m,stern,y,True)

    def foil(self, x, width=.67, swept=False):
        for side in (-1,1):
            self.pipe("foil_strut",[(x,side*.39,6.0),(x-.07,side*width,1.3)],.36,"steel")
            self.block("planing_foil",x-.06,side*(width-.10),.36,.27,.8,1.6,"tin",.20,
                       side*.25 if swept else 0)

    def hold(self, x, y=0, length=.42, width=.56, covered=False):
        # Floor and coamings stay below the common 9.7 weapon-base plane.
        self.block("open_hold_dark_interior",x,y,length,width,8.35,8.55,"seam",.35)
        for side in (-1,1):
            self.block("hold_longitudinal_coaming",x,y+side*width/2,length,.035,8.5,9.3,"ivory",.12)
            self.block("hold_end_coaming",x+side*length/2,y,.035,width,8.5,9.3,"timber",.12)
        if covered:
            self.block("removable_hold_cover",x,y,length-.04,width-.04,9.3,9.65,"canvas",.25)

    def locker(self, name, x, y, length=.24, width=.18, top=12.0, mat="ivory"):
        self.block(name,x,y,length,width,8.6,top,mat,.35)
        self.block(name+"_binding",x,y,.035,width+.012,top,top+.18,"brass",.08)

    def mast(self, x=-.40, y=0, height=24, spread=.20):
        self.pipe("signal_mast",[(x,y,16),(x,y,height)],.22,"steel")
        self.pipe("signal_yard",[(x,y-spread,height-1.1),(x,y+spread,height-1.1)],.18,"ivory")

    def reel(self, x, y, radius=1.5, height=11.6):
        for side in (-1,1):
            self.block("reel_stanchion",x,y+side*.10,.055,.055,8.7,height,"ivory",.15)
        self.pipe("reel_axle",[(x,y-.14,height),(x,y+.14,height)],.32,"steel")
        # Axle along Y, so fishing machinery is visibly distinct from mount wells.
        for offset in (-.09,0,.09):
            pts=[(x+radius/self.m.size*cos(2*pi*j/20),y+offset,
                  height+radius*sin(2*pi*j/20)) for j in range(20)]
            self.pipe("net_reel_flange" if offset else "wound_net",pts,.25 if offset else .7,
                      "ivory" if offset else "canvas",True)

    def davit(self, x, y, reach=.28, height=21):
        self.pipe("working_davit",[(x,y,8.8),(x,y,height),(x+.12,y+reach,height)],.36,"steel")
        self.pipe("davit_fall",[(x+.12,y+reach,height),(x+.12,y+reach,12)],.14,"rope")
        self.drum("davit_winch",x,y,1,9,10.7,"brass")

    def armor(self, courses=1, mat="armor_light"):
        st=self.data["stations"]
        cat=self.data["role"]=="raider"
        for side in (-1,1):
            for i in range(6):
                x=-1.10+i*.40
                y=side*(self.api["width_at"](st,x)+(.62 if cat else 0))
                for course in range(courses):
                    self.block("separate_belt_course",x,y,.34,.026,3.0+course*1.5,4.3+course*1.5,mat,.20)

    def finish(self):
        # Reject actual high structure AABBs that intrude into any interchangeable
        # well, rather than hiding occupied sockets beneath a pretty roof.
        for p in self.m.parts:
            if "socket" in p.name or "_well" in p.name or "_bolt" in p.name:continue
            high=[v for v in p.vertices if v[2]>9.7]
            if not high:continue
            lo=[min(v[i] for v in high) for i in (0,1)]
            hi=[max(v[i] for v in high) for i in (0,1)]
            for s in self.m.sockets:
                x,y=s["world_xy"]
                distance=hypot(max(lo[0]-x,0,x-hi[0]),max(lo[1]-y,0,y-hi[1]))
                gap=distance-s["radius"]
                if gap<.04*self.m.size:
                    raise ValueError(f"{self.m.hull_id}: {p.name} intrudes on {s['id']} (gap={gap})")
                self.clearance.append(gap)
        self.api["mounting_rings"](self.m,8.4)
        self.m.roster049={"recipe_revision":REVISION,"stations":self.data["stations"],
            "physical_size":self.m.size,"minimum_high_structure_clearance_world":min(self.clearance),
            "installed_guns_in_hull":False,"design":self.data["identity"]}
        return self.m


def bilge_punt(y):
    y.cockpit(length=.58,width=.40);y.motor(y=.12,width=.20,top=11.6,mat="tin")
    y.shaft(-.13)
    y.block("riveted_replacement_cheek",-.25,.48,.76,.04,4.5,8,"oxide",.12)
    y.locker("salvage_bin",1.65,0,.26,.22,11,"tin");y.reel(-1.08,-.29,1.0,11.5)


def lantern_skiff(y):
    y.house(length=.60,width=.43,top=18.2,roof="tin");y.motor(width=.38,top=13.7)
    y.shaft(-.23);y.shaft(.23)
    y.drum("customs_searchlight_pedestal",-.29,0,.7,18.2,20,"brass")
    y.block("searchlight_lens",-.20,0,.025,.16,19,21.4,"glass_edge",.28)
    y.locker("sealed_customs_chest",1.64,0,.28,.28,11.9)


def marsh_dart(y):
    y.cockpit(length=.62,width=.42,stepped=True);y.motor(length=.38,width=.30,top=12.5)
    y.shaft(0,True);y.foil(.18)
    y.block("shallow_step_skeg",.12,0,.30,.76,1.2,2.2,"tin",.28)
    y.locker("shoal_pole_lockers",1.64,0,.36,.16,10.5,"teal_light")


def scab_cutter(y):
    y.house(length=.62,width=.43,top=17.4,mat="armor_light",roof="oxide")
    y.motor(y=-.10,width=.20,top=13.6);y.funnel(-.98,.20,19,.65,"steel")
    y.shaft(-.22);y.shaft(.22)
    for side in (-1,1):
        for x in (1.45,1.65,1.85):
            y.block("sawtooth_bow_fender",x,side*.25,.12,.09,7,9.1,"ivory",.14,side*.4)
    y.locker("boarding_hook_bin",1.65,0,.30,.20,11.1,"armor_light")


def gale_cutter(y):
    y.house(length=.70,width=.40,top=16.4,mat="teal_light",roof="ivory")
    y.motor(y=-.20,width=.16,top=14.2);y.motor(y=.20,width=.16,top=14.2)
    y.shaft(-.28,True);y.shaft(.28,True);y.foil(.14,.75,True)
    y.pipe("supercharger_crossover",[(-1.12,-.18,14.5),(-1.12,0,15.3),(-1.12,.18,14.5)],.32,"brass")


def silt_lugger(y):
    y.house(length=.70,width=.52,top=16.1,mat="timber",roof="canvas")
    for side in (-1,1):
        y.motor(y=side*.24,width=.18,top=11.8,mat="teal_light");y.shaft(side*.62)
        y.hold(1.53,side*.62,.56,.32);y.locker("dry_cargo_bale",-.94,side*.64,.40,.28,13,"canvas")
    y.block("removable_foredeck_grating",.22,0,.32,.74,8.9,9.3,"timber",.22)


def hook_raider(y):
    y.house(x=-.27,length=.62,width=.42,top=16.5,mat="oxide",roof="tin")
    y.motor(width=.46,top=13.2);y.funnel(-1.03,0,19,.85,"steel")
    for side in (-1,1):
        y.shaft(side*.62,True);y.locker("contraband_locker",-1.10,side*.64,.38,.24,11.8,"timber")
    y.davit(-.38,.68,.18,22);y.hold(1.62,0,.42,.65,True)


def mercantile_clipper(y):
    y.house(length=.72,width=.52,top=19.7,mat="ivory",roof="brass_light")
    y.house(x=-.34,length=.40,width=.34,top=23.1,mat="teal_light",roof="ivory")
    for side in (-1,1):
        y.motor(y=side*.23,width=.18,top=13.4);y.shaft(side*.62)
        y.locker("bonded_bullion_safe",-1.07,side*.64,.36,.25,12.8,"tin")
        y.hold(1.64,side*.62,.46,.33,True)
    y.mast(-.40,0,27,.22)


def harbor_sloop(y):
    y.house(length=.66,width=.46,top=18.5,mat="ivory",roof="teal_light")
    y.motor(width=.38,top=12.9);y.funnel(-1.01,0,20,.85)
    y.shaft(0);y.mast(-.41,0,24,.15)
    y.drum("tow_capstan",1.61,0,1.15,8.8,11.8,"brass")


def aegis_corvette(y):
    y.house(length=.70,width=.50,top=20,mat="tin",roof="ivory")
    y.block("optical_rangefinder_wing",-.31,0,.16,.91,20,21.6,"teal_light",.42)
    y.motor(width=.42,top=13.5);y.funnel(-1.01,0,22,1.05,"steel")
    y.shaft(-.25);y.shaft(.25);y.mast(-.44,0,28,.22)
    for side in (-1,1):y.locker("damage_control_chest",1.63,side*.18,.32,.20,11.8)


def reed_stinger(y):
    y.cockpit(length=.60,width=.40);y.motor(width=.34,top=12.2,mat="teal_light")
    y.shaft(0,True);y.foil(.16,.65)
    # Compressed-air auxiliaries, deliberately no fixed torpedo or launcher tube.
    for side in (-1,1):y.drum("air_receiver",1.57,side*.13,.65,8.7,11.3,"steel")
    y.pipe("air_cross_manifold",[(1.55,-.13,10.8),(1.55,.13,10.8)],.21,"brass")


def krill_torpedo(y):
    y.house(length=.58,width=.40,top=17,mat="tin",roof="oxide")
    y.motor(y=.14,width=.20,top=13.4);y.funnel(-1.02,-.20,19,.7,"steel")
    y.shaft(-.22);y.shaft(.22)
    y.block("empty_reload_skid",1.65,0,.44,.28,8.7,9.4,"armor_light",.18)
    for side in (-1,1):y.pipe("reload_skid_rail",[(1.44,side*.13,9.6),(1.86,side*.13,9.6)],.18,"ivory")


def manta_strike(y):
    y.house(x=-.32,length=.72,width=.40,top=17.6,mat="teal_light",roof="ivory")
    y.motor(y=-.22,width=.16,top=13.2);y.motor(y=.22,width=.16,top=13.2)
    y.shaft(-.30,True);y.shaft(.30,True);y.foil(.14,.81,True)
    y.block("command_fin",-.47,0,.34,.055,17.6,25,"teal_light",.5)
    y.drum("hydraulic_reservoir",1.66,0,1.4,8.6,11.2,"tin")


def slag_gunboat(y):
    y.house(length=.68,width=.54,top=18.8,mat="armor_light",roof="tin")
    y.armor(1);y.motor(width=.46,top=13.5)
    y.funnel(-1.02,-.17,21,.78,"steel");y.funnel(-1.02,.17,21,.78,"steel")
    y.shaft(-.25);y.shaft(.25)
    y.block("river_ram_cheek",1.62,0,.42,.48,5.4,9.4,"armor_light",.65)


def bellows_gunboat(y):
    y.house(length=.70,width=.54,top=21.2,mat="tin",roof="ivory");y.armor(2)
    y.motor(y=-.14,width=.20,top=14.2);y.motor(y=.14,width=.20,top=14.2)
    y.funnel(-1.01,-.20,23,1.0,"steel");y.funnel(-1.01,.20,23,1.0,"steel")
    y.shaft(-.28);y.shaft(.28)
    for side in (-1,1):
        y.pipe("bellows_bilge_manifold",[(-.55,side*.61,9),(-.55,side*.61,12.8),(-.03,side*.61,12.8)],.42,"brass")


def furnace_turret(y):
    y.house(length=.68,width=.56,top=19.4,mat="armor_light",roof="ivory");y.armor(3)
    y.drum("conning_cupola",-.34,0,3.1,19.4,25.5,"tin")
    y.motor(width=.48,top=14.2);y.funnel(-1.02,-.20,25,1.2,"steel");y.funnel(-1.02,.20,25,1.2,"steel")
    y.shaft(-.30);y.shaft(.30)
    for i in range(3):y.drum("steam_bilge_ejector",1.66,(i-1)*.12,.90,8.7,13,"brass")


def barbed_lance(y):
    y.house(length=.62,width=.48,top=16.9,mat="timber",roof="tin")
    y.motor(width=.42,top=12.5);y.shaft(-.27);y.shaft(.27)
    y.hold(1.60,0,.46,.64,True)
    for side in (-1,1):
        y.block("scow_push_cheek",-.18,side*.72,.70,.12,3.1,8.3,"timber",.32)
        y.locker("sealed_igniter_box",-1.04,side*.59,.33,.20,11.4,"ivory")


def cinder_monitor(y):
    y.house(length=.66,width=.52,top=18,mat="armor_light",roof="ivory");y.armor(2)
    y.motor(width=.46,top=13.4);y.funnel(-1.01,0,24,1.35,"steel")
    y.shaft(-.28);y.shaft(.28)
    for side in (-1,1):
        y.locker("insulated_ammunition_safe",-1.04,side*.66,.35,.24,12.2,"tin")
    y.block("empty_blast_apron",1.66,0,.42,.52,8.8,9.5,"ivory",.25)


def wraith_rocket(y):
    y.house(length=.66,width=.48,top=19.2,mat="tin",roof="ivory")
    y.house(x=-.34,length=.36,width=.30,top=25,mat="teal_light",roof="ivory")
    y.motor(y=-.24,width=.17,top=13.8);y.motor(y=.24,width=.17,top=13.8)
    y.shaft(-.28,True);y.shaft(.28,True);y.mast(-.43,0,30,.28)
    for side in (-1,1):y.locker("salvo_service_caisson",1.69,side*.22,.45,.22,12.4,"tin")


def cobalt_frigate(y):
    y.house(length=.70,width=.52,top=20,mat="ivory",roof="teal_light")
    y.house(x=-.34,length=.42,width=.34,top=25.5,mat="tin",roof="ivory")
    y.motor(y=-.20,width=.17,top=14);y.motor(y=.20,width=.17,top=14)
    y.funnel(-1.01,-.20,24,.90,"brass");y.funnel(-1.01,.20,24,.90,"brass")
    y.shaft(-.26);y.shaft(.26);y.mast(-.43,0,31,.24)


def iron_bastion(y):
    y.house(length=.72,width=.54,top=22,mat="tin",roof="ivory");y.armor(2)
    y.house(x=-.34,length=.44,width=.36,top=29,mat="teal_light",roof="brass_light")
    y.motor(width=.46,top=15);y.funnel(-1.02,-.22,29,1.40,"steel");y.funnel(-1.02,.22,29,1.40,"steel")
    y.shaft(-.29);y.shaft(.29);y.mast(-.44,0,35,.28)
    y.drum("damage_control_pump_dome",1.71,0,2.1,8.6,12.6,"tin")


def maiden_dreadnought(y):
    y.house(length=.72,width=.56,top=24,mat="armor_light",roof="ivory");y.armor(3)
    y.house(x=-.36,length=.40,width=.34,top=31,mat="tin",roof="ivory")
    y.motor(width=.48,top=15.3)
    for yy in (-.23,0,.23):y.funnel(-1.04,yy,30,1.10,"steel")
    y.shaft(-.31);y.shaft(0);y.shaft(.31);y.mast(-.46,0,38,.30)
    for side in (-1,1):y.locker("capital_pump_room_access",1.73,side*.24,.45,.23,13.6,"tin")


def kelpnet_dory(y):
    y.cockpit(x=-.22,length=.47,width=.37);y.motor(x=-1.04,y=.16,width=.17,top=11.4,mat="tin")
    y.shaft(0);y.hold(.24,0,.34,.50);y.reel(-1.01,-.25,1.35,11.5)
    y.locker("net_stack",1.64,0,.32,.32,11,"canvas")
    y.pipe("dory_thwart",[(-.66,-.40,9.4),(-.66,.40,9.4)],.35,"timber")


def brinehook_longliner(y):
    y.house(length=.58,width=.40,top=16.4,mat="ivory",roof="canvas")
    y.motor(width=.30,top=12);y.shaft(0)
    y.reel(-1.94,-.20,1.1,11.5);y.reel(-1.94,.20,1.1,11.5)
    y.davit(-.42,.43,.15,21);y.hold(1.66,0,.44,.41)


def mother_gull_trawler(y):
    y.house(length=.66,width=.52,top=17.4,mat="timber",roof="ivory")
    for side in (-1,1):
        y.motor(y=side*.23,width=.18,top=12.5);y.shaft(side*.62)
        y.reel(-1.83,side*.61,1.65,12.0)
        y.locker("covered_net_stack",1.67,side*.62,.44,.30,12.4,"canvas")
    y.pipe("trawl_gantry",[(-.45,-.78,8.7),(-.45,-.78,22),(-.45,.78,22),(-.45,.78,8.7)],.40,"ivory")
    y.hold(.17,0,.30,.75)


def fenhopper_lighter(y):
    y.house(length=.72,width=.54,top=15.4,mat="timber",roof="canvas")
    for side in (-1,1):
        y.motor(y=side*.23,width=.17,top=12);y.shaft(side*.62)
        for x in (-1.91,1.61):y.locker("lashed_compressed_bales",x,side*.62,.34,.37,13,"canvas")
    y.hold(.18,0,.32,.90,True)
    y.block("lighter_loading_ramp",1.94,0,.26,.58,6.0,8.7,"timber",.3)


def tideledger_coaster(y):
    y.house(length=.70,width=.52,top=18.1,mat="ivory",roof="teal_light")
    for side in (-1,1):
        y.motor(y=side*.24,width=.18,top=13);y.shaft(side*.62)
        y.locker("bonded_hold_strongbox",-1.99,side*.62,.38,.32,12.9,"tin")
        y.hold(1.69,side*.62,.58,.39,True)
    y.davit(-.39,.61,.15,25)


def fourport_packet(y):
    y.house(length=.72,width=.54,top=18.7,mat="ivory",roof="teal_light")
    y.house(x=-.36,length=.46,width=.37,top=24,mat="ivory",roof="brass_light")
    for side in (-1,1):
        y.motor(y=side*.23,width=.18,top=13);y.funnel(-1.02,side*.23,21,.8,"brass")
        y.shaft(side*.62);y.hold(1.72,side*.62,.70,.42,True)
        y.locker("covered_manifest_cabinet",-1.96,side*.62,.32,.26,12.2,"timber")
    y.mast(-.45,0,29,.23)


def seepoil_tanker(y):
    y.house(length=.64,width=.46,top=15.9,mat="tin",roof="ivory")
    y.motor(width=.42,top=12.6);y.shaft(-.28);y.shaft(.28)
    # Actual broad tank volumes, low enough to leave all optional mount wells open.
    for x in (-1.94,1.67):
        for side in (-1,1):y.drum("secured_liquid_cask",x,side*.25,1.65,8.6,12.8,"tin")
    for side in (-1,1):
        y.pipe("copper_transfer_manifold",[(-.60,side*.64,8.9),(-.60,side*.64,11.2),(-.02,side*.64,11.2)],.40,"brass")
        y.drum("transfer_valve",-.13,side*.64,.75,11.2,12.2,"ivory")


def blackwater_fleet_tanker(y):
    y.house(length=.70,width=.48,top=17.8,mat="ivory",roof="tin")
    y.motor(width=.44,top=13.6);y.funnel(-1.01,0,22,1.0,"steel")
    for side in (-1,1):
        y.shaft(side*.36)
        for x in (-2.04,1.78):
            y.block("longitudinal_cargo_tank",x,side*.29,.58,.39,8.6,13.7,"tin",1.6)
            y.drum("tank_inspection_dome",x,side*.29,.9,13.7,14.4,"ivory")
        y.pipe("tank_transfer_main",[(-.65,side*.72,10.8),(-.65,side*.72,12.5),(-.04,side*.72,12.5)],.43,"brass")
    y.shaft(0);y.hold(.18,0,.31,.38,True)


def gullwing_daysailer(y):
    y.cockpit(length=.66,width=.46,stepped=True);y.motor(width=.30,top=11.8,mat="ivory")
    y.shaft(0,True);y.foil(.12,.68,True)
    y.block("fore_sunpad",1.66,0,.34,.32,8.8,10.2,"canvas",.45)
    y.pipe("windscreen_hoop",[(-.02,-.25,12.6),(-.02,0,16),(-.02,.25,12.6)],.23,"ivory")


def osprey_cabin_cruiser(y):
    y.house(length=.74,width=.46,top=17.8,mat="ivory",roof="teal_light")
    y.block("raised_day_salon",-.43,0,.35,.33,17.8,20.4,"timber",.75)
    y.block("salon_skylight",-.43,0,.27,.25,20.4,20.8,"glass",.30)
    y.motor(width=.34,top=12.4,mat="ivory");y.shaft(-.21);y.shaft(.21)
    y.block("lacquered_foredeck_locker",1.69,0,.42,.34,8.8,11.2,"timber",.8)


def aurelian_court_yacht(y):
    y.house(length=.74,width=.54,top=19.4,mat="ivory",roof="timber")
    y.house(x=-.36,length=.46,width=.36,top=25.5,mat="ivory",roof="brass_light")
    y.block("household_signal_wing",-.34,0,.18,.91,20.6,21.7,"ivory",.5)
    y.motor(y=-.20,width=.16,top=13.1,mat="ivory");y.motor(y=.20,width=.16,top=13.1,mat="ivory")
    y.shaft(-.28);y.shaft(.28);y.mast(-.46,0,31,.23)
    y.block("foredeck_cushioned_settee",1.72,0,.40,.42,8.8,11,"canvas",.55)
    y.hold(-2.05,0,.36,.42,True)


DESIGNS = {fn.__name__:fn for fn in (
    bilge_punt,lantern_skiff,marsh_dart,scab_cutter,gale_cutter,silt_lugger,
    hook_raider,mercantile_clipper,harbor_sloop,aegis_corvette,reed_stinger,
    krill_torpedo,manta_strike,slag_gunboat,bellows_gunboat,furnace_turret,
    barbed_lance,cinder_monitor,wraith_rocket,cobalt_frigate,iron_bastion,
    maiden_dreadnought,kelpnet_dory,brinehook_longliner,mother_gull_trawler,
    fenhopper_lighter,tideledger_coaster,fourport_packet,seepoil_tanker,
    blackwater_fleet_tanker,gullwing_daysailer,osprey_cabin_cruiser,aurelian_court_yacht)}


def build(hull_id, api):
    y=Yard(hull_id,api)
    d=y.data
    st=[(x,max(.002,w)) for x,w in d["stations"]]
    if d["role"]=="raider":
        for side in (-1,1):api["hull_shell"](y.m,"separate_working_demi_hull",st,side*.62,8.2,d["hull_material"],d["trim_material"],samples=40)
        # Centerline sockets sit on a real connected deck, never in the cat gap.
        y.block("structural_bridge_deck",-.15,0,3.34,1.30,6.9,8.4,"timber",.5)
    else:
        api["hull_shell"](y.m,"authored_rounded_hull",st,0,8.2,d["hull_material"],d["trim_material"],samples=40)
    # Deck material is specified independently of paint; originals remain intact.
    for p in y.m.parts:
        if p.name.endswith("_deck"):p.material=d["deck_material"]
    DESIGNS[hull_id](y)
    return y.finish()
