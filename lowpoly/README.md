# Low-poly bodies

The project is moving from voxels to a low-poly style (owner's decision, `SPEC.md` §0). This folder holds that work
so far: the bodies, and the Python scripts that make and check them. Nothing in `core/`, `runtime/` or `editor/`
builds polygons yet; the Godot project still runs the voxel system.

Godot ignores this folder (`.gdignore`), so nothing here is imported into the project.

## Where it stands

| Area | State |
|---|---|
| Clay bodies (the smooth forms the bodies are cut from) | feminine average (approved), masculine average (first pass, "decent") |
| Bodies cut on the clothing regions | those two; 412 polygons (854 triangles) each, same layout of polygons |
| Region map on the bodies (32 a side, same bands and heights as the voxel bodies) | done, checked |
| Rigid parts and pivot heights (the same 11) | tagged on every polygon; nothing poses them yet |
| Ordinary garments from the wardrobe file (regions, roles, bulk, mirror, layering) | prototype in Python, shown on both bodies |
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
   clothing region and is tagged with its region key (`upper_chest.L.F`, `forearm.R`...) and its rigid part.

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
| `rings.py` | cutting a clay into rings; also the first look test (bodies "A" and "B" of the first sheet) |
| `body.py` | the bodies the clothing system uses; writes `bodies/*.json` and `*.obj` |
| `dress.py` | **prototype**: garments from the wardrobe file onto a body (see the note below) |
| `picture.py` | pictures of polygon meshes: flat shade, smooth shade, edges drawn |
| `sheets.py` | builds the review sheets in `renders/` |
| `check.py` | checks the band table, the geometry, the regions, and that the body files match a rebuild |
| `dump_wardrobe.gd` | writes the project's starter wardrobe as JSON, for `dress.py` |
| `bodies/` | the body files: corners, polygons with region and part, pivots, the band table. Generated; do not hand-edit |
| `renders/` | the review sheets the owner judged the look from |

`dress.py` is a second copy of garment rules whose home is `core/` (the project keeps that logic in exactly one
place). It exists to prove that the regions and the parameters carry over to polygons. When the Godot side builds
polygons the rules belong there, and `dress.py` should go or shrink to a cross-check.

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

`check.py` also runs as part of `tests/run.sh` when numpy is installed. `sheets.py` takes `look`, `male`, `regions`
or `all`; the clay pictures take about 40 seconds a view and are kept in `lowpoly/_work/` for the next run.

## Not decided yet

All of these are the owner's to settle. Recommendations are recommendations.

1. **Polygon budget.** The bodies are 412 polygons with an edge on every region boundary. The first look test
   showed 273 ("A", no region edges) and 603 ("B"); work since has used A. For scale: the 1997 Final Fantasy VII
   battle model of Cloud is put at about 900 polygons for the whole character.
2. **Flat or smooth shading.** It changes the look more than the polygon count does. The voxel system's baked
   light/mid/dark does not carry over as it is, and the owner dislikes baked shading on 3D objects.
3. **How far one step of bulk stands off the body.** One old voxel (4.2 cm) now; it reads puffy on sleeves. One number
   in `dress.py` (`BULK_UNIT`).
4. **Joints.** The torso and legs are one skin, which looks best standing still. To pose it, either the pieces are
   split at the joints and allowed to overlap, or the skin bends with the bones. Not looked at yet.
5. **Edge style.** Soft and hard edges were about which corner voxels to drop; they need a new meaning or to go.
6. **The masculine clay** is a first pass: shoulder width (about 20% wider than the feminine), the amount of chest
   muscle, the slight belly and arm thickness are the parts most open to change.
