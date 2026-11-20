# Low-poly characters

The characters are low-poly (owner's decision, `SPEC.md` section 0). This folder holds what exists of them so far:
the bodies and heads, and the Python that makes, dresses, poses and checks them. Nothing in `core/`, `runtime/` or
`editor/` builds polygons yet; the Godot project still runs the earlier voxel system.

Godot ignores this folder (`.gdignore`), so nothing here is imported into the project.

## Decided so far

- **Style:** low-poly, at about the level of detail of Final Fantasy VII.
- **Bodies are cut from smooth clay models** on the clothing regions (method below).
- **Joints: the body is one skin that bends.** Rigid pieces were built, compared and rejected for the body
  (`renders/joints_rigid_or_bend.png`). Clothing may need to be different from the body at the joints; see "How
  clothing moves" below for what is built, and "Not decided yet" for what is the owner's to judge.

## Where it stands

| Area | State |
|---|---|
| Clay bodies (the smooth forms the bodies are cut from) | feminine average (approved), masculine average (first pass, "decent") |
| Bodies cut on the clothing regions | those two; 344 polygons (710 triangles) each without a head, same layout of polygons |
| Region map on the bodies (32 a side, same bands and heights as the voxel bodies) | done, checked |
| Joints: one bending skin over the same 11 parts | done: every corner's shares and every pivot are in the body files; posed in Python |
| Ordinary garments from the wardrobe file (regions, roles, bulk, mirror, layering) | built in Python, shown on both bodies; they bend with the body |
| Special shapes: straps, skirt, cape | built, with every setting the voxel ones have; all seven starter outfits dress both bodies (`renders/special_shapes.png`, `renders/special_shapes_moving.png`) |
| Special shapes: hood, facial hair, drawn (anchored) shapes; hair | not started. The cloak is worn without its hood |
| Edge style (soft / hard) | not carried over. The boots ask for "hard" and are built soft |
| Heads | all five (round, boxy, oval, strong, heart) as rounded forms: 114 polygons each, same layout; any head goes on any body. How the face sits on them is waiting for the owner's choice (`renders/heads.png`) |
| Faces (eyes, lids, brows) | not rebuilt. Every head keeps the flat face and the eye boxes they need; the open eye is placed as flat polygons for pictures only |
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

## How a head is made

A head is seven rings of points, top to bottom, closed by a point at the crown and a flat base (`heads.py`). Each ring
is given by three numbers: its half-width, and its depth in front of and behind the centre. Those numbers, and how
square the back is, are the whole shape. Every ring is laid out the same way: the face, cheeks that turn the corner in
steps, the side seam, a rounded back. So a head has a domed crown, a round back and a tapering jaw, like the bodies it
sits on. (The first rebuild was a block with bevelled edges; the owner found it too blocky:
`renders/heads_first_rebuild.png`.)

The five heads follow the ideas of the voxel heads without tracing them, and share what lets faces, hair and hats fit
any of them: the size (16 tall, 14 deep, 16 wide, the oval 14), the ears level with the eyes, one layout of polygons
with an edge on every head region, and the face.

**The face** is the one part that cannot simply be made round: each eye is 5 wide and 6 tall, the same on every head
(the owner's rule), and has to lie flat. `FACE_BEND` in `heads.py` says how:

- **0 (as committed): one flat face.** Both eye boxes and the brow row lie on one plane, as the spec has it. The front
  of the head stays flat, 12 wide.
- **15: each eye on its own flat patch**, the two turned 15 degrees outward and meeting down the middle of the face.
  The front of the head is then round as well. This changes the spec's "one face plane" to "one flat patch for each
  eye", so it is the owner's call.

## How clothing moves

Three ways, by what the clothing is:

- **It bends with the body.** A garment made of regions is the body's own polygons, recoloured or lifted off the
  body, and each corner keeps following what it was lifted from. Straps lie on the chest and follow it.
- **It hangs.** A skirt or a cape is hanging cloth (`hang.py`): a few columns of cloth, each fixed at its top (a skirt
  to the waist line, a cape to the shoulder line) and each a fixed length. For any pose, every column is a taut line
  from its top over whatever of the figure sticks out under it, then straight down, leaning out by the garment's
  flare. Nothing is simulated and nothing is remembered between poses, so standing still is one more pose. This is
  what makes a skirt fit the hips, let the forward knee push its front out, and lie over a lap.
- **It stays rigid.** Nothing does yet. `pose.posed_rigid` is kept for hard pieces, if they come to need it.

The voxel system turned hanging cloth by rule instead: each panel by 0.8 of a thigh's swing. That rule is not used
here; see "Not decided yet", 1.

## Files

| File | What it is |
|---|---|
| `clay.py` | the clay bodies and the smooth-shape maths; draws a clay body |
| `rings.py` | cutting a clay into rings; also the first two cuts ("A" and "B") that the look was approved from |
| `body.py` | the bodies: regions, parts, joints; writes `bodies/*.json` and `*.obj` |
| `dress.py` | garments from the wardrobe file onto a body (see the note below) |
| `specials.py` | the special shapes built so far: straps, skirt, cape, with the voxel generators' settings |
| `hang.py` | hanging cloth: how a skirt or a cape is laid over the figure in a pose |
| `heads.py` | the five heads; writes `heads/*.json` and `*.obj` |
| `pose.py` | posing: the bending skin, hanging cloth, the game's poses in this folder's terms, and the rigid-piece alternative |
| `picture.py` | pictures of polygon meshes: flat shade, smooth shade, edges drawn |
| `sheets.py` | builds the review sheets in `renders/` |
| `check.py` | checks the band table, the geometry, the regions, the files, and the clothing in every test pose |
| `game.py` | fetches what is taken from the game: the starter wardrobe, the test poses, the special shapes' settings |
| `dump_wardrobe.gd` | run by `game.py` in Godot: writes those as JSON into `_work/` |
| `bodies/` | the body files: corners and their shares, polygons with region and part, pivots, the band table. Generated; do not hand-edit |
| `heads/` | the head files: corners, polygons with their region, the eye box, the seven sections that define the shape. Generated |
| `renders/` | the sheets each decision was made from |

`dress.py`, `specials.py` and `hang.py` hold the clothing rules for polygons in Python. The project keeps that logic
in exactly one place, and that place is `core/` (GDScript), which today only knows voxels. When the Godot side builds
polygons the rules move there, and these files go or shrink to a cross-check. Nothing here copies the game's tables:
the wardrobe, the poses and the special shapes' settings are read from the game each time, and a check holds the
defaults equal.

## Running it

Needs Python 3 with numpy, and Pillow for pictures. From the repository root:

```bash
python3 lowpoly/check.py
```

```bash
python3 lowpoly/body.py
```

```bash
python3 lowpoly/heads.py
```

```bash
GODOT=/path/to/godot python3 lowpoly/sheets.py all
```

`check.py` also runs as part of `tests/run.sh` when numpy is installed. Its clothing checks, and every sheet with
clothes on it, ask Godot for the game's wardrobe and poses: set `GODOT=/path/to/godot` (or have `godot` on PATH).
Without Godot, `check.py` skips the clothing and says so.

`sheets.py` takes `look`, `male`, `regions`, `joints`, `heads`, `shapes`, `moving` or `all`; the clay pictures take
about 40 seconds a view and are kept in `lowpoly/_work/` for the next run.

## Not decided yet

All of these are the owner's to settle. Recommendations are recommendations.

1. **How hanging cloth moves.** Built: it is laid afresh for every pose ("How clothing moves" above). That was a
   call made while building, in place of the voxel rule (each panel turned by 0.8 of a thigh's swing), because a
   panel that turns cannot cover a lap when sitting and lifts its whole hem in every stride. It costs something on
   the Godot side: a skirt or cape becomes a small mesh whose points are worked out whenever the pose changes (about
   50 points a cloth), instead of a few bones turned by rule. Recommendation: keep it. The old rule could be rebuilt
   for polygons if the owner prefers it.
   Still open under the same heading: hard pieces fixed to one part so that they never bend (which could be what the
   "hard" edge style comes to mean), and sleeves at the shoulder.
2. **Polygon budget.** A body is 344 polygons with an edge on every region boundary, and a head 114: 458 for the
   figure. Dressed in a starter outfit a figure is about 500 to 540: a skirt adds about 40, a cape 20, a pair of straps
   about 36, and every band that is lifted off the body adds a ring of hem polygons. The first two cuts of the body
   were 273 ("A", no region edges, a plain block for a head) and 603 ("B"); work since has used A. For scale: the
   1997 Final Fantasy VII battle model of Cloud is put at about 900 polygons for the whole character.
3. **Flat or smooth shading.** It changes the look more than the polygon count does. The voxel system's baked
   light/mid/dark does not carry over as it is, and the owner dislikes baked shading on 3D objects.
4. **How far one step of bulk stands off the body.** One old voxel (4.2 cm) now; it reads puffy on sleeves. One number
   in `dress.py` (`BULK_UNIT`).
5. **Edge style.** Soft and hard edges were about which corner voxels to drop; they need a new meaning (see 1) or to
   go.
6. **The masculine clay** is a first pass: shoulder width (about 20% wider than the feminine), the amount of chest
   muscle, the slight belly and arm thickness are the parts most open to change.
7. **How the face sits on the head:** one flat face, or each eye on its own flat patch ("How a head is made" above;
   both are on `renders/heads.png`). Recommendation: the two patches, at 15 degrees. It is one number to change.
8. **Calls made in the special shapes** that differ from the voxel ones; each is easy to change:
   - a skirt hangs from the waist line, not from below the hips (a lap needs the cloth to lift off the hips);
   - "four panels" is one cloth all round; "two panels" is a front cloth and a back cloth with the sides open (the
     voxel four were separate slabs that parted at the corners when they swung);
   - an open front starts as a point at the hips and widens to the hem, instead of starting two units wide;
   - straps run from the shoulder straight to the front of the waist. The voxel rule, a plumb line from the shoulder,
     ends on the flank of these rounder bodies;
   - a strap is a flat band standing 0.12 units off what it lies on, with no thickness of its own;
   - a cape hangs from the shoulder line whatever the arms do. An arm swung far back goes through its edge.

Known weak spots of the clothing built so far: hands hang close to the hips, so a skirt with much flare meets them;
a bulky boot touches a shin-length hem and pushes it out a little; the wardrobe's shirt and trousers leave the waist
row bare between them (the voxel figure has the same strip of skin).

Known weak spots of the bending skin, at this polygon count: a sharp bend loses a little volume on the inside of the
joint, and the inner thigh stretches flat on a very high step. The shoulder is a ball, so a raised sleeve cuts into
the chest instead of flowing into it.
