"""Carousels on Icelandic folklore, history and curiosities. Every image is specific to its slide (Wikimedia Commons, free licences)."""
import sys, os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "plib.py")).read())
_fullbg0 = fullbg
def fullbg(im, src, BG):
    from PIL import ImageEnhance as _E
    _fullbg0(im, _E.Brightness(src).enhance(0.55), BG)
_d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
BOTTOM = H - 170
def block_h(title, tsize, body=None, bsize=42, kicker=False):
    h = len(wrap(_d, title, COND(tsize), W - 128)) * round(tsize * 1.02) + (48 if kicker else 0)
    if body: h += 18 + len(wrap(_d, body, SANS(bsize), W - 128)) * round(bsize * 1.38)
    return h
def header(im, key, h, fy=0.5, fx=0.5, where=""):
    src, cr = K(key, where)
    header_photo(im, None, h=h, fy=fy, fx=fx, src=src, credit=False)
    d = ImageDraw.Draw(im); f = MONO(17); d.text((W - 40 - d.textlength(cr, font=f), h - 205), cr, font=f, fill=(215, 215, 210))
def source(im, text):
    d = ImageDraw.Draw(im); f = MONO(20); d.text((64, H - 128), "Source: " + text, font=f, fill=(150, 150, 146))
def cover_s(key, kicker, title, sub, fy=0.5, fx=0.5, size=112):
    def make(im):
        y0 = BOTTOM - block_h(title, size, sub, 42, True) - 76
        header(im, key, max(900, y0 + 90), fy, fx)
        y = heading(im, kicker, title, y0, size)
        y = para(im, sub, y + 18, 42, TEXT); swipe(im, y + 24)
    return make
def story(key, kicker, title, body, src=None, fy=0.5, fx=0.5, big=None, col=ACCENT, ic=None):
    def make(im):
        y0 = min(1000, BOTTOM - block_h(title, 96, body, 40, bool(kicker)) - (40 if src else 0))
        header(im, key, y0 - 10, fy, fx)
        d = ImageDraw.Draw(im)
        if big: d.text((64, y0 - 300), big, font=COND(200), fill=col)
        if ic: icon(im, ic, W - 64 - 140, y0 - 290, 140)
        y = heading(im, kicker, title, y0, 96)
        para(im, body, y + 18, 40, TEXT)
        if src: source(im, src)
    return make

# ——— 19 · The 13 Yule Lads ———
LADS = [("12", "Stekkjarstaur", "Sheep-Cote Clod"), ("13", "Giljagaur", "Gully Gawk"), ("14", "Stúfur", "Stubby"), ("15", "Þvörusleikir", "Spoon Licker"),
        ("16", "Pottaskefill", "Pot Scraper"), ("17", "Askasleikir", "Bowl Licker"), ("18", "Hurðaskellir", "Door Slammer"), ("19", "Skyrgámur", "Skyr Gobbler"),
        ("20", "Bjúgnakrækir", "Sausage Swiper"), ("21", "Gluggagægir", "Window Peeper"), ("22", "Gáttaþefur", "Doorway Sniffer"), ("23", "Ketkrókur", "Meat Hook"),
        ("24", "Kertasníkir", "Candle Beggar")]
def lads_list(im):
    y = heading(im, "One a night, from 12 December", "The 13 Yule Lads", 150, 92)
    d = ImageDraw.Draw(im, "RGBA"); y += 26
    for day, ice, eng in LADS:
        d.rectangle((64, y, W - 64, y + 1), fill=(255, 255, 255, 40))
        d.text((64, y + 12), f"{day} DEC", font=MONO(26), fill=ACCENT)
        d.text((230, y + 6), ice, font=SANSB(34), fill=TEXT)
        f = SANS(28); d.text((W - 64 - d.textlength(eng, font=f), y + 12), eng, font=f, fill=DIM)
        y += 64
    d.rectangle((64, y, W - 64, y + 1), fill=(255, 255, 255, 40))
    d.text((64, y + 20), "Each leaves 13 days later, the last on 6 January.", font=SANS(30), fill=DIM)
    source(im, "Jóhannes úr Kötlum, 'Jólasveinarnir' (1932)")
carousel("carousel-19-yule-lads", [
    cover_s("lore:dimmu3", "Icelandic Christmas", "Iceland doesn't have one Santa. It has 13.", "Meet the Yule Lads, the Jólasveinar.", fy=0.4),
    story("lore:dimmu2", "Where they live", "Sons of a troll", "Their mother is Grýla, a child-eating ogress; their father, Leppalúði. In folklore the family lives in a cave in Dimmuborgir, the lava labyrinth near Lake Mývatn.", fy=0.45),
    (lads_list, "lore:dimmu1"),
    story("lore:laufa2", "22 December", "Gáttaþefur, the Doorway Sniffer", "His huge nose sniffs out laufabrauð: thin 'leaf bread', cut into patterns by hand and fried, a Christmas tradition in Icelandic homes.", fy=0.5),
    story("lore:yulecat", "The family pet", "The Yule Cat", "Grýla's giant cat eats anyone who didn't get new clothes before Christmas. Since 2018 a 5-metre Yule Cat, lit by 6,500 LEDs, stands in central Reykjavík.", src="Reykjavík City; mbl.is", fy=0.35),
    (lambda im: (icon(im, "shoe", 64, 330, 200),
                 para(im, "From 12 December, children leave a shoe on the windowsill. Good children find a small gift in the morning. Naughty ones find a rotten potato.",
                      heading(im, "Every night until Christmas", "Shoes in the window", 570, 110) + 24, 44, TEXT)), "lore:dimmu4"),
])

# ——— 20 · Before the Moon, Iceland ———
carousel("carousel-20-apollo-in-iceland", [
    cover_s("lore:apollo3", "Moon training · 1965 & 1967", "Before the Moon, they came to Iceland", "NASA sent Apollo astronauts here to learn volcanic geology.", fy=0.35),
    story("lore:apollo1", "July 1967", "Neil Armstrong was here", "Neil Armstrong and Ken Mattingly on a geology field trip in Iceland, two years before Apollo 11.", fy=0.3, src="NASA photo S67-38609"),
    story("lore:vit1", "Askja, central highlands", "'The most moon-like'", "\"If you want to go to a place on earth that looks like the Moon, central Iceland should be high on your list.\" Elbert King, NASA geologist.", fy=0.6, src="The Exploration Museum, Húsavík"),
    (lambda im: (icon(im, "users", 64, 180, 180),
                 heading(im, None, "32", 420, 260, AURORA),
                 para(im, "Apollo astronauts trained in Iceland in 1965 and 1967. Seven of them later walked on the Moon.", heading(im, None, "astronauts", 680, 100) + 20, 44, TEXT),
                 source(im, "The Exploration Museum, Húsavík")), "lore:apollo2"),
    story("lore:apollo6", "Getting around", "Highland roads, 1967", "No bridges then either: the astronauts' bus fords a river in the highlands.", fy=0.5),
    story("lore:apollomon", "Húsavík, 2015", "Their names, in basalt", "A monument outside the Exploration Museum lists all 32. Neil Armstrong's grandchildren unveiled it on 15 July 2015.", fy=0.4, src="Wikipedia, Astronaut Monument"),
])

# ——— 21 · Laki 1783 ———
carousel("carousel-21-laki-1783", [
    cover_s("lore:laki3", "Iceland, 1783", "The eruption that darkened Europe", "Laki, and the 'Haze Famine'.", fy=0.5),
    story("lore:laki5", "8 June 1783 – 7 February 1784", "A 25 km crack in the Earth", "Lava poured from more than 130 vents along a single fissure for eight months, most of it in the first five.", fy=0.4, src="Wikipedia, Laki"),
    story("lore:laki1", "Móðuharðindin", "The Haze Famine", "Fluorine poisoned the grass. About 80% of the sheep and half of the cattle and horses died, and about one Icelander in five died in the famine that followed.", fy=0.5, src="Wikipedia, Laki"),
    story("lore:laki2", "Summer 1783", "A haze over Europe", "Millions of tonnes of sulphur dioxide spread a thick haze across western Europe, followed by a very hard winter.", fy=0.5, src="Wikipedia, Laki; Katla Geopark"),
    story("lore:laki4", "Today", "Lakagígar", "The crater row is now moss-covered and protected in Vatnajökull National Park. Highland road F206, 4×4 only, summer only.", fy=0.5),
])

# ——— 22 · Trolls turned to stone ———
carousel("carousel-22-trolls-turned-to-stone", [
    cover_s("lore:reyn2", "Icelandic folklore", "These rocks were trolls", "Trolls turn to stone in daylight. Iceland's coast is full of the ones who forgot.", fy=0.4),
    story("lore:reyn3", "Reynisdrangar, Vík", "Caught dragging a ship", "Two trolls tried to haul a three-masted ship to shore at night. Dawn broke before they finished, and they became these sea stacks.", fy=0.45, src="Icelandic folklore; Wikipedia, Reynisdrangar"),
    story("lore:hvit1", "Hvítserkur, Vatnsnes", "The troll who hated church bells", "He set out to destroy the bells of the church at Þingeyrar, but the sun rose before he got there. He's still standing in the sea.", fy=0.55, src="Icelandic folklore; Visit North Iceland"),
    story("lore:hvit3", "The science", "15 metres of basalt", "Hvítserkur is a basalt stack shaped by the waves. Its base has been reinforced with concrete so the sea doesn't topple it.", fy=0.5, src="Visit North Iceland"),
    story("lore:reyn1", "Visiting Reynisdrangar?", "Never turn your back to the sea", "The black-sand beach below, Reynisfjara, has sneaker waves that reach far up the shore without warning.", fy=0.55),
])

# ——— 23 · Hidden people ———
carousel("carousel-23-hidden-people", [
    cover_s("lore:helli2", "Huldufólk", "Do Icelanders believe in elves?", "Not exactly. But many won't rule them out.", fy=0.6),
    (lambda im: (heading(im, None, "62%", 330, 260, AURORA),
                 para(im, "said it is at least possible that elves exist, in a 2007 University of Iceland survey of 1,000 people.", heading(im, None, "of Icelanders", 590, 100) + 20, 44, TEXT),
                 source(im, "University of Iceland survey (2007), via Terry Gunnell")), "lore:helli1"),
    story("lore:galga2", "Not little winged elves", "Hidden people", "In Icelandic folklore the huldufólk look like humans. They live inside rocks and hills, with farms and churches of their own.", fy=0.5),
    story("lore:galga1", "Gálgahraun, 2015", "The road that moved an elf church", "After years of protests over a new road through this lava field, the Road Administration moved a 70-tonne rock said to be an elf church, instead of blasting it.", fy=0.55, src="mbl.is; Reykjavík Grapevine"),
])

# ——— 24 · Hollywood in Iceland ———
carousel("carousel-24-hollywood-iceland", [
    cover_s("lore:svin1", "Iceland on screen", "You've seen these places in films", "Glaciers, waterfalls and lava fields that played other worlds.", fy=0.45),
    story("lore:svin2", "Interstellar (2014)", "Svínafellsjökull", "This glacier tongue played an icy alien planet. It is an outlet of Vatnajökull, near Skaftafell.", fy=0.5, src="Wikipedia, List of films shot in Iceland"),
    story("lore:jok1", "James Bond, twice", "Jökulsárlón", "The glacier lagoon appears in A View to a Kill (1985) and Die Another Day (2002), and in Lara Croft: Tomb Raider (2001).", fy=0.5, src="Wikipedia, List of films shot in Iceland"),
    story("lore:skog1", "Thor: The Dark World (2013)", "Skógafoss", "The 60-metre waterfall on the south coast, right next to Route 1.", fy=0.3, src="Wikipedia, List of films shot in Iceland"),
    story("lore:dett1", "Prometheus (2012)", "Dettifoss", "One of Europe's most powerful waterfalls, in the north-east, appears in the opening of Ridley Scott's film.", fy=0.5, src="Wikipedia, List of films shot in Iceland"),
    story("lore:leir1", "Rogue One (2016)", "Krafla", "The lava fields of the Krafla area near Lake Mývatn became a Star Wars planet.", fy=0.5, src="Wikipedia, List of films shot in Iceland"),
])

# ——— 25 · The beer ban ———
carousel("carousel-25-beer-ban", [
    cover_s("lore:beer2", "1915 – 1989", "Iceland banned beer for 74 years", "Wine and spirits came back long before.", fy=0.5),
    story("lore:vinbud", "How it happened", "Beer: the last one left", "All alcohol was banned from 1915. Spanish wine returned in the 1920s, spirits in 1935. Beer stronger than 2.25% stayed illegal.", fy=0.5, src="Wikipedia, Prohibition in Iceland"),
    story("lore:beer1", "1 March 1989", "Beer Day", "Strong beer became legal again on 1 March 1989. Icelanders still celebrate the date as Bjórdagurinn, Beer Day.", fy=0.4, src="Wikipedia, Beer Day (Iceland)"),
])

# ——— 26 · Þingvellir ———
carousel("carousel-26-thingvellir", [
    cover_s("lore:thing1", "Þingvellir, 930 AD", "Where Iceland's parliament was born", "The Alþingi met here, outdoors, for almost 900 years.", fy=0.5),
    story("lore:log1", "Lögberg, the Law Rock", "The law, from memory", "From this rock the elected Lawspeaker recited the law of the land to the assembly. The Alþingi met at Þingvellir from 930 until 1798.", fy=0.5, src="Wikipedia, Þingvellir"),
    story("lore:thing2", "Almannagjá", "Between two continents", "Þingvellir lies in a rift valley where the North American and Eurasian plates are pulling apart. A UNESCO World Heritage Site since 2004.", fy=0.6, src="Wikipedia, Þingvellir; UNESCO"),
])

# ——— Single · Surtsey ———
def b_surtsey(im):
    src, cr = K("lore:surt63", "post-07")
    header_photo(im, None, h=700, fy=0.5, src=src, credit=False)
    d = ImageDraw.Draw(im); f = MONO(17); d.text((W - 40 - d.textlength(cr, font=f), 495), cr, font=f, fill=(215, 215, 210))
    y = heading(im, "Born 14 November 1963", "Iceland's youngest island", 600, 104)
    rows(im, [("1963", "An eruption under the sea, 18 km off Heimaey, builds a new island.", ACCENT),
              ("1967", "The eruption ends on 5 June, after three and a half years.", YELLOW),
              ("2008", "UNESCO World Heritage: a natural laboratory of how life arrives.", AURORA)], y + 26, h=136, big=60, left=250)
    source(im, "Environment Agency of Iceland; UNESCO")
im = canvas(); b_surtsey(im); decorate(im, "post-07-surtsey", 1, 1, BG); brand(im); footer(im); save(im, "post-07-surtsey", 1)
print("ok")
