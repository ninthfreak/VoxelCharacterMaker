# Figure 42 — voxel base bodies

Scale: 24 voxels per meter. Figure is 42 voxels tall (1.75 m), inside a 24 x 24 x 48 reference grid (1 block wide, 2 tall).

Axes: x = width (character's left is +x; mirror line between x11 and x12), y = depth (front faces -y, depth
centre between y11 and y12), z = up (feet on z0). Voxel (x, y, z) spans [x, x+1) etc.; pivots are given in that
corner space, so an even-width part pivots on a boundary and a 90-degree turn stays on the grid.

## Files

- `build_bodies.py` — generates everything below. `build(sex, build, head)` returns (part, material) arrays.
- `body42_{sex}_{build}.vox` — MagicaVoxel, baked light/mid/dark shading. sex in male, female; build in slim, average, heavy.
- `body42_{sex}_{build}_parts.json` — per part: parent, pivot, voxel list; plus the region-band table.
- `head42_{shape}.vox` / `.json` — unisex heads: round, boxy, oval, strong, heart (14-16 wide, 14 deep, 16 tall). Every
  head shares the neck socket (4x4 at z25), pivot (12, 12, 25), height (z26-41), depth, eye box and ear rows, so hair,
  hats and faces fit all.
- `face42_{name}.json` — eyes only, as skin-tight overlays (bulk 0) on the face plane y5; heads and bodies are exported blank.
  Eye box: 4 wide x 5 tall, top corners rounded; screen-left eye x7-10, screen-right eye x13-16, rows z29-33; fits all heads.
  Each expression is stored per eye in box cells (c from the eye's outer edge, r from its bottom row) plus absolute voxels.
  Roles: white, pupil (eye colour), line (lids), skin. Expressions: neutral, blink, happy, angry, sad, surprised, bored,
  wink, look_left, look_right, look_down. Blink and expression changes are overlay swaps.
- `sheet_*.png` — review renders.

## Parts (11, rigid)

pelvis (root, z11-14) -> chest (z15-24) -> head (z25-41); chest -> upper_arm (z17-23) -> forearm+hand (z9-16);
pelvis -> thigh (z6-10) -> shin+foot (z0-5). No joint caps; parts simply meet. Thighs never touch each other;
arms touch only the chest at the shoulder (exception: female heavy's forearm rests against the hip).

## Row bands (identical on all six bodies)

head: neck 25 (trim), lower 26-30, mid 31-36, crown 37-41.  chest/pelvis: collar 24 (trim), upper chest 20-23,
lower chest 17-19, belly 15-16, waist 14 (trim), hips 11-13.  arm: shoulder 21-23, upper arm 18-20, elbow 17 (trim),
forearm 13-16, wrist 12 (trim), hand 9-11.  leg: upper thigh 9-10, lower thigh 7-8, knee 6 (trim), shin 3-5,
ankle 2 (trim), foot 0-1.  Torso bands split front/back at the depth centre; everything splits left/right at x12.

## Builds

Widths (chest / belly / hips), arms, legs:
male slim 10/10/10, arm 3x4, leg 4x4 · male average 12/10/10, arm 4x4, leg 4x6 · male heavy 14/14/14 (depth 10), arm 4x6, leg 6x8 / shin 6x6
female slim 8/6/8, arm 3x3, leg 4x4 · female average 10/8/10, arm 3x4, leg 4x6 · female heavy 12/10/12 (depth 8), arm 4x4, leg 5x6 / shin 5x6
Female: sloped shoulders (chest top row inset 1). Bust scales with the chest (each pair fills it minus 1 per side, 2-voxel
gap): slim 2x2, 1 proud; average 3x3 plus a 2x2 layer on the lower rows, 2 proud; heavy 4x3 plus the same layer, 2 proud.
Heavy: more mass everywhere, no bulges. Same construction as the other builds, thicker in every direction, with every
vertical edge of torso and legs rounded. All six bodies use the same baked shading rule. Pivots are measured from geometry.
Odd widths (3-wide arms, female heavy's 5-wide legs) put the sideways pivot on a voxel centre; forward/back swing is unaffected.
