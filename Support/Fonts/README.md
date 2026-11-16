# Theme fonts

Google Fonts used by the designed themes, from https://github.com/google/fonts (`ofl/`). Each family is under
the SIL Open Font License 1.1 (its `OFL.txt` is next to it), which allows bundling them with the app.

| Family | Used by |
|---|---|
| Bodoni Moda (+ italic) | Pearl, Lacquer |
| Cinzel | Elvenlight, Forged Gold |
| Cormorant Garamond | Celestial, Astrolabe |
| Orbitron | Chrome Day, Night City, Lab, Laser Grid, Laser Red |
| Bungee | Arcade Flyer, Arcade Cabinet |
| Tilt Neon | Highlighter, Neon Sign |

`scripts/build.sh` copies this folder into `WheelSmith.app/Contents/Resources/Fonts`, and the app registers the
fonts for itself at launch (`ThemeFonts.register()`); nothing is installed system-wide.
