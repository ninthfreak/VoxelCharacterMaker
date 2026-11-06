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
| Region map (part family + band + side + front/back) | done |
| Parametric garments (regions, roles, bulk, mirror, edge style) | done |
| Layering by reach, then draw order | done |
| One-file wardrobe with exact round-trip | done |
| Special items | hood and skirt; skirt hangs cloth panels |
| Mesher (exposed-face culling, vertex colours) | done |
| Rigid-part rig and test poses | done |
| Editor: preview, wardrobe, garment regions, colours, outfits | done |
| Face editor | not started |
| Review renders (`docs/renders/`) | done, including editor screenshots |
| Export (.vox / STL / OBJ) | deferred to game work (owner's call) |
| Body editor | slice editing, mirror pairs, live checks |

See `docs/NOTES.md` for decisions taken while building, and for the things
still open.

## Running it

Godot 4.7 or newer.

```bash
godot --path .
```

The editor is the project's main scene. `runtime/character_demo.tscn` shows the
same character assembled the way the game will do it, with no editor involved.

## Tests

Every acceptance check in `SPEC.md` section 12 is an automated test.
**1062 checks, all passing** on Godot 4.7.2.

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
    --tab Body --edit-body --row 22
```

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
core/specials/   generators for shapes bulk cannot express (hood, skirt)
runtime/     the rig the game uses, and the test poses
editor/      the in-engine editor, which calls the same core
tests/       headless acceptance checks
tools/       asset generation and the asset-fact oracle
assets/      generated bodies, heads and faces
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
