# Voxel Character Maker

A voxel character system and in-engine character editor for a 16-bit-JRPG-style
game, rendered in the spirit of the Voxel Doom mod: chunky, pixel-art-shaded
figures. Godot 4, GDScript.

`SPEC.md` holds every design decision. Read it before changing anything here.
`CLAUDE.md` holds the working conventions.

## What works now

| Area | State |
|---|---|
| Asset loading (6 bodies, 5 heads, 11 expressions) | done, validated against the files |
| Coordinate system and the mapping into Godot | done, locked by a test |
| Baked light/mid/dark shading | done, matches `build_bodies.py` |
| Region map (part family + band + side + front/back, 32 a side) | done |
| Parametric garments (regions, roles, bulk, mirror, edge style) | done |
| Layering by reach, then draw order | done |
| One-file wardrobe (v2) with exact round-trip | done; v1 files still open |
| Special shapes on any item | skirt, cape, hood, and a drawn shape anchored to the body |
| Eyes, hair, facial hair as their own kind of item | done |
| Mesher (exposed-face culling, vertex colours) | done |
| Rigid-part rig and test poses | done |
| Editor: four tabs (Bodies, Face & Hair, Clothes, Preview) | done |
| Body and head editing, saved beside the generated files | done |
| Review renders (`docs/renders/`) | done, including editor screenshots |
| Export (.vox / STL / OBJ) | deferred to game work (owner's call) |

See `docs/NOTES.md` for decisions taken while building, and for the things
still open.

## Running it

Godot 4.7 or newer.

```bash
godot --path .
```

The editor is the project's main scene. It has four tabs:

- **Bodies** -- the six bodies and five heads, bare: no hair, clothes or
  items, and only the basic eyes. Open a body or a head to edit it slice by
  slice.
- **Face & Hair** -- eye sets (expressions and eye colours), hair styles and
  facial hair. These work like clothes, but every character has exactly one of
  each ("none" counts as a choice). The head type can be changed here.
- **Clothes** -- every clothing item with all its settings, including any
  special shapes (skirts, capes, hoods, drawn shapes). Cycle through the six
  bodies to check an item on each. Colours and outfits are here too.
- **Preview** -- pick a body, head, eyes, hair, facial hair and clothes made in
  the other tabs and see the whole character. Nothing is edited there.

Edited bodies and heads are saved to `assets/edited/`, never over the
generated files, and are used in place of them when present. "Revert" deletes
the edit. `runtime/character_demo.tscn` shows the
same character assembled the way the game will do it, with no editor involved.

## Tests

Every acceptance check in `SPEC.md` section 12 is an automated test.
**1343 checks, all passing** on Godot 4.7.2.

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The expected asset numbers are not typed in by hand. They are measured from the
shipped assets by a separate script, which writes `tests/expected.json`:

```bash
python3 tools/verify_assets.py
```

Run that after regenerating anything in `assets/`, then run the Godot tests.

## Review renders

A test suite over a geometry pipeline can be green and still have the figure
come out wrong, so looking at it is part of checking it:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 \
    --script res://tools/render_sheets.gd -- --out docs/renders
```

Drop `xvfb-run -a` on a machine with a display. Writes the six bodies bare,
the six dressed in one parametric outfit, every test pose, and the special
items, all labelled and orthographic so they can be compared.

The editor builds its whole UI in code and the tests run headless, so nothing
else here ever renders a control. To look at one:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 \
    --script res://tools/screenshot_editor.gd -- --out docs/renders \
    --tab Bodies --edit-body --row 22
```

Other options: `--tab "Face & Hair" --section Eyes`, `--tab Clothes --select
dress`, `--edit-head`, `--scroll PX`, `--name FILE`.

## Regenerating assets

`tools/build_bodies.py` is the source of truth for bodies, heads and faces
(Python 3 + numpy). It rewrites every file in `assets/`:

```bash
cd assets && python3 ../tools/build_bodies.py
```

Asset JSON is generated, never hand-edited.

## Layout

```
core/        the shared character pipeline: assembler, bulk generation,
             shading, region map, wardrobe model, mesher
core/specials/   special shapes bulk cannot express (skirt, cape, hood,
             drawn shapes) and the body anchors they hang from
runtime/     the rig the game uses, and the test poses
editor/      the in-engine editor, which calls the same core
editor/workspaces/   its four tabs
tests/       headless acceptance checks
tools/       asset generation and the asset-fact oracle
assets/      generated bodies, heads and faces
assets/edited/   bodies and heads saved from the editor (created on first save)
docs/        review renders, and build notes
reference/   earlier prototypes, for feature ideas only
```

The one rule that shapes all of this: **the character assembler exists exactly
once**, in `core/character_assembler.gd`, and the editor and the game both call
it. Two implementations of bulk generation would drift (`SPEC.md` section 8).

## Accessibility

The owner is red/green colour blind, dyslexic, and has ADHD. In this codebase
that means: no editor state is signalled by red versus green alone, every
swatch is listed with its name and hex value, labels are short and literal, and
the figure, the open file and the current selection stay on screen.
