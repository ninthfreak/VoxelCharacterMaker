# Character System — Spec

**The characters are low-poly (owner's decision, 2026-11). Read section 0 first: it is the system as built.**
Sections 1 to 13 are the original design, made for voxel figures. What they decided about parts, regions, faces, the
wardrobe and the editor carried over; what they say about voxel geometry describes a system that was removed in phase
5 of the move (2026-11). Where they and section 0 disagree, section 0 wins.

Where this document says *recommended* it is a recommendation, not a decision; everything else was decided.

Owner preferences that apply to every decision: the owner assesses risk and tradeoffs personally, wants accurate
feasibility reads and visible uncertainty, and prefers to be asked when a choice is genuinely theirs. The owner is
red/green colour blind, dyslexic and has ADHD — see *Accessibility* under the editor.

---

## 0. The direction: low-poly (owner, 2026-11)

**The characters are low-poly. This is the project's direction, not an experiment.** The owner had taken the voxel
look as far as it would go, here and in earlier attempts of their own, and it kept ending short of the goal. Decided:

- **Style:** low-poly figures at about the level of detail of Final Fantasy VII, without that game's variety of
  character models.
- **Bodies:** the same conventions (masculine and feminine, three builds each), **plus a "short" body for each**, to
  use for dwarfs. Eight bodies.
- **Heads and faces:** nearly the same system as sections 4 and 5, not voxelised.
- **Clothing:** the same system as section 7 (regions with a colour role and a bulk, plus special shapes), not
  voxelised.
- **Editor:** it no longer edits bodies. It is for making clothing and items only.
- **Bodies come from smooth "clay" models**, cut into polygons by script. The feminine average clay is the approved
  starting point; the masculine average is a first pass the owner called decent.
- **The other builds work off the average** (owner): they must be compatible enough with the average body that
  every clothing rule still works. Slim, heavy and short of each sex are made from the average clays and cut the same
  way, so all eight bodies have the same corners and polygons, regions and joints: each is the average body with its
  corners moved (`lowpoly/renders/bodies_builds.png`; their shapes are a first pass). The short bodies, 36 tall with
  the same head, have the same bands at their own, lower heights, so section 3.3's identical row boundaries hold for
  the voxel bodies and the other low-poly builds, not for the short ones; see `lowpoly/README.md`.
- **Joints: the body is one skin that bends.** Each corner follows one part, or several in a fixed share (blended
  skinning). Rigid pieces with rounded ends were built and compared, and rejected for the body
  (`lowpoly/renders/joints_rigid_or_bend.png`). **Clothing may need to be different** from the body at the joints;
  what is built for that so far is below, and it is not settled.
- **Heads are rounded forms**, like the bodies. The first low-poly rebuild, blocks with bevelled edges, was too
  blocky.
- **The face: each eye lies on its own flat patch**, the two patches turned 15 degrees outward and meeting down the
  middle of the face, so that the front of the head is round too (`lowpoly/renders/heads.png`, "B"). This replaces
  section 5's single face plane. The eye box itself is unchanged: 5 wide, 6 tall, a brow row above, the same on
  every head.
- **The eyes are rounded ovals** at 0.9 of the voxel eye's size (4.5 wide, 5.4 tall), with their middle at the middle
  of the flat part of the face. The oval replaces section 5's drawing in cells; the lid states and colours of
  section 5 stay.
- **Lashes and eyebrows are two things.** Section 5's one thick bar on the eyelid, which is lashes and eyebrow at
  once and overhangs the eye, came from voxel art. On the low-poly face a thin lash line runs along the top edge of
  the open eye and never leaves it, and each eye has an eyebrow of its own above it.
- **The face has a small mouth**, low on the flat part of the face, with room left for a moustache above it and a
  beard under and round it. Its shapes are a first pass (`lowpoly/renders/faces.png`).
- **Facial hair is four parts and one length** (owner's design, replacing section 5.1's three styles): a moustache,
  sideburns, a goatee and the cheeks between them, each on or off, and one length for all of them, done the way
  clothes do bulk. Stubble is a tint flush with the face; short is opaque and still flush; longer lengths grow out
  from the face. A named style is a set of parts: a full beard has all four, an Amish beard all but the moustache
  (`lowpoly/renders/facial_hair.png`).
- **Held items are low-poly too** (owner, 2026-11): weapons, shields, tools, a potion being drunk. The world will be
  voxel blocks; the characters and what they hold are not. Items are made in the same editor, from simple shapes
  placed, turned and sized, as in a beginner's CAD tool (section 7.5).

**Where this stands:** `lowpoly/README.md`. In short: eight bodies (slim, average, heavy and short, for each sex) are
cut so that their polygons follow the region map of section 3.4, with the shares and pivots that make them bend;
ordinary garments from the wardrobe file go onto them and bend with them. The five heads of section 4 are rebuilt as rounded low-poly
forms that keep what section 4 says every head shares (size, eye box, ears). The faces of section 5 are rebuilt on
them: eye sets and their colourways, the ten lid states, lids, brows and the six skin tones. Section 7.4's special
shapes are rebuilt (straps, skirt, cape, hood), so all seven starter outfits dress all eight bodies, and facial hair is
rebuilt for the new face (four parts and one length). The voxel drawn shape has no low-poly form: the owner chose fixed
shape types with a few settings each in its place (2026-11): long beard, ponytail, bun, horns, pauldrons (section
7.4). All of that is made in Python first (`lowpoly/`), and the game builds it the same way in Godot (`core/lowpoly/`,
`runtime/lowpoly_rig.gd`), checked against the Python corner by corner. The move happened in five phases (owner's
go-ahead, 2026-11), all done: 1, bare bodies and heads in the game, bending; 2, ordinary clothing; 3, faces and facial
hair; 4, straps, skirts and capes; 5, the editor switched over and the voxel code removed (the last commit with it is
`fa40fa0`). The editor has three tabs (Face & Hair, Clothes, Preview); bodies and heads are made in Python, not edited
in the game. Not on the low-poly figure yet, though the wardrobe file keeps its setting: edge style.

**How to read the rest of this document.** Sections 1 to 13 are the original design, for voxel figures. They stay
the record of what was decided and still holds: the part hierarchy (3.1), the region map (3.4), faces (5), the
wardrobe file, items, bulk rules and special items (7), and accessibility (8). What they say about voxel geometry
(grids, cell counts, baked shading, the mesher, the voxel body, head and face files, the body editor, .vox and STL
export, cloth panels) describes the system removed in phase 5; each such passage is marked. Where this section and a
later one disagree, this section wins.

**Carried over, and already shown to work on the low-poly bodies:** the band table and its heights (the clay's unit
is the old voxel, so rows are heights), the 32 regions a side, the 11 parts and their hierarchy, and the wardrobe file
with its garment parameters (coverage, roles, bulk, mirror, draw order).

**Changed with the bending skin:** the 11 parts are no longer rigid pieces but what the skin's corners follow. The
hinge joints (neck, waist, elbow, knee) sit in their one-row trim bands: the band's two edge loops share the bend
75/25 and 25/75 and the pivot is at the middle of the band. The hip bends on the leg-opening loop. The shoulder is a
ball: the arm is a separate piece turning about the centre of its shoulder. Section 3.2's pivot table is the voxel
bodies'; the low-poly pivots are in each body file.

**Special shapes as polygons** (straps, skirt, cape; `lowpoly/specials.py`). Each takes the settings section 7.4
gives it, under the same names and with the same defaults (a check holds them equal to the game's table). What is
different from 7.4:

- **Hanging cloth is laid once, standing, then follows bones** (`lowpoly/hang.py`; owner's choice, 2026-11). A skirt
  or a cape is a few columns of cloth, each fixed at its top and of fixed length; standing, each column is a taut line
  from its top over whatever of the figure sticks out under it, then straight down, leaning out by the garment's
  flare. In a pose every point follows what its column's top follows and, further down, cloth bones the legs turn:
  a skirt's front follows the thigh furthest forward, its back the thigh furthest back, its sides their own thigh, each
  with a second bone at the knee that follows the shin reaching furthest that way; a cape swings back with the thigh
  furthest back. (Laid afresh for every pose by the
  taut-line rule, as first built, the cloth jumped between poses a hair apart, so it would pop in any animation:
  `docs/NOTES.md` 4zh.) Sitting, the cloth cuts the corner where the lap meets the belly by up to about 2 units.
- A skirt hangs from the waist line (the top of the hips band), over the hips. Its waistband is still the waist band
  covered as a garment would cover it.
- "Four panels" is one cloth all round; "two panels" is a front cloth and a back cloth with the sides open.
- An open front starts as a point at the hips and widens to the hem.
- Straps are flat bands on the chest. Over the shoulder they sit where 7.4 puts them (halfway between the neck and
  the edge of the chest's top row); from there they run straight to the front of the waist.
- A cape hangs from the shoulder line and drapes over the back; it does not react to the arms.

**Faces and facial hair as polygons** (`lowpoly/faces.py`, `lowpoly/facial_hair.py`). The options are section 5's,
and are read from the game each time: the eye sets and colourways in the wardrobe file, the ten lid
states with their five numbers for each eye, the lid colour from the skin tone, the brow and stubble colours from the
hair. What is different:

- **The eye is a rounded oval**, not a drawing in cells. It fills the box the eye set's drawing fills, and its
  pupil is an oval over the drawing's pupil cells. A lid cuts the oval straight across (on a slope, when it is
  tilted). The eye box is put on the head at 0.9 of its voxel size, its middle at height 33, the middle of the flat
  part of the face. A check holds the lids and the pupil, in every lid state, to where the game's cells have them
  (at the middle of every cell, apart from the columns where a tilted lid's edge runs through the middle of the
  cells). (The first port drew the cells themselves, with straight or square edges; the owner turned that down for
  ovals: `lowpoly/renders/faces_first_port.png`.)
- **The lash line** is the top edge of the open eye, drawn dark and thin from corner to corner, never outside the
  eye. It takes the eye set's "line" colour. When the lids meet, it is the line of the closed eye.
- **The eyebrow** is a shape of its own above the eye, in the brow colour the hair gives. It is moved by the same
  five numbers as the lids, so section 5's ten lid states still give ten faces without new data: it rises a little
  for a wide open eye, comes down a little for a lowered lid, and takes about half of the lid's tilt.
- **A small mouth**, which the voxel faces do not have, sits low on the flat part of the face (height 29.4): a
  short line, straight, with its corners turned up or turned down, or a small open oval, in the skin's colour
  darkened. Built as a first pass for the owner to judge. Which mouth goes with which lid state is for the game to
  say.
- White, pupil and lash line keep their own colour whatever the light (section 5); lid, eyebrow and mouth are lit
  as skin.
- **Facial hair is the head's own polygons**, cut along each part's edge and recoloured or lifted by the ordinary
  garment rules (`lowpoly/facial_hair.py`). The lengths: stubble (the game's stubble colour, flush), short (the hair's
  colour, flush), medium (half a step of bulk out) and long (a whole step out). With every part on, a gap of skin is
  left round the mouth. A moustache that is more than stubble hangs over the mouth. With hair on, sideburns run up
  into the hair; on a bald head they stop at the top of the ear.
- **Section 5.1 turned down** the goatee, the moustache and a beard with volume for the voxel face; all three are
  back, by the owner's design. The parts and the length are the game's own facial hair settings (wardrobe file and
  editor); its three items, once a style each, are now parts and a length (stubble: every part at stubble;
  chinstrap: all but the moustache, medium; full beard: every part, medium).
- Ears stay skin under hair.

**Three places where a region now follows the body instead of a level line** (calls made while cutting the bodies;
they are easy to change):

1. Hips / upper thigh: the boundary is the leg opening, level 11 at the outside of the hip and dropping to the crotch,
   so "hips" covers the whole pelvis.
2. Front / back: split along the side seam, within half a unit of the depth centre.
3. The arm's top and the foot's top stand a little past their bands' heights and belong to "shoulder" and "foot".

**Not decided yet** (the owner's to settle; `lowpoly/README.md` has the detail): how far each facial hair length
grows out; the mouth's shapes; hard pieces and
sleeves at the joints; the polygon budget; flat or smooth shading; how far one step of bulk stands off the body; what
becomes of edge style; and the final shape of the masculine clay.

---

## 1. Goal and scope

A character system for a 16-bit-JRPG-style game rendered as voxels, in the spirit of the Voxel Doom mod: chunky,
pixel-art-shaded voxel figures. Parts of it:

1. **Base bodies** — six bare, featureless bodies (masculine/feminine × slim/average/heavy), 11 rigid parts each.
2. **Heads** — a library of five unisex head shapes that fit any body.
3. **Faces** — eyes with a lid-and-brow system, as skin-tight overlays.
4. **Wardrobe** — hair and clothing as overlays, mostly *parametric* (body regions + colour + bulk), plus a limited
   set of *special* generated shapes (hoods, skirts/dresses/robes/togas, capes...). All unisex.
5. **Editor** — an in-engine tool for creating wardrobe items and faces (and later editing bodies).
6. **Runtime** — assembling a dressed character and animating it with rigid parts.

Out of scope for now: children (they will get their own model and clothing later), physics cloth, LOD, final
animation set. (Held items were out of scope; they are in now: section 7.5.)

**Engine: Godot 4.** Chosen because its scenes and resources are plain text and editor tools are easy to write, which
suits building with Claude Code. Use the current stable 4.x release. *Recommended:* GDScript (works directly in
editor plugins, no .NET toolchain); revisit only if meshing becomes too slow (then move the mesher to GDExtension).

---

## 2. Scale and coordinates

- **24 voxels per metre.** A world block is 1 m = **24 × 24 × 24** voxels.
- The figure is **42 voxels tall** (1.75 m), slightly under two blocks.
- **Reference box** per character: 24 wide × 24 deep × 48 tall (one block wide, two tall). It is a reference, not a
  clip: the heavy masculine body is exactly 24 wide, so arm bulk goes past it. *Recommended:* the editor's authoring
  canvas is wider, e.g. 32 × 32 × 48, with the body centred.
- **Voxel axes** (all asset files): x = width, y = depth, z = up. Feet stand on z = 0. The figure **faces −y**. The
  character's **left is +x**. The mirror line lies between x = 11 and x = 12; the depth centre between y = 11 and 12.
- A voxel (x, y, z) occupies [x, x+1) × [y, y+1) × [z, z+1). **Pivots are in this corner space**, so a pivot of
  (12, 12, 12) sits on a voxel boundary.
- **Godot mapping** (proper rotation, metres): `godot = ((12 − x) / 24, z / 24, (y − 12) / 24)`. This puts up on +Y,
  the character's right on +X and its face toward −Z (Godot's Node3D forward). If the project instead adopts the
  glTF/MODEL_FRONT convention (models face +Z), flip X and Z. **Decide in phase 1 and lock it with a test** (a camera on
  the −Z side must see the face; the character's left hand must be on the camera's right).

---

## 3. Base bodies

### 3.1 Parts and hierarchy (11 rigid parts)

```
pelvis (root)
├── chest
│   ├── head                 (from the head library)
│   ├── upper_arm_L ── forearm_L   (forearm includes the hand)
│   └── upper_arm_R ── forearm_R
├── thigh_L ── shin_L        (shin includes the foot)
└── thigh_R ── shin_R
```

- Rows: pelvis z11–14, chest z15–24, head z25–41 (neck at z25, head proper z26–41), upper arm z17–23,
  forearm+hand z9–16, thigh z6–10, shin+foot z0–5. Every row comes from one band table (§3.4): `lowpoly/body.py`
  (`BANDS`), written for the game to `assets/lowpoly/regions.json` (`lowpoly/check.py` holds the two equal). On the
  low-poly bodies the rows are heights, in the same unit.
- **Owner decision (layout B, 2026-11):** the head grew from 14 to 16 rows (and 2 wider and deeper) to give faces and
  expressions more room. The figure stays 42 tall; the two rows came from one belly row and one upper-thigh row, and
  the forearm lost a row so the arms keep their reach relative to the legs.
- **No joint caps.** Parts simply meet; gaps and overlaps at bent joints are accepted (the style is plainly cubes).
- Contacts: every part touches only its parent. Thighs never touch each other; arms touch only the chest at the
  shoulder. Every part is one connected piece; every body is one piece with no edge-only voxel contacts (so a
  straight voxel→STL export is manifold).
- The deltoid (top of the shoulder) belongs to **upper_arm**, flush against the chest, so it lifts with the arm.
- Hands are a 1-voxel-narrower "hint" with rounded fingertip corners; fused to the forearm. Feet fused to the shin.

### 3.2 Pivots

*Voxel figures (removed in phase 5). The low-poly bodies' pivots are in their files (`assets/lowpoly/`), made by
`lowpoly/body.py`.*

Each part rotates about its joint with its parent. Measured from the built geometry (so every body is correct):

| | pelvis | chest | head | upper_arm_L | forearm_L | thigh_L | shin_L |
|---|---|---|---|---|---|---|---|
| all bodies | (12,12,11) | (12,12,15) | (12,12,25) | see below | same x, z17 | see below | same x, z6 |

Upper-arm pivot (x, 12, 24) and thigh pivot (x, 12, 11), left side; right side mirrors as 24 − x:

| body | arm x | leg x |
|---|---|---|
| masculine slim | 19.5 | 15 |
| masculine average | 21 | 15 |
| masculine heavy | 22 | 16 |
| feminine slim | 18.5 | 15 |
| feminine average | 19.5 | 15 |
| feminine heavy | 21 | 15.5 |

**Parity rule:** an even-width part pivots on a voxel boundary, so 90° turns stay on the grid. Exceptions accepted:
3-wide arms (both slims, feminine average) and feminine heavy's 5-wide legs pivot on a voxel centre for *sideways*
rotation; forward/back swing is unaffected.

### 3.3 The six bodies

*Voxel figures (removed in phase 5); the eight low-poly bodies replace them (section 0).*

All six share **identical row boundaries** (so one region map serves all) and the same head socket. (The low-poly
short bodies keep the same bands at lower heights: section 0.) Widths (chest / waist / hips) and depths:

| body | chest/waist/hips | torso depth | arm w×d | thigh w×d | shin w×d | notes |
|---|---|---|---|---|---|---|
| masc. slim | 10/10/10 | 6 | 3×4 | 4×4 | 4×4 | |
| masc. average | 12/10/10 | 8 | 4×4 | 4×6 | 4×4 | |
| masc. heavy | 14/14/14 | 10 | 4×6 | 6×8 | 6×6 | all vertical edges rounded |
| fem. slim | 8/6/8 | 6 | 3×3 | 4×4 | 4×4 | bust 2×2, 1 proud |
| fem. average | 10/8/10 | 6 | 3×4 | 4×6 | 4×4 | bust 3×3 + 2×2 layer, 2 proud |
| fem. heavy | 12/10/12 | 8 | 4×4 | 5×6 | 5×6 | bust 4×3 + 2×2 layer; edges rounded |

- Masculine: square shoulders (full-width top row). Feminine: sloped shoulders (top row inset 1 per side), a waist
  narrower than chest and hips, and a bust that scales with the chest (each pair fills it minus 1 per side, 2-voxel
  gap; second layer on the lower two rows).
- **Heavy means more mass everywhere, not obesity.** No protruding belly or rear. This was tried and rejected twice;
  do not reintroduce it.
- The owner considers the bodies a good starting point and **expects to tweak them in the editor**.

### 3.4 Region map (shared by all bodies)

Regions are defined by **part family + row band**, split **left/right** at the mirror line, and torso and head bands
also split **front/back** at the depth centre. They never use absolute x, so they adapt to every body's widths.
**Trim bands** are deliberately one row thick: a cuff, belt, collar or hem is simply a trim band in another colour.

| family | regions (rows z) |
|---|---|
| head | neck 25 *(trim)*, lower_head 26–30, mid_head 31–36, crown 37–41 |
| chest | collar 24 *(trim)*, upper_chest 20–23, lower_chest 17–19, belly 15–16 |
| pelvis | waist 14 *(trim)*, hips 11–13 |
| upper_arm | shoulder 21–23, upper_arm 18–20, elbow 17 *(trim)* |
| forearm | forearm 13–16, wrist 12 *(trim)*, hand 9–11 |
| thigh | upper_thigh 9–10, lower_thigh 7–8, knee 6 *(trim)* |
| shin | shin 3–5, ankle 2 *(trim)*, foot 0–1 |

32 regions per side (the owner settled 32: the head and torso split front/back, including the neck and waist trims).
The game reads the band table from `assets/lowpoly/regions.json`.

---

## 4. Heads

*Voxel heads (removed in phase 5); the five low-poly heads keep the five shapes and what every head shares (section 0).*

Five unisex shapes: **round, boxy, oval, strong, heart** (14–16 wide, 14 deep, 16 tall + 4×4 neck). Every head shares:
the neck socket (4×4 at z25, x10–13, y10–13), pivot (12, 12, 25), height z26–41, depth (so one face plane), ear rows,
and the **eye box**. So hair, hats and faces fit every head. Heads are exported blank (no eyes). Note: head widths
differ, so pre-drawn hair/hats need slack or a per-head fit; parametric ones fit automatically.

Each head row is a rectangle, inset and then rounded at its corners by a stepped profile (per shape: top and bottom
insets, corner steps, and jaw/crown narrowing). The larger heads use the extra voxels for rounder corners and crowns
where it suits the shape: round and heart get a three-cell corner step (the oval a one-cell step, eased so the eyes
fit — §5); strong keeps its square jaw under a
rounded crown; boxy stays boxy.

## 5. Faces: eyes, lids and brows

Eyes with a lid-and-brow system; **no mouths**. (Owner, 2026-11: the original "no brows" became one brow line that
the lids drive; see below.) *The low-poly face (section 0) keeps the eye sets, colourways, lid states, lid and brow
colours and skin tones, draws the eye as an oval with a lash line and a brow of its own, and adds a mouth.*

- A face is a **skin-tight overlay** (bulk 0) on the face plane **y = 5**: it recolours head voxels, never adds volume.
- **The eyes are the same size on every head, always** (owner). Every head must give both eye boxes *and the brow
  row above them* a flat face with nothing in front; a test fails any head that cannot. (The oval's corner rounding
  was eased one step for this.)
- **Eye box:** 5 wide × 6 tall, all four corners rounded. Screen-left eye x6–10, screen-right eye x13–17, rows
  z29–34 (three skin rows under the eyes); the brow row is z35.
- **The open eye ("G7", locked in by the owner):** all white, with a black pupil 1 wide × 2 tall in the middle
  (column 2, rows 2–3) — two white rows above it and two below. This is the eye wide open; lids make every other look.
- **Lids and brow** (`core/eye_lids.gd`). Per eye: how many rows the upper lid covers, how many the lower lid covers,
  and a pupil shift. Rows the upper lid covers are **lid**; its lowest covered row is the **brow** line — the brow
  leads the lid down. With no upper lid the brow sits on the row above the eye (wide open, brows raised); in neutral
  it covers the eye's top row and no lid shows. Rows the lower lid covers are lid, **with no line**. When the lids
  meet the eye is closed: lid, with the brow line at the upper lid's edge. The brow is always the full eye width.
  The one line serves as both brow and lash line (owner accepted the compromise; it reads as the brow when wide open).
  **Tilt** slants the upper lid, and so the brow: +n puts its inner end (nearest the nose) n rows lower than its outer
  end, −n puts it n rows higher, in even steps across the eye (a tilt of 2 steps 0, 1, 1, 2, 2). Both eyes mirror.
- **Lid colour:** the skin tone half a shade darker (halfway from its mid to its dark). **Brow colour:** the hair
  colour one shade darker (its garment dark tone); bald characters get the brow of dark-brown hair unless a brow colour
  is set.
- **Named lid states:** neutral (upper 1), wide open (0), unimpressed (upper 2), downcast (upper 3, pupil down 1),
  tired (upper 3, lower 1, pupil down 1), suspicious (upper 2, lower 2), angry (upper 1, tilt +2), sad (upper 2,
  tilt −2, pupil down 1), blink (closed), wink (one eye closed). They
  live in code; they are chosen on the editor's Preview tab only. Blinking is a lid state swap.
- **Roles:** white, pupil (= eye colour; a colourway), line (paintable, optional), lid and brow (from the lid state).
- **No drawn expressions** (owner, 2026-11: retired completely). An eye set is the open eye, drawn **once per eye in box
  cells** (c from the eye's outer edge, r from its bottom row) in the Face & Hair tab, plus its colourways; every look
  is a lid state over it. Older wardrobe files load their "neutral" drawing as the eye. The game's standard eye is
  `EyeSet.STANDARD_CELLS` (`core/eye_set.gd`). No ^ ^ (happy arcs) for now (owner).
- Draw order: the face draws **under** hair and hats.

### 5.1 Facial hair (owner, 2026-11)

*For the low-poly figures, section 0 replaces this: facial hair is four parts (moustache, sideburns, goatee, cheeks),
each on or off, and one length (stubble, short, medium, long). Those are the generator's settings in the wardrobe file
now (`moustache`, `sideburns`, `goatee`, `cheeks`, `length`; a file saved with the old `style` is read as parts and a
length; `FacialHairSettings`). The voxel generator described below was removed in phase 5.*

At this resolution facial hair is coverage and depth, not detail. Kept: **stubble**, **chinstrap**, **full beard**;
rejected: goatee, moustache, moustache + goatee, a volumetric full beard, flat sideburns.

- One generator (`core/specials/facial_hair_generator.gd`, special type `facial_hair`, param `style`) that reads each
  head's own surface, so it fits all five heads and edited ones:
  - **stubble** recolours the skin over the jaw rows (z26–28), the jaw's sides, the underside of the chin, and a
    sideburn strip on the side of the head in front of each ear (z29–33). No volume.
  - **chinstrap** adds one voxel of hair along the bottom row of the face and jaw sides and up each side as a raised
    sideburn.
  - **full beard** = chinstrap + stubble.
- **Colours follow the character** through colour references: `@stubble` is always darker than the skin (the skin
  half a shade darker, leaning a third toward the hair, darkened further if the hair is lighter than the skin);
  `@hair` is the worn hair's colour (dark brown when bald). Any item role can use them.
- **Face accessory** slot (optional, one at a time): the **long beard**. *On the voxel figure a hand-drawn shape at
  the chin anchor; on the low-poly figure one of the shapes of their own (section 7.4: length, width, point, jut). It
  starts on the face just under the lower lip and hangs straight down over the chest.* Its colour is `@hair`.

## 6. Shading and colour

*The baked tones and the thin-cloth rule are voxel shading (removed in phase 5). The low-poly figure is lit flat or
smooth, which is still the owner's call (section 0); the skin tones, garment tones and the colour-blind rule hold.*

- **Baked tones** (Voxel Doom style), lit from the viewer's upper-left-front. Per voxel, from its six neighbours:
  **light** if the top is exposed, or both left (−x, viewer's left) and front (−y) are exposed; else **mid** if the
  front is exposed; else **dark** if bottom, right or back is exposed; else mid. Same rule on all six bodies.
- **Skin is a choice of tone** (owner): pale, light, tan, medium, brown, deep. "Light" is the original skin —
  light (255,214,172), mid (236,178,134), dark (190,128,92) — and every other tone derives its light and dark in the
  same proportions to its mid, so all tones shade alike. Eye black (20,20,26), line (70,38,24), eye white
  (250,250,248); lid and brow colours as in §5.
- **Thin cloth is shaded by the way it faces, not voxel by voxel** (owner). The rule above assumes solid shapes. A
  hanging panel is a sheet one voxel thick: its inside face looks at the legs, so the rule prints them onto the back of
  a skirt (dark where a leg touches the cloth, lighter where there is air behind it), and a one-voxel strap is all edge
  and comes out all light. So a strap, a skirt panel and a cape each take the tone a flat face of a solid would have:
  top light; front and viewer's-left mid; back, viewer's-right and bottom dark.
- Garment colours: from a palette colour c, light = c + (255 − c) × 0.28, mid = c, dark = c × 0.68.
- *Recommended* in Godot: unshaded material with vertex colours, so the baked look is exact. Optional extra legibility:
  multiply per face orientation (top 1.0, front 0.97, sides 0.9, back 0.84, bottom 0.74) — the prototypes used this.
- Colour choices in UI and palettes must not rely on red vs green (owner is colour blind).

---

## 7. Wardrobe

### 7.1 One file

Everything lives in **one wardrobe file** (JSON): palette, every item with its roles and colourways, saved
outfits, eye sets, **saved characters** (version 3) and **held items** (version 4, section 7.5). Bodies, heads and
faces are separate library files.

A **saved character** (`core/character_def.gd`) is who someone is: body, head, skin tone, eye set and its colourway,
brows, resting eyelids and mouth, hair, facial hair and face accessory (each with its colourway), the clothes worn,
and what it holds in each hand.
It names items, eye sets and colours by id; deleting an item takes it off every character, and anything else missing
falls back (a colourway to the item's first, an eye set to the first), so a character always builds. It makes the
request the assembler builds from, for the editor and the game alike.

### 7.2 Items

- **Category and draw order** (higher draws on top; defaults): hat 80, hair 70, back/cape 60, accessory 55, belt 50,
  other 45, hands 40, top 30, feet 20, bottom 10. Adjustable per item.
- **Colour roles** (named parts of a design: Cloth, Trim, Buckle...) and **colourways** (saved colour sets for the same
  design). Outfits record which items are worn and in which colourway.
- **Unisex by construction**: parametric items regenerate from each body's surface, so one item fits all six bodies.

### 7.3 Parametric garments (the main system)

A garment lists the **regions** it covers, each with a **colour role** and a **bulk**. The **left side** is defined
and a **mirror flag** says whether the right side mirrors it or has its own definition (sashes, one-shouldered tops).

Bulk rules:
1. Bulk is 0 or more. **0 only recolours** the body's own voxels (tights, gloves, skin-tight colour); N adds N voxels.
2. Growth is **sideways only, within the band's own rows**, so adjacent bands with different bulk make a hem step.
3. Surfaces facing up or down (shoulder tops, crown, foot tops) also grow vertically. **Nothing grows below z0.**
4. **Each body part grows independently**, so arm and torso bulk may overlap in the rest pose and still separate when
   the figure moves.
5. Grown voxels belong to the region and part they grew from.
6. **Layering:** when worn items claim the same cell, the one reaching farthest from the body wins; draw order breaks
   ties. Bulk is measured from the body, not from the layer underneath.
7. **Edge style** per garment: soft (rounded corners, cloth) or hard (squared, plate).
8. **Nothing worn on the legs or feet grows into the gap between them** (owner, 2026-11). The side of a leg that
   faces the other leg gets no added voxels; the leg's own inner face is recoloured instead. The legs stand two voxels
   apart, so each growing one voxel inward would fuse trousers or boots into one block. Applies to thigh and shin
   parts (the shin includes the foot), at any bulk and either edge style. **Skin-tight (bulk 0) is the norm for
   trousers**; bulk is for legwear meant to look thick.

Normal range 0–3; more is allowed.

### 7.4 Special items

Shapes the bulk system cannot express — and they are **common**: hoods, skirts, dresses, robes, togas, capes,
standing collars, pauldrons, hats, long hair. *Recommended:* each special type is a **generator with a few
parameters** (skirt: length *to knee/ankle*, flare, panels; hood: depth, up/down; cape: length, width), built from body
measurements so it still fits every body, using region names for lengths. A limited number of types.

Long garments that hang across the legs (skirts, robes, capes) use **cloth panels**: garment-owned rigid parts hung
from a pivot on a body part (front/back/side panels from the pelvis; cape panels from the chest), rotated by a simple
driver rule (front panel follows the more-forward thigh, back panel the more-backward one, side panels their own
thigh). Legs may clip at extreme poses; accepted. Panels measure the figure **as worn**, so they are placed after
everything else that is worn, whatever the draw order: a skirt then hangs clear of boots and of thick trousers.

**Skirts are always their own items; a dress is an outfit** (owner). A skirt item is the hips in cloth plus the skirt
shape, with its waistband on so no skin shows under a top that stops short. A *dress* is a bodice (a top that ends at
the waist) and a skirt in one colour — voxel for voxel the figure a one-piece dress would be — and the same holds for a
toga (one-shouldered top + wrap skirt) and a robe (long-sleeved top + open skirt). Each half also goes with anything
else. The skirt's settings: length (to knee / shin / ankle), flare, two or four panels, waistband, hem trim, and two
that make it asymmetric, both aimed at one **side** (the character's own left or right):

- **Hem slant** 0–6: the hem rises that many rows from the other side to this one, and the trim follows it. The high
  side always keeps at least two rows.
- **Opening**: *wrap* cuts the front on a line from this side's hip to the middle at the hem, so this leg shows;
  *front* opens it down the middle (two columns at the hips, four at the hem) as two flaps, each following its own leg
  forward and hanging when that leg goes back. A narrow slit was tried and dropped: at this size it reads as a stripe.

**Built so far (voxel):** skirt (above), cape, hood, shoulder straps, facial hair (§5.1), and a hand-drawn shape placed
at a body anchor. *On the low-poly figure: skirt, cape, straps and facial hair; skirts and capes are hanging cloth
laid standing and following cloth bones (section 0). The hood: raised, a loose shell over the head with the face
open, falling to a cowl on the shoulders; lowered, a collar with the empty hood lying on the back (settings raised,
looseness, opening, lined, and for its shape peak, brim, fullness at the back and cowl length; the top is round
unless peaked). The drawn shape is replaced by shapes of their own, each fixed at a place on the figure
with a few settings (owner, 2026-11): long beard (from under the lower lip, hanging straight: length, width, point, jut = how far its tip leans forward), ponytail (back of the
head: height, length, thickness, tie), bun (top, back or nape; size), horns (a pair from the brow: length, curve,
spread, thickness), pauldrons (a pair on the shoulders: size, drop). An old file's drawn shape under the chin becomes a
long beard, one at the nape a ponytail; any other is kept in the file and not drawn.* **Straps** run up the chest, across the top beside the neck and straight down the back, one voxel proud, in a
column halfway between the neck and the chest's edge, so they fit every body. Worn over a shirt they are suspenders.
**Overalls are an outfit, not a garment** (owner): trousers, a bib of zones, and suspenders, all in one colour —
the same idea as the dress.

Hand-placed voxel edits: allowed on special types; ordinary parametric garments stay purely parametric (hand edits
would stop them fitting other bodies). Decals (buttons, emblems) are deferred; thin trim bands cover most of it.

### 7.5 Held items (owner, 2026-11)

Weapons, shields, tools and potions: items a character holds, in the same wardrobe file (section `held_items`) with
roles and colourways like any item, made in the editor's Items tab. They are not worn and not dressed: an item is a
list of **parts**, each one simple shape placed, turned and sized in the item's own space (the figure's axes and
units), coloured by a role (`core/held_item_shape.gd`; `lowpoly/held.py` makes the same corners):

- **box**; **wedge** (a block whose top slopes to nothing at its front); **cylinder**, **cone** and **sphere**, with a
  number of sides (3 to 24: 4 makes a square post, 8 nearly round);
- **outline**: a flat shape drawn on a 16 by 16 grid and given thickness (blades, axe heads, shields);
- **spin**: half a side view drawn on the grid and spun round its middle (bottles, handles, pommels).

A part fills its size exactly: its width, depth and height are the box round it, whatever its number of sides. A part
may be **mirrored** (drawn again across the item's middle). Every part is a closed piece, faces outward; parts overlap
and nothing is cut away (no holes: a hole would be a gap between parts). Turns are degrees forward (about x), then
sideways (about y), then round (about z).

**Holding.** The item's **grip** is where the hand closes, with a turn for how the item sits in it; a two-handed item
also has a **second grip** (kept in the file if there; nothing uses it and the editor has no control for it yet).
Unturned, an item made standing up and facing the front is held as a sword is, in the right hand with the arm hanging:
its top points ahead, out of the thumb's side of the fist, its front faces outward and its left side down. So a sword
or an axe made standing up needs no turn; a bottle held upright is turned 90 degrees sideways. **The left hand holds
the mirror image.** The grip goes at the palm (the middle of the box round the hand) and the item rides the forearm,
as one rigid piece: there is no hand bone and the hand does not close round it (section 13). Held items are drawn
after the face, so changing what is held does not dress the figure again. A saved character keeps one item per hand;
the game's `GameCharacter.hold(item, hand)` and `release(hand)` change it for that character only.

---

## 8. Editor (in Godot)

Built **inside the game's Godot project** — an editor plugin or a tool scene — sharing the runtime's
assembler, now **LowpolyAssembler** (`core/lowpoly/`). The assembler (body + head + face + worn items → a dressed
figure) must exist **exactly once**; the editor and the game both call it. This is the main
reason for building the editor in-engine: two implementations of bulk generation would drift.

Features (roughly in priority order):
- **Preview:** any of 6 bodies × 5 heads × lid states; orbit/pan/zoom; front/back/side buttons; solo an item.
- **Held items** (Items tab, section 7.5) **are put together by hand in the view** (owner, 2026-11: editing by
  numbers alone is not workable; numbers are for fine work and exact places). One rule for every drag: it moves flat
  to the view being faced (from the front: across and up; from above: across and depth; from a side: depth and up;
  an angled view uses whichever of those it faces most, and two lines through the part say which, by letter).
  - Click a part to choose it; drag it to move it. Drag empty space to turn the view.
  - The chosen part has a square on four of its sides (w, d, h; not the two seen end on): pull one and that side
    moves, the opposite side stays. A ring turns it, about the way the view faces.
  - Buttons above the view add a part of each kind, on top of the item, chosen. A see-through hand at the grip gives
    the size of things.
  - On the Grip sub-tab the view edits the grip instead: the forearm and hand that will hold the item are shown; drag
    the hand to move the grip, the ring to turn it.
  - Everything snaps to a quarter unit and 15 degrees; nothing finer is offered by hand. What a drag is doing is
    written by the pointer. One drag is one undo step; Escape gives it up.
  - The usual keys: Ctrl+C copies the chosen part, Ctrl+V pastes it (into the same item, beside the first, or into
    another item), Ctrl+X cuts it, Delete removes it, Ctrl+Z undoes. The arrow keys move it a quarter unit a press,
    the way they point on the screen, for careful placing.
  - "Centre it on: x, y, z" above the view puts the chosen part on the item's middle along that axis (that place
    becomes 0).
  - **Kept small on purpose** (owner): an item is a handful of parts and is small in the game, so detail finer than
    this is not worth controls. One way to do each thing; no control that does nothing.
  - Handles are told apart by shape and letter, never by red against green: squares size, a ring turns, a diamond is
    a grip.
  - The panel keeps the list of parts and the numbers (shape, colour role, place, turn, size, sides, mirror), which
    follow the view, and a 16 by 16 grid to draw an outline or a side view on (click to add a point, drag to move
    one, right-click to remove one).
  - Show: the item alone (where it is edited), or held in a character's right or left hand, in any pose. The Preview
    tab chooses what each hand holds.
- **Saved characters** (Preview tab): save the whole character shown as a named character, pick one to see it,
  update it with changes, rename, delete; all undoable. The summary says whether what is shown is the character as
  saved.
- **Wardrobe panel:** items list (worn toggles, category, draw order), roles and colourways, outfits (wear, save,
  update), palette editing.
- **Garment editing:** pick regions on the figure or from a list; set role + bulk per region; mirror flag; edge style.
- **Special items:** choose a type, edit its parameters with live preview.
- **Face editor:** a grid of the eye box; edit one eye, the other mirrors. (Expressions were retired: lids make them.)
- **Body editing:** *built for the voxel bodies and removed with them in phase 5; the low-poly bodies are made in
  Python (`lowpoly/`).* The voxel design was: parts as layers, one owner per cell, mandatory mirror pairs, row-band guides, pivot
  markers, and a **pose preview** (arms raised, mid-stride, sitting) — the real test of part splits and pivots.
- **Files:** native dialogs, Open / Save / Save As, Ctrl+S to the current file, unsaved-changes prompt, reopen last
  file. (The owner strongly dislikes browser-style file handling; this was the reason an HTML editor was rejected.)
- **Export:** .vox (MagicaVoxel), STL for 3D printing (with the edge-contact fix so it is manifold), OBJ if useful.
  *(Voxel; not built. The low-poly bodies and heads have OBJ copies in `lowpoly/bodies/` and `lowpoly/heads/`.)*
- **Undo/redo** for every edit.

**Accessibility:** never encode meaning in red vs green alone; use labels, shapes or a colour-blind-safe palette
(e.g. Okabe-Ito). Prefer clear labels and short hints over dense text; readable type sizes.

## 9. Runtime

*The game now draws one skinned mesh that bends at its joints, plus its hanging cloth as a second skinned mesh on the
same skeleton, which has nine cloth bones besides the eleven parts (`runtime/lowpoly_rig.gd`; section 0). The voxel runtime below was removed in phase 5.*

**Animation** (`runtime/animations.gd`): clips of a few key poses, evenly spaced over a length, looping or not; every
angle moves on a smooth curve through the keys (uniform Catmull-Rom). A clip is a walk on the spot: the game moves the
node. `RigAnimator` plays one on a rig, blending in from the pose the figure had, and turns only bones each frame
(cloth follows its bones). Clips so far, as first passes: idle (breathing) and walk (one second, two steps).
`lowpoly/pose.py` samples clips the same way; `tests/lowpoly_expected.json` holds samples the game is checked
against, and `lowpoly/check.py` holds the cloth to 0.15 units in eight frames of the walk on every body and outfit.

**`GameCharacter`** (`runtime/game_character.gd`) is the node the game uses: it builds a saved character by its id
from a wardrobe, through the same assembler as the editor, and shows it with a LowpolyRig. It changes the expression
(eyelids, mouth) without dressing the figure again, a pose, an animation (`play`), the clothes worn, or what it holds
(`hold`, `release`; for that node only: the wardrobe is not changed). The library of bodies and heads, and a wardrobe read from a file, are read once and shared.
`runtime/character_demo.tscn` stands the saved characters in a row, walking on the spot.

- Each part is a mesh under a Node3D at its pivot, parented per §3.1; animation rotates the pivots (AnimationPlayer).
  No skinning.
- Mesher: exposed-face culling into an ArrayMesh with vertex colours is enough at these sizes (a body is ~4–6k voxels).
  Greedy meshing later if needed.
- *Optional later:* re-voxelise rotated parts each frame to keep everything snapped to the world grid (the Voxel Doom
  look). A rendering choice; it does not change the data.
- Collision: a simple capsule/box (~0.6 × 1.75 m), independent of pose; arms and hair may poke through walls.

## 10. Assets in this package

*As first delivered (voxel). Now: `assets/lowpoly/` holds the eight bodies, the five heads and the region table, made
by `lowpoly/` (see `assets/README.md`); the voxel files and `tools/build_bodies.py` were removed in phase 5.*

```
CLAUDE.md, SPEC.md
assets/      body42_{sex}_{build}_parts.json, .vox   (sex: male, female; build: slim, average, heavy)
             head42_{shape}.json, .vox               (round, boxy, oval, strong, heart)
             face42_open.json                        (the open eye; lids and brow are drawn over it)
             README.md                               (file formats in brief)
tools/       build_bodies.py                         (regenerates everything in assets/)
docs/        sheet_*.png                             (review renders)
reference/   earlier editor prototypes (HTML, PySide) and a CLI exporter
```

- `tools/build_bodies.py` was the source of truth for the voxel bodies, heads and faces (Python 3 + numpy), run from
  inside `assets/`. Removed with them; `lowpoly/` makes the assets now.
- Body files: per part, parent, pivot, voxel list `[x, y, z]`; head voxels are empty (supplied by the head library);
  the region table is included. The `.vox` files are previews with the round head and baked shading.
- Head files: head voxels, neck socket, pivot, eye box. Face files: eye box spec, per-eye cells, absolute voxels.
- `reference/` prototypes implement an older hand-painted wardrobe model (explicit voxels per item). Use them for
  feature ideas only; do not port their file format.

## 11. Suggested build order

*The original order, for the voxel system; done, then superseded by the move to low-poly (section 0).*

1. Godot project, coordinate mapping test, load body/head/face JSON, mesher, preview with orbit camera.
2. Rigid-part hierarchy and pose preview (a few test poses).
3. Wardrobe data model + one-file save/load + parametric garment generation (bulk rules) + layering.
4. Editor panels for items, roles, colourways, outfits; garment region editing.
5. Special item generators (start with hood and skirt) and cloth panels.
6. Face editor.
7. Export (.vox, STL, OBJ).
8. Body editor.

## 12. Acceptance checks (automate where possible)

*The voxel acceptance checks, retired with the voxel system in phase 5. The checks now are `tests/` (Godot: the
coordinate lock, the wardrobe, the model, the low-poly figure against the Python, the editor) and `lowpoly/check.py`.
The two that still apply as written: the coordinate test from §2, and the wardrobe round-trip.*

- Coordinate test from §2 passes.
- Loading each body reproduces its voxel counts (masc. slim 4754, average 5310, heavy 6630; fem. slim 4480,
  average 4832, heavy 5530 — counts include the round head; bodies files exclude it). Before layout B they were
  3894, 4494, 5926; 3590, 3976, 4714.
- Every body: mirror-symmetric, one connected piece, every part one piece, no edge-only contacts, parts touch only
  their parents.
- The eyes fit every head (no eye cell falls off the face plane); every head gives the whole eye box and
  brow row a flat face; every lid state lands on every head.
- A parametric garment generates without gaps on all six bodies; bulk-0 adds no voxels.
- Wardrobe file round-trips unchanged (save → load → save is identical).
- STL export of a dressed figure is watertight.

## 13. Open questions (for the owner, when relevant)

- Hands as separate parts with pre-drawn grip poses: held items exist now (section 7.5), held at the palm of an open
  hand.
- Whether cloth panels stay rule-driven or get simple physics.
- Re-voxelised animation look vs plain rotated parts.
- Decals (buttons, emblems) — currently deferred.
- Exact animation set and how faces change during animation (blink timing, talking).
- Authoring canvas size (32 recommended) and whether the 24-wide reference box matters for gameplay.
