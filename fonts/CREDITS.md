# Font Credits

All fonts come from the Google Fonts repository (https://github.com/google/fonts). The full license texts are in `licenses/`.

| File | Use | Font | Source | Author | License |
|---|---|---|---|---|---|
| `scrawl.ttf` | Frantic blood writing on walls | Rock Salt Regular | https://github.com/google/fonts/tree/main/apache/rocksalt | Font Diner (Sideshow) | Apache License 2.0 (`licenses/rocksalt_LICENSE.txt`) |
| `journal.ttf` | Messy, readable pen handwriting for notes | Reenie Beanie | https://github.com/google/fonts/tree/main/ofl/reeniebeanie | James Grieshaber (Typeco) | SIL Open Font License 1.1 (`licenses/reeniebeanie_OFL.txt`) |
| `sign.ttf` | Clean institutional signage | Roboto Condensed Bold | https://github.com/google/fonts/tree/main/ofl/robotocondensed | Christian Robertson / Google | SIL Open Font License 1.1 (`licenses/robotocondensed_OFL.txt`) |
| `ui.ttf` | Menus and subtitles | Inter Regular | https://github.com/google/fonts/tree/main/ofl/inter | Rasmus Andersson / The Inter Project Authors | SIL Open Font License 1.1 (`licenses/inter_OFL.txt`) |

## Modifications

- `sign.ttf` and `ui.ttf` are static instances made with fontTools `varLib.instancer` from the upstream variable fonts. `sign.ttf` comes from `RobotoCondensed[wght].ttf` at wght=700. `ui.ttf` comes from `Inter[opsz,wght].ttf` at wght=400, opsz=14. The internal names were updated. These fonts were not renamed with a Reserved Font Name.
- `scrawl.ttf` and `journal.ttf` are unmodified upstream files, only renamed.
