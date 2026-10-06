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
| Q / Z | Lean left / right around a corner (stops short of walls) |
| E / LMB | Interact, press keypad buttons, put a page away |
| F | Flashlight |
| R | Swap in spare batteries (only once the beam is below half) |
| G / RMB | Throw an almond-water bottle |
| Tab / J | Re-read collected journal pages |
| Esc | Pause |

Footsteps are judged by how fast you actually move, so creeping while reading
a page is as quiet as crouching. The breaker room and the stairwell have
concrete floors: steps there are louder and carry further. A failed action
(no bottle, no spare batteries, hands full) gets an empty pocket-pat and a
short thought instead of silence. Your hands tremble and a heartbeat rises
when something is close or hunting you.

## Entities

| Entity | Strengths | Weaknesses |
|---|---|---|
| **The Hollow**: 2.5 m, eyeless, emaciated | Faint sounds (crouch steps, distant walking) make it investigate; repeated or loud steps make it hunt, and when hunting it is faster than you can sprint. Hearing carries along corridors and loses range per wall. It searches 2–4 cells around the last sound and turns toward Watcher scrapes. | It is blind and only kills while hunting. Bumping into it outside a hunt makes it freeze and sniff for 2.5–4 s: stand still and it moves on; any step then starts a hunt. A thrown bottle pulls it to where the bottle lands. |
| **The Smiler**: a grin in the dark | Can't be stopped in darkness. It drifts toward you whenever you stand in an unlit area (dead and flickering panels count), moves faster when your light is off, and drifts toward the lever and alarm through the dark. | It can't enter lit areas and is harmless while fading. Hold the beam on its face for about 2 s and it recoils and re-forms somewhere out of view; a dim beam hurts it less. |
| **The Watcher**: a spider-limbed crawler, wakes when power returns (or early, on a wrong breaker pull) | Fast and almost silent. It roams, chases on sight, and hears steps, the lever and the alarm. Its scrape gets louder and faster as it nears. | It freezes only when it is near the centre of your view (about 20° off-centre), within 25 m, lit, and you aren't reading. Break line of sight and it loses you, goes to where it last saw you and searches. |

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
   ambiguous. The breaker switches have ON/OFF marks and red/pale flag
   windows. Pulling the main lever with the wrong pattern causes a 28 s
   total blackout, every entity hears it (70 m), and it wakes the Watcher
   early. The correct pull is quieter (30 m).
3. With power restored, the keypad shows six symbols in order. Each digit is
   painted on a wall in blood beside its symbol. The brown, dried writings
   are lies left by someone earlier. Only the fresh red, still-wet ones (they
   glint under the beam) are true. The journal auto-adds a "Numbers on the
   walls" page logging every symbol and number you've seen, tagged "red, wet"
   or "brown, dry". The keypad's red LED blinks once per try left. Three
   wrong codes set off an alarm every entity hears.

</details>

## Dying, retrying and settings

The death screen names what got you. "Try again" keeps the layout but
rerolls the clues, the code and the monster spawns; "New level" uses a new
seed. A bad generation (unreachable page, prop or code, or a failed puzzle)
silently regenerates at seed+1. Esc/P pauses, and gameplay timers pause with
the game. Sensitivity, subtitles, master volume and FOV are saved to
`user://settings.cfg`. The camera's fear grain only reacts to monsters in
line of sight.

## Project layout

- `scripts/level.gd`: seeded grid generator, merged geometry, pooled real lights, decals, signs, A* pathing
- `scripts/puzzle.gd`: breaker clue generator (uniqueness + minimality) and keypad code
- `scripts/player.gd`, `scripts/hands.gd`: controller (lean, fear, gait-from-speed footsteps) and first-person arms: downloaded skinned hand models (`models/hands`) posed per finger bone, procedural forearms/sleeves and torch; the beam follows the camera, not the hand
- `scripts/audio.gd`: buses, per-zone reverb (halls, wing, breaker room, stairwell), occlusion at three heights with doorway diffraction via A*, heartbeat/breath dread layer
- `scripts/entities/*`: AI for the Hollow, the Smiler and the Watcher, plus `creature.gd` (skinned sculpt loader + procedural animation)
- `tools/sculpt_creatures.py`: SDF anatomy → marching cubes → auto-skinning → `meshes/*.crt` (plus `_lod` meshes)
- `tools/gen_decals.py`: blood, damp-stain decals and the six keypad symbols
- `tools/gen_sfx.py`: concrete footsteps (re-EQ'd carpet steps), heartbeat, fumble
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
- `--nointro`: skip the fall-through-the-floor intro (auto-skipped with `--autosolve`, `--bench`, `--look`, `--goto`, `--entity`, and with `--shot` unless `--intro` is also given, e.g. `--shot=x.png --intro --wait=1.5` captures mid-fall)
- `--autosolve`: smoke test that solves the run through the real interaction handlers and walks out

## Credits

Texture, font, model and sound sources and their licences are listed in
`textures/CREDITS.md`, `fonts/CREDITS.md`, `models/hands/CREDITS.md` and
`audio/sfx/CREDITS.md`.
