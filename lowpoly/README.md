# Low-poly characters

The characters are low-poly (owner's decision, `SPEC.md` section 0). This folder holds what exists of them so far:
the bodies, and the Python that makes, dresses, poses and checks them. Nothing in `core/`, `runtime/` or `editor/`
builds polygons yet; the Godot project still runs the earlier voxel system.

Godot ignores this folder (`.gdignore`), so nothing here is imported into the project.

## Decided so far

- **Style:** low-poly, at about the level of detail of Final Fantasy VII.
- **Bodies are cut from smooth clay models** on the clothing regions (method below).
- **Joints: the body is one skin that bends.** Rigid pieces were built, compared and rejected for the body
  (`renders/joints_rigid_or_bend.png`). Clothing may need to be different from the body at the joints; open.

## Where it stands

| Area | State |
|---|---|
| Clay bodies (the smooth forms the bodies are cut from) | feminine average (approved), masculine average (first pass, "decent") |
| Bodies cut on the clothing regions | those two; 412 polygons (854 triangles) each, same layout of polygons |
| Region map on the bodies (32 a side, same bands and heights as the voxel bodies) | done, checked |
| Joints: one bending skin over the same 11 parts | done: every corner's shares and every pivot are in the body files; posed in Python |
| Ordinary garments from the wardrobe file (regions, roles, bulk, mirror, layering) | built in Python, shown on both bodies; they bend with the body |
| Clothing that should not bend with the body (hard pieces, hanging cloth) | not settled |
| Special shapes (skirt, cape, hood, straps, facial hair, anchored shapes) | not started |
| Edge style (soft / hard) | not carried over |
| Heads and faces | a stand-in block that carries the head regions; no real head |
| The other six bodies (slim, heavy and short, each sex) | not started; each needs a clay |
| Building polygons in Godot (assembler, editor, runtime) | not started |

## How a body is made

1. **Clay** (`clay.py`). A body is a handful of rounded volumes blended into one smooth form. Its unit is the old
   voxel (24 to the metre), so heights are the old rows: 42 tall, mirror plane at x = 12, front toward -y.
2. **Rings** (`rings.py`). Rings of a few points are placed on the clay at chosen heights and joined into four-sided
   polygons. Points sit where the outline is widest, deepest or furthest forward, so the front and side outlines of the
   clay are kept at every ring. Torso, neck and legs are one continuous skin; arms, feet and head are separate closed
   pieces that overlap it.
3. **Regions** (`body.py`). The rings sit on every boundary of the band table, so each polygon lies in exactly one
   clothing region and is tagged with its region key (`upper_chest.L.F`, `forearm.R`...) and its part.
4. **Joints** (`body.py`). Each corner gets its shares: the parts it follows when the figure moves. The hinge joints
   (neck, waist, elbow, knee) sit in their one-row trim bands: the band's two edge loops share the bend 75/25 and
   25/75, and the pivot is at the middle of the band. The hip bends on the leg-opening loop. The shoulder is a ball:
   the arm is a separate piece turning about the centre of its shoulder.

Three places where a region follows the body instead of a level line:

- **Hips / upper thigh:** the boundary is the leg opening, level 11 at the outside of the hip and dropping to the
  crotch. A level line would leave the crotch outside "hips", because this pelvis hangs lower between the legs than
  the voxel one, which simply ended at row 11.
- **Front / back:** split along the side seam (the widest point of each ring), within half a unit of the depth centre.
- **Arm top and foot top:** they stand a little past their bands' heights and are tagged "shoulder" and "foot".

## Files

| File | What it is |
|---|---|
| `clay.py` | the clay bodies and the smooth-shape maths; draws a clay body |
| `rings.py` | cutting a clay into rings; also the first two cuts ("A" and "B") that the look was approved from |
| `body.py` | the bodies: regions, parts, joints; writes `bodies/*.json` and `*.obj` |
| `dress.py` | garments from the wardrobe file onto a body (see the note below) |
| `pose.py` | posing: the bending skin, and the rigid-piece alternative kept for clothing that must not bend |
| `picture.py` | pictures of polygon meshes: flat shade, smooth shade, edges drawn |
| `sheets.py` | builds the review sheets in `renders/` |
| `check.py` | checks the band table, the geometry, the regions, and that the body files match a rebuild |
| `dump_wardrobe.gd` | writes the project's starter wardrobe as JSON, for `dress.py` |
| `bodies/` | the body files: corners and their shares, polygons with region and part, pivots, the band table. Generated; do not hand-edit |
| `renders/` | the sheets each decision was made from |

`dress.py` holds the garment rules for polygons in Python. The project keeps that logic in exactly one place, and
that place is `core/` (GDScript), which today only knows voxels. When the Godot side builds polygons the rules move
there, and `dress.py` goes or shrinks to a cross-check.

## Running it

Needs Python 3 with numpy, and Pillow for pictures. From the repository root:

```bash
python3 lowpoly/check.py
```

```bash
python3 lowpoly/body.py
```

```bash
GODOT=/path/to/godot python3 lowpoly/sheets.py all
```

`check.py` also runs as part of `tests/run.sh` when numpy is installed. `sheets.py` takes `look`, `male`, `regions`,
`joints` or `all`; the clay pictures take about 40 seconds a view and are kept in `lowpoly/_work/` for the next run.

## Not decided yet

All of these are the owner's to settle. Recommendations are recommendations.

1. **Clothing at the joints.** Cloth lifted off the body bends with it, and that is built. The owner expects some
   clothing to need something different. Candidates: hard pieces fixed to one part so they never bend (which could
   be what the "hard" edge style comes to mean), and hanging cloth such as skirts and capes, which does not follow
   the legs at all.
2. **Polygon budget.** The bodies are 412 polygons with an edge on every region boundary. The first two cuts were
   273 ("A", no region edges) and 603 ("B"); work since has used A. For scale: the 1997 Final Fantasy VII battle
   model of Cloud is put at about 900 polygons for the whole character.
3. **Flat or smooth shading.** It changes the look more than the polygon count does. The voxel system's baked
   light/mid/dark does not carry over as it is, and the owner dislikes baked shading on 3D objects.
4. **How far one step of bulk stands off the body.** One old voxel (4.2 cm) now; it reads puffy on sleeves. One number
   in `dress.py` (`BULK_UNIT`).
5. **Edge style.** Soft and hard edges were about which corner voxels to drop; they need a new meaning (see 1) or to
   go.
6. **The masculine clay** is a first pass: shoulder width (about 20% wider than the feminine), the amount of chest
   muscle, the slight belly and arm thickness are the parts most open to change.

Known weak spots of the bending skin, at this polygon count: a sharp bend loses a little volume on the inside of the
joint, and the inner thigh stretches flat on a very high step. The shoulder is a ball, so a raised sleeve cuts into
the chest instead of flowing into it.
