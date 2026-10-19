# build.py — Make the static, Latin-subset fonts in this folder from the OFL sources
#
#   python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools brotli
#   mkdir -p fonts/src  # then download the four sources listed in fonts/README.md into it
#   /tmp/fontenv/bin/python fonts/build.py   # run from the repo root
#
# Each output is renamed with a "Dialhex" prefix so it can't clash with a copy
# of the same family the player has installed (and so the web and iOS builds
# ask for exactly the same font names).

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

LATIN = list(range(0x20, 0x7F)) + [0xA0, 0xB7, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026]


def rename(font, family, ps):
    names = font['name']
    for record in list(names.names):
        if record.nameID in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25):
            names.removeNames(nameID=record.nameID)
    names.setName(family, 1, 3, 1, 0x409)
    names.setName('Regular', 2, 3, 1, 0x409)
    names.setName(f'{ps};dialhex', 3, 3, 1, 0x409)
    names.setName(family, 4, 3, 1, 0x409)
    names.setName(ps, 6, 3, 1, 0x409)
    if 'STAT' in font:
        del font['STAT']


def save(font, ps):
    options = subset.Options()
    options.layout_features = ['kern', 'liga', 'tnum', 'case']
    options.name_IDs = ['*']
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=LATIN)
    subsetter.subset(font)
    font.flavor = None
    font.save(f'fonts/{ps}.ttf')
    font.flavor = 'woff2'
    font.save(f'fonts/{ps}.woff2')


def instance(src, axes, family, ps, weight):
    font = instantiateVariableFont(TTFont(src), axes)
    rename(font, family, ps)
    font['OS/2'].usWeightClass = weight
    font['OS/2'].usWidthClass = 5
    save(font, ps)


ARCHIVO = 'fonts/src/Archivo[wdth,wght].ttf'

# Base brand: headings and labels, secondary text, digits
instance(ARCHIVO, {'wdth': 125, 'wght': 800}, 'Dialhex Archivo Expanded Heavy', 'DialhexArchivoExpanded-ExtraBold', 800)
instance(ARCHIVO, {'wdth': 125, 'wght': 500}, 'Dialhex Archivo Expanded', 'DialhexArchivoExpanded-Medium', 500)
instance('fonts/src/JetBrainsMono[wght].ttf', {'wght': 700}, 'Dialhex JetBrains Mono', 'DialhexJetBrainsMono-Bold', 700)

# Skins
instance(ARCHIVO, {'wdth': 62, 'wght': 800}, 'Dialhex Archivo Condensed Heavy', 'DialhexArchivoCondensed-ExtraBold', 800)
instance(ARCHIVO, {'wdth': 125, 'wght': 900}, 'Dialhex Archivo Expanded Black', 'DialhexArchivoExpanded-Black', 900)
vt323 = TTFont('fonts/src/VT323-Regular.ttf')
rename(vt323, 'Dialhex VT323', 'DialhexVT323-Regular')
save(vt323, 'DialhexVT323-Regular')

# Alfa Slab One has a Reserved Font Name, so it ships unmodified: no subset,
# no rename, no WOFF2. Copy fonts/src/AlfaSlabOne-Regular.ttf in as it is.
