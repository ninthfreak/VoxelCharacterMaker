# Low-poly characters

The characters are low-poly (owner's decision, `SPEC.md` section 0). This folder holds what exists of them so far:
the bodies and heads, and the Python that makes, dresses, poses and checks them. The Godot side is moving over in
five phases (owner's go-ahead, 2026-11; `docs/NOTES.md` 4t to 4y), all done: the game reads the bodies, heads and
region table from `assets/lowpoly/`, dresses them in clothing and hair made of regions, straps, skirts and capes,
grows facial hair on them and draws their faces (`core/lowpoly/`), and draws them bending, with their hanging cloth
following cloth bones (`runtime/lowpoly_rig.gd`). The editor's four tabs (Face & Hair, Clothes, Items, Preview)
show them, and a click on the figure picks a region; the Items tab makes held items (`held.py`). The voxel system was removed in phase 5.

Godot ignores this folder (`.gdignore`), so nothing here is imported into the project.

## Decided so far

- **Style:** low-poly, at about the level of detail of Final Fantasy VII.
- **Bodies are cut from smooth clay models** on the clothing regions (method below).
- **The other builds work off the average** (owner, 2026-11: they must be compatible enough with the average body
  that every clothing rule still works). Slim, heavy and short are made from each sex's average clay and cut the same
  way, so each is the average body with its corners moved.
- **Slim is clearly slimmer** (owner): about 0.78 of the average's widths. The first pass's 0.86 was hard to tell
  from the average once dressed.
- **Joints: the body is one skin that bends.** Rigid pieces were built, compared and rejected for the body
  (`renders/joints_rigid_or_bend.png`). Clothing may need to be different from the body at the joints; see "How
  clothing moves" below for what is built, and "Not decided yet" for what is the owner's to judge.
- **Heads are rounded forms**, like the bodies (the first rebuild, blocks with bevelled edges, was too blocky).
- **The face: each eye lies on its own flat patch**, the two patches turned 15 degrees outward ("B" on
  `renders/heads.png`). This replaces the voxel spec's one face plane.
- **The eyes are rounded ovals**, not drawings in cells, at 0.9 of the voxel eye's size (4.5 wide, 5.4 tall), with
  their middle at the middle of the flat part of the face.
- **Lashes and eyebrows are two things.** The voxel face has one thick bar on the eyelid that is both and overhangs
  the eye. Here a thin lash line runs along the top edge of the open eye and never leaves it, and each eye has an
  eyebrow of its own above it.
- **The face has a small mouth**, low on the flat part of the face, so that there is room for a moustache above it
  and a beard under and round it. Its shapes are a first pass (`renders/faces.png`).
- **Facial hair is four parts and one length** (owner's design): moustache, sideburns, goatee and cheeks, each on
  or off, and one length for all of them, done the way clothes do bulk: stubble is a tint flush with the face (like
  skin-tight clothing), short is opaque and still flush, and longer lengths grow out from the face
  (`renders/facial_hair.png`). A named style is just a set of parts: a full beard has all four, an Amish beard all
  but the moustache.

## Where it stands

| Area | State |
|---|---|
| Clay bodies (the smooth forms the bodies are cut from) | feminine average (approved), masculine average (first pass, "decent"); slim, heavy and short of each sex, made from the averages: a first pass for the owner to judge (`renders/bodies_builds_clay.png`) |
| Bodies cut on the clothing regions | all eight: slim, average, heavy and short, each sex (`renders/bodies_builds.png`). 344 polygons (710 triangles) each without a head, and the same corners and polygons on all eight: each is the feminine average with its corners moved |
| Region map on the bodies (32 a side, the same bands as the voxel bodies) | done, checked. At the voxel bodies' heights on every body but the short ones, which have the same bands lower |
| Joints: one bending skin over the same 11 parts | done: every corner's shares and every pivot are in the body files; posed in Python |
| Ordinary garments from the wardrobe file (regions, roles, bulk, mirror, layering) | built in Python, on all eight bodies; they bend with the body |
| Special shapes: straps, skirt, cape | built, with every setting the voxel ones have; all seven starter outfits dress all eight bodies, in every test pose (`renders/special_shapes.png`, `renders/special_shapes_moving.png`, `renders/bodies_builds.png`) |
| Facial hair: four parts, each on or off, and one length (stubble, short, medium, long) | built, on every head; colours follow the hair and the skin as in the game (`renders/facial_hair.png`). The parts and the length are the game's own settings now (wardrobe file and editor); its three facial hair items were converted to them |
| Special shapes: hood, drawn (anchored) shapes | not started. The cloak is worn without its hood; the long beard and the ponytail's tail are drawn shapes |
| Hair | not rebuilt. The wardrobe's short crop goes on by the ordinary region rules, which is enough to show brows and beards following it |
| Edge style (soft / hard) | not carried over. The boots ask for "hard" and are built soft |
| Heads | all five (round, boxy, oval, strong, heart) as rounded forms: 114 polygons each, same layout; any head goes on any body (`renders/heads.png`) |
| Faces: eyes, lids, lashes, eyebrows, skin tones | built: oval eyes from the wardrobe's eye sets and their colourways, the game's ten lid states, lids from the skin tone, a thin lash line, eyebrows from the hair, all six skin tones (`renders/faces.png`) |
| The mouth | a first pass: a short line, straight or curved, or a small open oval (four: neutral, smile, frown, open). New here; the voxel faces have none. The game's table of them is `core/mouths.gd`, next to the lid states; which mouth goes with which lid state is open |
| Held items: parts placed, turned and sized; held at the palm, riding the forearm | built in Python (`held.py`) and in the game (`core/held_item_shape.gd`), checked corner for corner; the editor's Items tab makes them |
| Building polygons in Godot (assembler, editor, runtime) | done (all five phases): bodies and heads bending on a skeleton; clothing and hair made of regions (`LowpolyAssembler`); faces and facial hair (`LowpolyFace`, `LowpolyFacialHair`); straps, skirts and capes (`LowpolyShapes`), skirts and capes laid standing and following cloth bones (`LowpolyCloth`, `LowpolyPose`); all of it in full precision; the editor's tabs, flat or smooth shading, picking regions on polygons, a mouth picker. Godot's posed corners, dressed polygons, faces and laid cloth are checked against the Python's. The voxel code is gone |

## How a body is made

0. **Builds** (`clay.py`). Slim, heavy and short are made from each sex's average clay (`derive`, `squash`), so a
   change to an average carries over. Slim and heavy keep every height and change widths and girths
   (`BUILD_FACTORS`); heavy is more mass everywhere and its belly never comes forward of the chest. Short is made
   broader, then shorter: each band of height keeps a share of its height (`SHORT_KEEPS`), most lost from the shins
   and the lower thighs, less from the torso, none from the feet or the upper thighs, and the same head sits on the
   shorter neck: 36 tall instead of 42. The upper thigh keeps its height because it holds the leg opening: the broad
   pelvis keeps most of its depth, so the crotch sits as far below the hips as on the average.
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
5. **Every build the same way** (`body.py`). All eight bodies are cut from their own clays by the same cutter, at the
   same rings and columns. So they have the same corners in the same order and the same polygons, regions, parts and
   joint shares: each is the feminine average with its corners moved, and every clothing rule works on each as it
   does on the average (`check.py` holds this, and dresses all eight in every outfit and pose). The game could even
   blend from one build to another. A short body has the same bands at its own heights: every height the cutter
   uses is the average's, moved to the short body's bands (`clay.Heights`); the body carries its band table
   (`body["bands"]`, `heights` in its file); the head from the head library is set on its neck (`head_raise` in the
   file, 6 units down), and the face and facial hair go with the head. The joints, the straps, the skirt and the cape
   read their heights from the body.

Three places where a region follows the body instead of a level line:

- **Hips / upper thigh:** the boundary is the leg opening, level 11 at the outside of the hip (a short body: its own
  height there) and dropping to the crotch. A level line would leave the crotch outside "hips", because this pelvis hangs lower between the legs than
  the voxel one, which simply ended at row 11.
- **Front / back:** split along the side seam (the widest point of each ring; where the shoulder is cut off flat, the
  middle of the flat), within half a unit of the ring's centre depth. `check.py` holds this.
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

**The face** is the one part that cannot simply be made round: the eyes are big, the same on every head (the
owner's rule), and have to lie flat. So the front of every head has a flat part, 8 units tall (heights 29 to 37): two
flat patches, one for each eye with its eyebrow, turned 15 degrees outward and meeting down the middle of the face,
which makes the front of the head round as well. The angle is `FACE_BEND` in `heads.py`. (The owner chose this over
one flat face for both eyes; both are on `renders/heads.png`.) Everything on the face has to fit on that flat part:
above it the crown slopes back, and under it the jaw slopes away.

## How a face is made

What is shown is the voxel faces' own, and comes from the game each time (`game.py`), not from a copy here:

- **An eye set** is the open eye, drawn once for each eye in the eye box's cells, in the wardrobe file. What is
  taken from the drawing is how much of the box it fills and where its pupil sits.
- **Eye colour** is a colourway of the eye set.
- **A lid state** is five numbers for each eye: how far the upper lid has come down, how far the lower lid has come
  up, where the pupil looks (across and up or down), and the tilt of the upper lid. The ten named states (neutral,
  wide open, unimpressed, downcast, tired, suspicious, angry, sad, blink, wink) are the game's.
- **Lid colour** comes from the skin tone and **brow colour** from the hair (dark brown on a bald head). Both are the
  game's own numbers.

How it is drawn is the low-poly figure's own (`faces.py`):

- **The eye is a rounded oval** that fills the box the drawing fills, with an oval pupil over the drawing's pupil
  cells. A lid cuts the oval straight across, on a slope when it is tilted. A check holds the lids and the pupil, in
  every lid state, to where the game's cells have them (at the middle of each cell, leaving out the columns where a
  tilted lid's edge runs through the middle of the cells).
- **Its size and place.** The eye box goes on the head at 0.9 of the voxel one (`EYE_SIZE`): 4.5 wide and 5.4 tall,
  where the voxel eye is 5 by 6. Its middle is at the middle of the flat part of the face (`EYE_MIDDLE`, height 33),
  which is 1 unit higher than the voxel eye's middle.
- **The lash line** is the top edge of the open eye, drawn dark from corner to corner: along the upper lid's edge
  where the lid has come down, along the eye's own outline where it has not. It is thin (about a third of a row),
  a little thicker toward the outer corner, and never outside the eye. Its colour is the eye set's "line" colour.
  When the lids meet it is the line of the closed eye.
- **The eyebrow** is a shape of its own above the eye: thicker toward the nose, with a low arch. It takes the hair's
  brow colour. It moves with the same five numbers as the lids, so the ten lid states still give ten faces: it
  rises a little for a wide open eye, comes down a little once the lid is half way down, and takes about half of
  the lid's tilt, hanging from its higher end. Where a tilted brow lies over the eyelid, it is cut out of it.
- **The mouth** sits low on the flat part of the face (`MOUTH_Z`, height 29.4): a short line, straight (neutral),
  with its corners turned up (smile) or down (frown), or a small open oval. Its colour is the skin's, darkened. It
  lies across the middle of the face, so it is cut in two where the patches meet. Which mouth goes with which eyes
  is for the game to say. Between a straight mouth and the bottoms of the eyes there is 0.75 of a unit, and far more
  between the eyes: room for a moustache. Under it is the jaw: room for a beard.

The white, the pupil and the lash line are drawn in their own colour, untouched by the light, as on the voxel face.
The lid, the eyebrow and the mouth are lit like the skin. The polygons of a face tile it without overlapping, so the
whole face lies at one small height off the head. A pair of eyes with their brows is 10 to 50 polygons (52 to 132
triangles); a mouth is 2 to 6.

**Facial hair** (`facial_hair.py`) is four parts, each on or off, and one length for all of them (owner's design):

- **moustache**: above the mouth;
- **sideburns**: in front of each ear, from about the bottom of the ear up to the hair (on a bald head, up to the
  top of the ear);
- **goatee**: the chin, from under the mouth down the front of the jaw and under it;
- **cheeks**: the part between the sideburns and the goatee, as named here: the jaw, the lower cheeks, and the face
  beside the mouth, up to a line from beside the mouth to the foot of the sideburn.

A named style is a set of parts (`PRESETS`): a full beard has all four, an Amish beard all but the moustache, mutton
chops the sideburns and the cheeks, and so on. Any set works. With every part on there is still a gap of skin round
the mouth, so that the mouth can be read on dark hair.

The **length** works the way bulk works on clothes:

- **stubble**: a tint over the skin, flush with the face, like skin-tight clothing. Its colour is the game's own
  stubble colour, worked out from the skin tone and the hair: the skin seen through the hair, always a little darker
  than the skin. Under stubble the mouth shows whole;
- **short**: the hair's colour, opaque, still flush with the face;
- **medium** and **long**: grown out from the face by half a step and a whole step of bulk (`LENGTHS`), with edges
  like a sleeve's. The chin grows downward, so a long beard hangs lower.

Every part is made of the head's own polygons. The polygons a part covers are cut along its edge, the leftover pieces
are joined back together where their colours match, and the ordinary garment rules recolour or lift the parts, so
facial hair follows each head's shape. A moustache that is more than stubble hangs over the mouth, so the mouth is cut
where the moustache is. Hair colour comes from the worn hair; on a bald head it is dark brown.

The game's facial hair settings are these four toggles and the length (`core/specials/facial_hair_settings.gd`).
Its three facial hair items, once a `style` (stubble, chinstrap, full beard), are now parts and a length, and a
wardrobe file saved with `style` is read the same way (`GAME_STYLES` here, `FacialHairSettings.FROM_STYLE` there):
stubble is every part at stubble; chinstrap is the Amish parts at medium, since a narrow strap is not a part; full
beard is every part at medium. `Wardrobe.facial_hair` in `dress.py` makes an item for any other set of parts, for the
pictures and checks.

## How clothing moves

Three ways, by what the clothing is:

- **It bends with the body.** A garment made of regions is the body's own polygons, recoloured or lifted off the
  body, and each corner keeps following what it was lifted from. Straps lie on the chest and follow it.
- **It hangs.** A skirt or a cape is hanging cloth (`hang.py`): a few columns of cloth, each fixed at its top (a skirt
  to the waist line, a cape to the shoulder line) and each a fixed length. Standing, every column is a taut line
  from its top over whatever of the figure sticks out under it, then straight down, leaning out by the garment's
  flare: that fits a skirt to the hips. Each column has five rows of points between its top and its trim line, on
  its bends; a four-sided piece of cloth between two columns that is not flat is split into two triangles along the
  diagonal that folds outward, as cloth over a body does.
  In a pose it **follows bones** (owner's choice, 2026-11): each point follows what its column's top follows and,
  further down, cloth bones turned by the legs (`pose.py`): a skirt's front follows the thigh furthest forward, its
  back the thigh furthest back, its sides their own thigh, each with a second bone at the knee that follows the shin
  reaching furthest that way; a cape swings back with the thigh furthest back. Smooth by construction, and in the game nine bones turned per pose. Laid afresh for every
  pose instead (the first build), the cloth jumped between poses a hair apart: a knee coming under a column snapped it
  out at once, so it would pop in any animation. Sitting, it cuts the corner where the lap meets the belly by up to
  about 2 units (`check.py` holds every other test pose to 0.15).
- **It stays rigid.** Nothing does yet. `pose.posed_rigid` is kept for hard pieces, if they come to need it.

The voxel system turned hanging cloth by rule too: each panel by 0.8 of a thigh's swing. The cloth bones are that
rule grown up: four sides and a knee each, and smooth.

## Files

| File | What it is |
|---|---|
| `clay.py` | the clay bodies and the smooth-shape maths; draws a clay body |
| `rings.py` | cutting a clay into rings; also the first two cuts ("A" and "B") that the look was approved from |
| `body.py` | the bodies: regions, parts, joints; writes `bodies/*.json` and `*.obj` |
| `dress.py` | a whole character from the wardrobe file: body, skin tone, eyes, mouth, features (hair, facial hair) and garments (see the note below). Every polygon it makes says which worn item made it |
| `specials.py` | the special shapes: straps, skirt, cape, with the voxel generators' settings; the hood and the shapes of their own are in the next two files |
| `hood.py` | the hood, raised or lowered |
| `drawn.py` | the shapes of their own (long beard, ponytail, bun, horns, pauldrons): a loft of oval sections from each type's settings |
| `facial_hair.py` | facial hair: four parts and a length, cut into the head's own polygons |
| `hang.py` | hanging cloth: how a skirt or a cape is laid over the figure in a pose |
| `held.py` | held items (weapons, shields, tools, potions): their parts (box, wedge, cylinder, cone, sphere, a drawn outline with thickness, a drawn side view spun round) and how a hand holds them |
| `heads.py` | the five heads; writes `heads/*.json` and `*.obj` |
| `faces.py` | the eyes, with their lids and brows, and the mouth, as flat polygons on a head |
| `pose.py` | posing: the bending skin, hanging cloth, the game's poses in this folder's terms, and the rigid-piece alternative |
| `picture.py` | pictures of polygon meshes: flat shade, smooth shade, edges drawn |
| `sheets.py` | builds the review sheets in `renders/` |
| `check.py` | checks the band table, the geometry, the regions, the files, the clothing in every test pose, the faces against the game's own cells, and the facial hair on every head |
| `game.py` | fetches what is taken from the game: the starter wardrobe, the test poses, the special shapes' settings, the eyes and lid states, the skin, brow and stubble colours |
| `dump_wardrobe.gd` | run by `game.py` in Godot: writes those as JSON into `_work/` |
| `../assets/lowpoly/` | what the game reads (Godot ignores this folder, so the files live there). The eight body files (`body_<sex>_<build>.json`): corners and their shares, polygons with region and part, pivots, the band table and each band's heights on that body, how far the head is raised. The five head files: corners, polygons with their region, the eye box and its angle, the seven sections that define the shape. Generated; do not hand-edit |
| `bodies/`, `heads/` | the same bodies and heads as OBJ files, to look at in any 3D viewer. Generated |
| `expected.py` | writes `tests/lowpoly_expected.json`: where every corner of a figure must be in each test pose, every polygon of some dressed figures and their hanging cloth in several poses, some faces with facial hair, and four test held items in a hand, which the Godot tests hold the game to |
| `renders/` | the sheets each decision was made from. `faces_first_port.png` is the eyes as first ported, in cells with straight or square edges, which the owner turned down for rounded ovals |

`dress.py`, `specials.py`, `hang.py`, `faces.py` and `facial_hair.py` hold the clothing and face rules for polygons in
Python. The game builds the same rules in GDScript (`core/lowpoly/`), and these files are where a rule is tried first
and the cross-check the game is held to (`expected.py`): a change to a rule is made in both. Nothing here copies the
game's tables: the wardrobe, the poses, the special shapes' settings, the eyes, the lid states, the mouths and the
colours the game works out are read from the game each time, and a check holds the defaults equal.

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
GODOT=/path/to/godot python3 lowpoly/expected.py
```

```bash
GODOT=/path/to/godot python3 lowpoly/sheets.py all
```

`check.py` also runs as part of `tests/run.sh` when numpy is installed. Its clothing and face checks, and every sheet
with clothes or eyes on it, ask Godot for the game's wardrobe and tables: set `GODOT=/path/to/godot` (or have `godot`
on PATH). Without Godot, `check.py` skips the clothing and the faces and says so. With it, the check takes about two
minutes (the eight bodies are dressed side by side, four at a time).

`sheets.py` takes `look`, `male`, `builds`, `bodies`, `regions`, `joints`, `heads`, `faces`, `beards`, `shapes`, `moving`, `hood`,
`types` or `all`; the clay
pictures take about 40 seconds a view and are kept in `lowpoly/_work/` for the next run.

## Not decided yet

All of these are the owner's to settle. Recommendations are recommendations.

1. **How hanging cloth moves.** Decided (owner, 2026-11): laid standing, then following cloth bones ("How clothing
   moves" above). Still open under the same heading: hard pieces fixed to one part so that they never bend (which
   could be what the "hard" edge style comes to mean), and sleeves at the shoulder.
2. **Polygon budget.** A body is 344 polygons with an edge on every region boundary, and a head 114: 458 for the
   figure. Dressed in a starter outfit a figure is about 500 to 560: a skirt adds about 56, a cape 28, a pair of straps
   about 36, and every band that is lifted off the body adds a ring of hem polygons. A pair of eyes with brows adds
   10 to 50 (most of them slivers: of the white round the pupil, and of the lash line round the top of the eye; 52 to
   132 triangles, about a tenth of the figure), a mouth 2 to 6. Facial hair adds up to about 22 polygons (66
   triangles) when flush and up to about 56 (134 triangles) when grown out, for a full beard on a bald head; less
   with hair, and less for fewer parts. The first two cuts of the body were 273 ("A", no region edges, a plain block
   for a head) and 603 ("B"); work since has used A. For scale: the 1997 Final Fantasy VII battle model of Cloud is put at about 900
   polygons for the whole character.
3. **Flat or smooth shading.** It changes the look more than the polygon count does. The voxel system's baked
   light/mid/dark does not carry over as it is, and the owner dislikes baked shading on 3D objects. Both can now be
   seen in the editor itself: every tab has a Shading choice.
4. **How far one step of bulk stands off the body.** One old voxel (4.2 cm) now; it reads puffy on sleeves. One number
   in `dress.py` (`BULK_UNIT`).
5. **Edge style.** Soft and hard edges were about which corner voxels to drop; they need a new meaning (see 1) or to
   go.
6. **The masculine clay** is a first pass: shoulder width (about 20% wider than the feminine), the amount of chest
   muscle, the slight belly and arm thickness are the parts most open to change.
   **The slim, heavy and short bodies** are a first pass too (`renders/bodies_builds.png`, and their clays in
   `renders/bodies_builds_clay.png`): their shapes, and the short bodies' proportions. Slim has been made slimmer
   once already (owner): from 0.86 of the average's widths to about 0.78. Calls made while building them, each easy
   to change:
   - **the masculine slim's chest muscle shrinks with its chest** (the others keep the average's): left at the
     average's size, it stood out sideways past the slimmer ribs;
   - **the short bodies have heights of their own**: the same bands, lower, so `SPEC.md` 3.3's "identical row
     boundaries" holds for the voxel bodies and for the low-poly slim, average and heavy, not for the short ones.
     Garments are made of regions, so they fit; everything that used a height directly now reads it from the body.
     The other way, a short body made by scaling an average down whole, is simpler but shrinks the head too, so it
     reads as a child rather than a dwarf;
   - **the short legs**: the first pass had the crotch below the thigh's ring and the knee high on the leg; the
     upper thigh now keeps its height and the shins and lower thighs give it up, which puts the knee where it is on
     the average (57% of the way from ankle to crotch);
   - **the same head on every build**: a heavy or short body may want a broader head, or a short one a bigger nose
     or brow, later.
7. **Facial hair** is built as the owner described it: four parts and one length. Calls made while building, each
   easy to change:
   - **"cheeks"** is the name given here to the part between the sideburns and the goatee;
   - **"semi-transparent" stubble** is the game's own stubble colour: the skin as if seen through the hair. Real
     see-through rendering would look the same here, because the stubble lies on the skin itself;
   - **the lengths**: four (stubble, short, medium, long), with medium half a step out and long a whole step
     (`LENGTHS`). More lengths are one line each;
   - **every part grows by the same amount** for now. The owner has decided (2026-11) that a character keeps one
     length setting, but that it should not mean the same length on every part: a moustache or sideburns grown out
     a whole step stand off the face as much as a full beard does, which reads chunky (`renders/facial_hair.png`,
     row 4). Marked for later;
   - **the game's three items** are read as parts and a length: stubble as every part at stubble, chinstrap as the
     Amish parts at medium (its narrow strap is not a part any more), full beard as every part at medium;
   - **turned down for the voxel face and back now** (`SPEC.md` 5.1): the goatee and the moustache are parts, and a
     beard can have thickness;
   - the long beard is one of the shapes of their own: see 10.
8. **The mouth** is a first pass for the owner to react to: its size, its four shapes, its colour, and whether a
   face has one at all. The game keeps the mouths in a small table next to the lid states (`core/mouths.gd`; `faces.py`
   draws from the same numbers, and `check.py` holds the two equal). Still to settle: how a mouth pairs with a lid
   state (for now they are chosen apart).
   Other calls made in the faces, each easy to change:
   - "vertically centred" was taken as: the middle of the eye at the middle of the flat part of the face. Higher
     than that, the eyebrows run out of room under the hairline;
   - the eye's outline is an ellipse (`ROUND`; a larger number makes it fuller toward the corners of its box);
   - the lash line's colour is the eye set's "line" colour, which the wardrobe already has (a dark brown), not the
     hair's. Its thickness is `LASH`, and `LASH_FLARE` makes it thicker toward the outer corner;
   - how the eyebrow moves: how far it rises and comes down (`BROW_MOVE`) and how much of the lid's tilt it takes
     (`BROW_TILT`) are numbers chosen by eye. Its shape is `BROW_THICK`, `BROW_ARCH`, `BROW_REACH`;
   - a chinstrap's sideburn is the one polygon of each ring just in front of the ear (the voxel one was a strip
     three deep);
   - ears stay skin under hair. The crop's regions include the ears' polygons; coloured as hair they read as lumps;
   - the face's polygons lie 0.04 units off the head (1.7 mm), not cut into it. Godot draws them that way too: at the
     editor's distances the depth buffer tells 0.04 apart with room to spare, so they do not flicker. At a long
     game-camera distance that is worth checking again; cutting them into the head, a depth offset, or painting the
     face with a small texture or a shader are the ways out.
9. **Calls made in the special shapes** that differ from the voxel ones; each is easy to change:
   - a skirt hangs from the waist line, not from below the hips (a lap needs the cloth to lift off the hips);
   - "four panels" is one cloth all round; "two panels" is a front cloth and a back cloth with the sides open (the
     voxel four were separate slabs that parted at the corners when they swung);
   - an open front starts as a point at the hips and widens to the hem, instead of starting two units wide;
   - straps run from the shoulder straight to the front of the waist. The voxel rule, a plumb line from the shoulder,
     ends on the flank of these rounder bodies;
   - a strap is a flat band standing 0.12 units off what it lies on, with no thickness of its own;
   - a cape hangs from the shoulder line whatever the arms do. An arm swung far back goes through its edge.

10. **The hood and the shapes of their own** (`renders/hood.png`, `renders/shape_types.png`, `docs/NOTES.md` 4za, 4zb):
   - **the hood**, raised: a loose shell measured off the dressed head (hair included), a brim over the brows, more
     room at the back and over the crown, the face left open, falling to a short cowl on the shoulders; lowered: a
     cowl closed round the neck and the empty hood lying on the upper back. Its "Looseness" setting (`depth` in the
     file, "Thickness" before) is how far it stands off the head: 1.3, 1.9 or 2.5 units. The owner's plan was to
     generate a looser hood, then hand-tune it: the hand-tuning is four shape settings, 0 to 3 (peak, 0 a round top
     and the default; brim; fullness at the back; cowl length, which for a lowered hood is its collar's);
   - **the shapes of their own** replace the voxel drawn shape (owner's choice: fixed types with a few settings, over
     hand-set sections or the cell drawing; `renders/drawn_shapes.png` is the comparison it was chosen from, and the
     code that drew it is in commit `a8ef07e`). Five so far: long beard, ponytail, bun, horns, pauldrons. A new type
     is a small function and its settings, here and in the game;
   - weak spots: an arm raised or reaching forward goes through the hood's cowl, which follows the chest (as an arm
     swung back goes through a cape's edge); over a ponytail the raised hood bulges in a rough ridge; a lowered hood's
     lining faces up and is hidden by the head at a low camera; a pauldron sinks into the shoulder when the arm goes
     overhead (the arm is one rigid piece at the shoulder); a hand reaching forward goes through a long beard; from
     straight in front the big head hides much of a pauldron.

Known weak spots of the clothing built so far: hands hang close to the hips, so a skirt with much flare meets them;
a bulky boot touches a shin-length hem and pushes it out a little; the wardrobe's shirt and trousers leave the waist
row bare between them (the voxel figure has the same strip of skin). Where three different amounts of bulk meet at one
corner (hair, a grown-out beard and bare skin at the top of a sideburn; two beards of different lengths), the three
hems there leave a small open triangle between them: each hem steps between two of the three, and nothing closes the
corner. A triangle on the three lifted corners would close it; that is a change to the hem rule here and in Godot
alike (found in the review of phases 2 and 3, `docs/NOTES.md` 4w).

Known weak spots of the faces built so far: the mouth cannot go lower than it is, because the flat part of the face
ends a quarter of a unit under it and the jaw slopes away there; on the deepest skin tone the mouth and the default
dark eyebrows are hard to see at small sizes; under a fringe the eyebrows sit just below the hair's edge, and a raised
brow touches it; a moustache hides the upper part of the mouth, so a smile or a frown under one is only its lower
edge; a fair beard on light skin is hard to see; grown-out sideburns cover the front of the ear a little, seen from
the side; the short crop, coming from region rules alone, stands off the whole back of the head like a cap.

Known weak spots of the bending skin, at this polygon count: a sharp bend loses a little volume on the inside of the
joint, and the inner thigh stretches flat on a very high step. The shoulder is a ball, so a raised sleeve cuts into
the chest instead of flowing into it.
