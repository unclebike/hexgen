# Fonts

Self-hosted, so the game looks the same on every device. The web build loads
the `.woff2` files (the `.ttf` for Alfa Slab One) and waits for them before it
draws anything. The iOS app bundles the `.ttf` files and registers them at launch.

| File | Source | Used for |
| --- | --- | --- |
| `DialhexArchivoExpanded-ExtraBold` | Archivo, wdth 125, wght 800 | headings and labels |
| `DialhexArchivoExpanded-Medium` | Archivo, wdth 125, wght 500 | secondary text (nothing lighter than 500) |
| `DialhexJetBrainsMono-Bold` | JetBrains Mono, wght 700 | score and timer |
| `DialhexArchivoCondensed-ExtraBold` | Archivo, wdth 62, wght 800 | riso skin |
| `DialhexArchivoExpanded-Black` | Archivo, wdth 125, wght 900 | acid skin |
| `DialhexVT323-Regular` | VT323 | crt skin |
| `AlfaSlabOne-Regular.ttf` | Alfa Slab One, unmodified | flash skin |

All are under the SIL Open Font License 1.1 (`OFL-*.txt`). The first six are
static instances of the variable fonts, renamed and cut down to Latin by
`build.py`. Sources:

- https://github.com/google/fonts/raw/main/ofl/archivo/Archivo%5Bwdth,wght%5D.ttf
- https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf
- https://github.com/google/fonts/raw/main/ofl/vt323/VT323-Regular.ttf
- https://github.com/google/fonts/raw/main/ofl/alfaslabone/AlfaSlabOne-Regular.ttf
