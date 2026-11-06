# Voxel Character System — Spec

Status: figure definition settled; software not started. This document is the hand-off from the design session to the
build session. Where it says *recommended* it is a recommendation, not a decision; everything else was decided.

Owner preferences that apply to every decision: the owner assesses risk and tradeoffs personally, wants accurate
feasibility reads and visible uncertainty, and prefers to be asked when a choice is genuinely theirs. The owner is
red/green colour blind, dyslexic and has ADHD — see *Accessibility* under the editor.

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

Out of scope for now: children (they will get their own model and clothing later), held items/props, physics cloth,
LOD, final animation set.

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
  forearm+hand z9–16, thigh z6–10, shin+foot z0–5. Every row comes from one band table (§3.4): in
  `tools/build_bodies.py` (`BANDS`) and, for the Godot side, `core/body_layout.gd`, checked against each other by a
  test.
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

All six share **identical row boundaries** (so one region map serves all) and the same head socket. Widths
(chest / waist / hips) and depths:

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
The band table also lives in every body file under `"regions"`.

---

## 4. Heads

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
the lids drive; see below.)

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
- **Roles:** white, pupil (= eye colour; a colourway), line (in drawn expressions), lid and brow (from the lid state).
- **Drawn expressions** remain: each is defined **once per eye in box cells** (c from the eye's outer edge, r from its
  bottom row), drawn in the Face & Hair tab, and lids apply on top. The 11 starters (neutral, blink, happy, angry, sad,
  surprised, bored, wink, look_left, look_right, look_down) were only roughly adapted to the 5×6 box; most are now
  better made with lids (angry and sad now are), and what to keep is still open.
- Draw order: the face draws **under** hair and hats.

## 6. Shading and colour

- **Baked tones** (Voxel Doom style), lit from the viewer's upper-left-front. Per voxel, from its six neighbours:
  **light** if the top is exposed, or both left (−x, viewer's left) and front (−y) are exposed; else **mid** if the
  front is exposed; else **dark** if bottom, right or back is exposed; else mid. Same rule on all six bodies.
- **Skin is a choice of tone** (owner): pale, light, tan, medium, brown, deep. "Light" is the original skin —
  light (255,214,172), mid (236,178,134), dark (190,128,92) — and every other tone derives its light and dark in the
  same proportions to its mid, so all tones shade alike. Eye black (20,20,26), line (70,38,24), eye white
  (250,250,248); lid and brow colours as in §5.
- Garment colours: from a palette colour c, light = c + (255 − c) × 0.28, mid = c, dark = c × 0.68.
- *Recommended* in Godot: unshaded material with vertex colours, so the baked look is exact. Optional extra legibility:
  multiply per face orientation (top 1.0, front 0.97, sides 0.9, back 0.84, bottom 0.74) — the prototypes used this.
- Colour choices in UI and palettes must not rely on red vs green (owner is colour blind).

---

## 7. Wardrobe

### 7.1 One file

Everything lives in **one wardrobe file** (JSON): palette, every item with its roles and colourways, and saved
outfits. Bodies, heads and faces are separate library files.

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

Normal range 0–3; more is allowed.

### 7.4 Special items

Shapes the bulk system cannot express — and they are **common**: hoods, skirts, dresses, robes, togas, capes,
standing collars, pauldrons, hats, long hair. *Recommended:* each special type is a **generator with a few
parameters** (skirt: length *to knee/ankle*, flare, panels; hood: depth, up/down; cape: length, width), built from body
measurements so it still fits every body, using region names for lengths. A limited number of types.

Long garments that hang across the legs (skirts, robes, capes) use **cloth panels**: garment-owned rigid parts hung
from a pivot on a body part (front/back/side panels from the pelvis; cape panels from the chest), rotated by a simple
driver rule (front panel follows the more-forward thigh, back panel the more-backward one, side panels their own
thigh). Legs may clip at extreme poses; accepted.

Hand-placed voxel edits: allowed on special types; ordinary parametric garments stay purely parametric (hand edits
would stop them fitting other bodies). Decals (buttons, emblems) are deferred; thin trim bands cover most of it.

---

## 8. Editor (in Godot)

Built **inside the game's Godot project** — an editor plugin or a tool scene — sharing the runtime's
**CharacterAssembler** module. The assembler (body + head + face + worn items → per-part voxels and meshes, with
bulk generation and shading) must exist **exactly once**; the editor and the game both call it. This is the main
reason for building the editor in-engine: two implementations of bulk generation would drift.

Features (roughly in priority order):
- **Preview:** any of 6 bodies × 5 heads × expressions; orbit/pan/zoom; front/back/side buttons; solo an item.
- **Wardrobe panel:** items list (worn toggles, category, draw order), roles and colourways, outfits (wear, save,
  update), palette editing.
- **Garment editing:** pick regions on the figure or from a list; set role + bulk per region; mirror flag; edge style.
- **Special items:** choose a type, edit its parameters with live preview.
- **Face editor:** a grid of the eye box; edit one eye, the other mirrors; add/rename expressions.
- **Body editing (later):** parts as layers, one owner per cell, mandatory mirror pairs, row-band guides, pivot
  markers, and a **pose preview** (arms raised, mid-stride, sitting) — the real test of part splits and pivots.
- **Files:** native dialogs, Open / Save / Save As, Ctrl+S to the current file, unsaved-changes prompt, reopen last
  file. (The owner strongly dislikes browser-style file handling; this was the reason an HTML editor was rejected.)
- **Export:** .vox (MagicaVoxel), STL for 3D printing (with the edge-contact fix so it is manifold), OBJ if useful.
- **Undo/redo** for every edit.

**Accessibility:** never encode meaning in red vs green alone; use labels, shapes or a colour-blind-safe palette
(e.g. Okabe-Ito). Prefer clear labels and short hints over dense text; readable type sizes.

## 9. Runtime

- Each part is a mesh under a Node3D at its pivot, parented per §3.1; animation rotates the pivots (AnimationPlayer).
  No skinning.
- Mesher: exposed-face culling into an ArrayMesh with vertex colours is enough at these sizes (a body is ~4–6k voxels).
  Greedy meshing later if needed.
- *Optional later:* re-voxelise rotated parts each frame to keep everything snapped to the world grid (the Voxel Doom
  look). A rendering choice; it does not change the data.
- Collision: a simple capsule/box (~0.6 × 1.75 m), independent of pose; arms and hair may poke through walls.

## 10. Assets in this package

```
CLAUDE.md, SPEC.md
assets/      body42_{sex}_{build}_parts.json, .vox   (sex: male, female; build: slim, average, heavy)
             head42_{shape}.json, .vox               (round, boxy, oval, strong, heart)
             face42_{expression}.json
             README.md                               (file formats in brief)
tools/       build_bodies.py                         (regenerates everything in assets/)
docs/        sheet_*.png                             (review renders)
reference/   earlier editor prototypes (HTML, PySide) and a CLI exporter
```

- `tools/build_bodies.py` is the current source of truth for bodies, heads and faces (Python 3 + numpy). Run it from
  inside `assets/` (`cd assets && python3 ../tools/build_bodies.py`); it rewrites every asset there.
- Body files: per part, parent, pivot, voxel list `[x, y, z]`; head voxels are empty (supplied by the head library);
  the region table is included. The `.vox` files are previews with the round head and baked shading.
- Head files: head voxels, neck socket, pivot, eye box. Face files: eye box spec, per-eye cells, absolute voxels.
- `reference/` prototypes implement an older hand-painted wardrobe model (explicit voxels per item). Use them for
  feature ideas only; do not port their file format.

## 11. Suggested build order

1. Godot project, coordinate mapping test, load body/head/face JSON, mesher, preview with orbit camera.
2. Rigid-part hierarchy and pose preview (a few test poses).
3. Wardrobe data model + one-file save/load + parametric garment generation (bulk rules) + layering.
4. Editor panels for items, roles, colourways, outfits; garment region editing.
5. Special item generators (start with hood and skirt) and cloth panels.
6. Face editor.
7. Export (.vox, STL, OBJ).
8. Body editor.

## 12. Acceptance checks (automate where possible)

- Coordinate test from §2 passes.
- Loading each body reproduces its voxel counts (masc. slim 4754, average 5310, heavy 6630; fem. slim 4480,
  average 4832, heavy 5530 — counts include the round head; bodies files exclude it). Before layout B they were
  3894, 4494, 5926; 3590, 3976, 4714.
- Every body: mirror-symmetric, one connected piece, every part one piece, no edge-only contacts, parts touch only
  their parents.
- Every expression fits every head (no eye cell falls off the face plane); every head gives the whole eye box and
  brow row a flat face; every lid state lands on every head.
- A parametric garment generates without gaps on all six bodies; bulk-0 adds no voxels.
- Wardrobe file round-trips unchanged (save → load → save is identical).
- STL export of a dressed figure is watertight.

## 13. Open questions (for the owner, when relevant)

- Hands as separate parts with pre-drawn grip poses, once held items exist.
- Whether cloth panels stay rule-driven or get simple physics.
- Re-voxelised animation look vs plain rotated parts.
- Decals (buttons, emblems) — currently deferred.
- Exact animation set and how faces change during animation (blink timing, talking).
- Authoring canvas size (32 recommended) and whether the 24-wide reference box matters for gameplay.
