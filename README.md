# Voxel Character Maker

A character system and in-engine character editor for a 16-bit-JRPG-style game.
Godot 4, GDScript.

**The characters are low-poly** (owner's decision, 2026-11; `SPEC.md` section 0).
The project began as a voxel system and the repository keeps that name; the
voxel code was removed once the low-poly figure did what it did (the last
commit with it is `fa40fa0`).

The bodies and heads, and the rules that dress, pose and check them, are made
in Python first, in `lowpoly/` (its README says what exists and how). The game
builds the same characters in GDScript, in `core/lowpoly/`, and is checked
against the Python corner by corner.

`SPEC.md` holds every design decision. Read it before changing anything here.
`CLAUDE.md` holds the working conventions.

## What works now

| Area | State |
|---|---|
| Eight bodies (slim, average, heavy, short; each sex) and five heads | made in `lowpoly/`, read from `assets/lowpoly/` |
| One skin that bends at its joints; the test poses | done (`runtime/lowpoly_rig.gd`) |
| Coordinate system and the mapping into Godot | done, locked by a test |
| Region map (part family + band + side + front/back, 32 a side) | done |
| Garments made of regions: roles, bulk, hems, layering, mirror | done |
| Faces: eye sets, colours, ten lid states, lids, brows, a mouth, six skin tones | done |
| Facial hair: four parts and one length | done |
| Straps, skirts and capes; skirts and capes laid standing, then following cloth bones the legs turn | done |
| One-file wardrobe (v4: saved characters, held items) with exact round-trip | done; older files and the old facial hair styles still open |
| Held items: built from simple parts, held in a hand, kept by saved characters | done (`core/held_item_shape.gd`) |
| Editor: four tabs (Face & Hair, Clothes, Items, Preview), flat or smooth shading, picking regions on the figure | done |
| Hood (raised or lowered) | done |
| Shapes of their own: long beard, ponytail, bun, horns, pauldrons (replacing the voxel drawn shape) | done |
| Edge style | kept in the wardrobe file, not on the figure yet |
| Export (.vox / STL / OBJ) | OBJ copies of the bodies and heads in `lowpoly/`; the rest deferred |

See `docs/NOTES.md` for decisions taken while building, and for the things
still open.

## Running it

Godot 4.7 or newer.

```bash
godot --path .
```

The editor is the project's main scene. It has four tabs:

- **Face & Hair** -- eye sets (the open eye and eye colours), hair styles and
  facial hair. These work like clothes, but every character has exactly one of
  each ("none" counts as a choice). The head type can be changed here.
- **Clothes** -- every clothing item with all its settings, including any
  special shapes. Cycle through the eight bodies to check an item on each.
  Click the figure to pick a region. Colours and outfits are here too.
- **Items** -- held items (weapons, shields, tools, potions), built from simple
  parts: boxes, wedges, cylinders, cones, spheres, and shapes drawn on a grid
  (an outline given thickness, or half a side view spun round). Put together by
  hand in the view: click a part to choose it, drag it to move it, pull the
  squares on its sides to size it, the ring to turn it; the buttons above the
  view add parts; Ctrl+C, Ctrl+V and Ctrl+X copy, paste and cut a part. The
  numbers in the panel follow, for fine work. On the Grip
  sub-tab, drag the hand to say where and how the item is held. See the item
  alone, or in a character's right or left hand.
- **Preview** -- pick a body, head, skin tone, eyes, eyelids, brows, mouth,
  hair, facial hair, clothes and what each hand holds, made in the other tabs, and see the whole
  character, posed or animated (idle, walk). Save it as a character (the
  Saved characters list at the top: save as new, update, rename, delete); the
  game builds one by its name.

The bodies and heads are made in Python (`lowpoly/`), not edited in the game.
`runtime/character_demo.tscn` shows the saved characters built the way the game
does it (`GameCharacter`), walking on the spot, with no editor involved.

## Tests

```bash
tests/run.sh
```

runs the Godot checks (`tests/run_tests.gd`: the coordinate lock, the wardrobe,
the model, the low-poly figure against the Python, the editor) and, where
Python 3 with numpy is installed, the low-poly Python checks
(`lowpoly/check.py`). After changing anything in `lowpoly/`, regenerate what
the game reads and the numbers Godot is held to:

```bash
python3 lowpoly/body.py
```

```bash
python3 lowpoly/heads.py
```

```bash
python3 lowpoly/expected.py
```

## Looking at it

A test suite over a geometry pipeline can be green and still have the figure
come out wrong, so looking at it is part of checking it. `lowpoly/sheets.py`
draws the review sheets (`lowpoly/renders/`). The editor builds its whole UI in
code and the tests run headless, so to look at a tab:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/screenshot_editor.gd -- --out docs/renders --tab Preview --preview outfit=dress --preview pose=sitting
```

Other options: `--tab "Face & Hair" --section Eyes`, `--tab Clothes --select
skirt`, `--view back`, `--set body_id=female_short`, `--scroll PX`,
`--name FILE`. Drop `xvfb-run -a` on a machine with a display.

To see what the editor's common actions cost, and how many times each one
rebuilds a figure:

```bash
godot --headless --path . --script res://tools/bench_editor.gd
```

## Layout

```
core/            the wardrobe model, eye sets and lid states, mouths, palette,
                 region map, the character request, the axes
core/lowpoly/    the low-poly figure: library, assembler, face, facial hair,
                 special shapes, hanging cloth, posing in full precision
core/specials/   special shapes' settings (and facial hair's)
runtime/         the rig the game uses, the test poses, a demo scene
editor/          the in-engine editor, which calls the same core
editor/workspaces/   its four tabs
tests/           headless checks
tools/           editor screenshots, and timings of the editor's actions
assets/lowpoly/  generated bodies, heads and the region table
lowpoly/         the Python that makes and checks all of it
docs/            build notes and review renders
reference/       earlier prototypes, for feature ideas only
```

The one rule that shapes all of this: **the character assembler exists exactly
once**, in `core/lowpoly/lowpoly_assembler.gd`, and the editor and the game
both call it (`SPEC.md` section 8).

## Accessibility

The owner is red/green colour blind, dyslexic, and has ADHD. In this codebase
that means: no editor state is signalled by red versus green alone, every
swatch is listed with its name and hex value, labels are short and literal, and
the figure, the open file and the current selection stay on screen.
