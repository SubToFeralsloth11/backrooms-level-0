# The Backrooms - Level 0

First-person survival horror in Godot 4.7. Every run is a new seeded Level 0:
~5,000 m² of damp yellow wallpaper, humming fluorescent panels, a dark
maintenance wing and one steel door out.

No HUD bars and no sanity meter. You can tell you're out of breath because you
can hear yourself breathing, and you can tell the batteries are dying because
the beam dims and stutters. The character's thoughts appear as subtitles only.

## Run

Open the folder in Godot 4.7 and press Play, or run:

```sh
godot --path .
```

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Shift | Run (loud) |
| Ctrl / C | Crouch-walk (near-silent) |
| E / LMB | Interact, press keypad buttons, put a page away |
| F | Flashlight |
| R | Swap in spare batteries |
| G / RMB | Throw an almond-water bottle |
| Tab / J | Re-read collected journal pages |
| Esc | Pause |

## Entities

| Entity | Strengths | Weaknesses |
|---|---|---|
| **The Hollow**: 2.5 m, eyeless, emaciated | Hears footsteps through walls. When it is hunting, it is faster than you can sprint. | It is blind. If you crouch-walk or stand still, it can't find you. A thrown bottle pulls it to where the bottle lands. |
| **The Smiler**: a grin in the dark | Can't be stopped in darkness. It drifts toward you whenever you stand in an unlit area, and moves faster when your light is off. | It can't enter lit areas. Hold the flashlight beam on its face for about 2 s and it recoils and vanishes. Batteries are limited. |
| **The Watcher**: a spider-limbed crawler, wakes when power returns | Fast, and almost silent while you aren't looking at it. | It cannot move while you are looking at it in light. Darkness or a dead flashlight frees it. |

## The puzzle (spoilers)

<details>
<summary>How the escape works</summary>

1. Six journal pages are hidden across the level. One sits near spawn. Four
   carry breaker clues, and one of those four is inside the dark wing. The
   last page is in the breaker room.
2. The breaker room is in the maintenance wing. The clues (*"the second and
   the fifth never agree"*, *"of the first, third and sixth: exactly two
   up"*...) are generated each run as a **minimal** set: the switch pattern
   has exactly one solution, and leaving out any single page makes it
   ambiguous. Pulling the main lever with the wrong pattern causes a 28 s
   total blackout, and every entity hears the lever.
3. With power restored, the keypad shows six symbols in order. Each digit is
   painted on a wall in blood beside its symbol. The brown, dried writings
   are lies left by someone earlier. Only the fresh red ones are true. Three
   wrong codes set off an alarm every entity hears.

</details>

## Project layout

- `scripts/level.gd`: seeded grid generator, merged geometry, pooled real lights, decals, signs, A* pathing
- `scripts/puzzle.gd`: breaker clue generator (uniqueness + minimality) and keypad code
- `scripts/player.gd`, `scripts/hands.gd`: controller and procedurally built articulated hands
- `scripts/entities/*`: AI for the Hollow, the Smiler and the Watcher, plus `creature.gd` (skinned sculpt loader + procedural animation)
- `tools/sculpt_creatures.py`: SDF anatomy → marching cubes → auto-skinning → `meshes/*.crt` (plus `_lod` meshes)
- `tools/gen_decals.py`: blood, damp-stain decals and the six keypad symbols
- `data/lines.json`: subtitle lines

Regenerate assets with `python3 tools/sculpt_creatures.py` and `python3 tools/gen_decals.py`. The sculptor needs numpy, scipy and scikit-image.

## Performance

The target is **≥30 fps minimum**. A dynamic-resolution governor (`Game._process`)
scales the 3D render resolution between 45% and 100% (FSR upscale, UI stays
native) to hold 40–55 fps. Shaders are warmed up behind the opening black
screen. Creatures use a coarse LOD mesh for shadows and beyond 8 m.

Measured on Apple A18 Pro at 1600×900 with the flashlight on:

| Scenario | Avg fps | 1% low | Worst frame |
|---|---|---|---|
| Watcher at 1.6 m, power on | 57.2 | 44.0 | 41.8 |
| Blackout, Smiler at 2 m | 51.9 | 42.1 | 38.3 |
| Hollow at 1.8 m | 46.4 | 38.4 | 37.4 |

## Dev flags

Put these after `--`, for example `godot --path . -- --auto --bench=12`.

- `--auto`: skip the menu
- `--seed=N`: fixed level
- `--nomonsters`: no entities
- `--power`, `--blackout`, `--flash`: set the world state
- `--entity=hollow|smiler|watcher --dist=M --pitch=DEG`: frozen specimen placed in front of you
- `--goto=breaker|keypad|blood|oldblood|note`: stand in front of a puzzle prop
- `--shot=path.png --wait=S`: save a screenshot and quit
- `--bench=S`: print frame-time stats and quit
- `--autosolve`: smoke test that solves the run through the real interaction handlers and walks out

## Credits

Texture, font and sound sources and their licences are listed in
`textures/CREDITS.md`, `fonts/CREDITS.md` and `audio/sfx/CREDITS.md`.
