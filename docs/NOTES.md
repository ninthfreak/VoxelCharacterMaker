# Build notes

Decisions taken while building, discrepancies found in the hand-off package,
and what is still open. `SPEC.md` remains the design record; this is the log of
what happened when it met code.

Difficulty and confidence are rated explicitly, because a flat narrative hides
which parts are solid and which are guesses.

---

## 1. Verification status

**Everything compiles and the acceptance suite is green: 1494 checks, 0 failures.**

```bash
tests/run.sh                 # measures the assets, then runs the Godot suite
```

Verified by running it:

- Every structural claim in `SPEC.md` section 12 about the assets: all six
  voxel counts, every pivot x in the section 3.2 table, mirror symmetry, one
  connected piece per body and per part, no edge-only contacts, all 11
  expressions fitting all 5 heads.
- The section 2 coordinate lock, asserted against Godot's own camera
  convention rather than against this project's arithmetic.
- The bulk rules one at a time, parametric garments generating with no gaps on
  all six bodies, bulk 0 adding nothing, layering by reach then draw order,
  the wardrobe round-tripping byte for byte, both special generators on every
  head, and the rig's joint chain landing on each part's pivot.
- The figure renders correctly, which `docs/renders/` shows.

### Two real bugs the first run caught

Worth recording, because both were invisible to review and one was invisible to
the test suite as it then stood.

**1. The rig mixed an affine point map with a relative offset.** A joint's
position is the offset between its pivot and its parent's, but the root has no
parent, and `Vector3.ZERO` was being passed as a stand-in and then run through
the full point mapping -- which adds a translation that should have cancelled.
The whole figure sat half a metre off-centre. Caught by the first assertion
that looked at a joint position.

**2. `direction_to_godot` did not apply the voxel scale.** It permuted the axes
but never multiplied by 1/24, so every child joint sat 24 times too far from
its parent and the figure exploded into loose slabs. The test suite missed this
entirely: `test_axes` only checked unit axes, where a missing uniform scale is
invisible, and the rig test only checked the root. It was obvious in the first
render and in nothing else.

Both are fixed, and both now have tests that would have caught them: a
displacement must agree with the difference of the two mapped points, 24 voxels
up must be one metre, and walking the joint chain from the root must land on
each part's pivot.

**The lesson worth keeping:** a test suite over a geometry pipeline can be
large and green and still miss a uniform scale error. The render is not a nice
extra here, it is part of the check. `tools/render_sheets.gd` exists for that.

## 2. Discrepancies found in the hand-off package

**`assets/README.md` overstates one contact.** It says "arms touch only the
chest at the shoulder (exception: female heavy's forearm rests against the
hip)". Measured, female heavy's forearm is **2 voxels clear** of the pelvis
(Chebyshev distance 2, so a full empty voxel sits between them — not a face
contact and not even a diagonal one). It is the closest clearance of the six
bodies, and the same 2 to the thigh and the chest. So the strict `SPEC.md` section
3.1 rule, "every part touches only its parent", holds on **all six bodies** with
no exception, and `tests/test_assets.gd` asserts it with no exception. The
README's note appears to be stale. Nothing needs fixing in the assets; the note
is just wrong in the owner's favour.

**"30 regions per side" does not follow from the stated rule.** `SPEC.md`
section 3.4 says regions are "part family + row band, split left/right ... and
torso and head bands also split front/back", then says there are 30 per side.
Applying that rule to the 22 bands gives **32 per side**: 10 head and torso
bands split front/back (head 4, chest 4, pelvis 2) plus 12 limb bands, doubled
per side. 32 − 30 = 2, which is exactly what you get if the two single-row trim
bands in those families, `neck` and `waist`, do *not* split front/back.

That is a guess, so nothing was silently changed. The general rule is
implemented (32 per side), which is strictly more expressive and costs nothing:
an unused region is simply never painted. If the intent was that `neck` and
`waist` stay whole, there is a named note in `core/region_map.gd:all_keys()` and
it is a one-place change.

**Open question for the owner:** which did you mean?

**A bulk-1 garment on both thighs closes the gap between the legs.** Measured:
the gap between the thighs is exactly 2 voxels on all six bodies, and bulk 1
grows 1 voxel inward from each thigh, so it fills exactly. 60 to 88 cells
bridge the gap depending on the build, and standing still, trousers read as a
skirt. See `docs/renders/six_dressed.png`.

This is not a coding fault: it follows directly from SPEC 7.3 rules 1 and 4,
and rule 4's own words apply -- the legs do separate again when the figure
moves. But the standard gap being exactly twice the normal minimum bulk looks
like a coincidence nobody intended. Four ways out, for the owner to pick:

1. Accept it. Walking separates the legs, and a fused rest pose may not matter.
2. A per-garment flag, "do not grow toward the mirror line", for paired limb
   parts. Smallest change; leaves rule 4 intact everywhere else.
3. Make that the default for paired limb parts, with a flag to opt back in.
4. Widen the thigh gap in `build_bodies.py`. This changes all six bodies and
   invalidates the section 12 voxel counts, so it is the most disruptive.

*Recommended:* option 2, because it is reversible and costs nothing until a
garment asks for it. Not done, because which way this goes is a look decision.

**Resolved (owner, 2026-11), as option 3 without the opt-out:** bulk rule 8 --
nothing worn on the legs or feet grows into the gap between them; the leg's
inner face is recoloured instead -- plus skin-tight trousers as the norm. See
section 4f.

---

## 3. Decisions made, and why

**Culling per part, shading across the whole figure.** These pull in opposite
directions and the split matters. The mesher culls a voxel face only against
*its own part's* cells, so a limb that rotates away never opens a hole — which
is the right trade given `SPEC.md` section 3.1 has no joint caps and accepts
gaps at bent joints. Shading, by contrast, runs over the *whole* assembled
figure in its rest pose, so a sleeve shades as part of the silhouette rather
than as a free-floating tube. That is also what `build_bodies.py` does, so the
`.vox` previews and the engine agree. Confidence: high.

**Bulk grows from the body, never from the layer underneath.** `SPEC.md` 7.3
rule 6 says bulk is measured from the body, so every item grows from the same
base occupancy regardless of what is already worn. Simpler and matches the
spec; the alternative (each layer growing off the last) would make an outfit's
appearance depend on draw order in a way nothing asks for.

**Layering compares the item's bulk, not the cell's depth.** Rule 6 says "the
one reaching farthest from the body wins; draw order breaks ties". At a *shared*
cell both items are necessarily the same distance out, so "reaching farthest"
was read as "whose bulk in that region is greater" — the outer garment owns the
whole stack. Only buried cells are affected either way, because the visible
surface is always the outermost one. Noted at the comparison in
`core/character_assembler.gd:_offer()`. Confidence: medium; it is a reading of
an ambiguous sentence, and the visual consequence is near zero.

**The face is a claim, not a special case.** Rather than a separate pass, the
expression claims head cells with reach 0 at draw order −1, below every garment
category. The existing layering rule then produces "the face draws under hair
and hats" (`SPEC.md` 5) with no extra code, and a bulk-0 hat over the eyes
covers them, which `tests/test_faces.gd` checks. Confidence: high.

**Growth seeds from surface cells only.** Under both the Chebyshev and the
Euclidean metric, the nearest source cell to any exterior cell is a surface
cell, so filtering out interior cells cannot change the result — only the cost.
Confidence: high; this is a proof, not a hope.

**Edge style as a metric, not a post-process.** Soft is a ball
(`dx²+dy²+dz² ≤ n²`), hard is a cube (`max(|dx|,|dy|,|dz|) ≤ n`). At bulk 1 the
only difference is the diagonal corner cell, which is exactly "rounded corners"
versus "squared". Falls out in two lines instead of a corner-rounding pass.

**The editor's UI is built in code, not laid out in a `.tscn`.** A hand-written
scene file cannot be read for correctness the way a script can, and this session
could not open the Godot editor to lay one out. `editor/editor_main.tscn` is
therefore a bare root node and `editor_main.gd` builds every control. This is a
reasonable thing to migrate to real scenes later; nothing outside `editor/`
depends on it. Confidence that this was the right call *given the constraints*:
high. That it is the right long-term structure: medium — scenes are more
idiomatic once someone can click around.

**Undo is snapshot-based.** The wardrobe is a few kilobytes of JSON, so every
edit pushes a full snapshot (`editor/edit_history.gd`). It cannot drift out of
sync with the model the way a command stack can, and at this size the cost is
irrelevant. Every edit path funnels through one `commit(label)` call, so "undo
for every edit" (`SPEC.md` 8) is structural rather than something to remember.

**Colours serialise as `#rrggbb`.** Floats would make the byte-identical
round-trip (`SPEC.md` 12) fragile for no benefit. Nothing in the figure is
translucent, so alpha is not stored at all.

---

## 4. What is deliberately not built yet

In the spec's own build order (section 11), steps 1–5 are done. Of what is
left, step 7 is deferred by the owner; 6 and 8 are simply not started yet:

- **Face editor** (step 6) is built, as the Eyes part of the Face & Hair tab:
  a grid of both eye boxes, "both eyes" mirroring, expressions, eye colours.
- **Export: .vox, STL, OBJ** (step 7). **Deferred by the owner** until work
  starts on the actual game. Nothing else depends on it. When it comes round:
  the STL "edge-contact fix" needed for a watertight export is not written, but
  `TestReport.edge_only_contacts()` already detects the condition the fix has to
  remove, so the test for it exists before the feature does. The shipped bodies
  have no such contacts, so the fix only matters once garments and hand-placed
  edits can introduce them.
- **Body editor** (step 8) is now built: parts as layers, one owner per cell,
  mandatory mirror pairs, row-band guides, pivot markers and the pose preview.
  What it does NOT yet have is a front or side elevation view. Editing happens
  on horizontal z-slices, which is the unit the bodies were designed in --
  build_bodies.py builds each one as boxes over row ranges, and a row belongs
  to exactly one band -- but shaping a silhouette would be easier with an x-z
  view as well. Worth adding if the slice view turns out to be awkward in use.
- **More special types.** Skirt, cape, hood and a drawn "shape" exist. The
  generator registry describes its own parameters, so a toga, a standing
  collar or a pauldron needs one file and one line in `SpecialItem.types()`
  and no editor changes -- though the drawn shape may cover many of these.
- **Decals** — deferred in the spec, and still deferred.

---

## 4a. Two notes from building the body editor

**Edited bodies and heads live in `assets/edited/`.** The spec says asset
JSON is generated and regenerated rather than hand-edited (CLAUDE.md), but it
also says the owner expects to tweak bodies in the editor (section 3.3). To
stop those colliding, the editor saves to `assets/edited/` and the library uses
an edited file in place of the generated one when there is one. Running
`build_bodies.py` can no longer wipe an edit. The cost: an edit no longer
follows changes to the script, so a body regenerated with a fix will not show
the fix while an edit of it exists. Whether edits should eventually become the
source of truth (and the script retire) is still the owner's call; this is a
recommendation that keeps both doors open.

**Pivots are measured, never stored.** `BodyEdit` recomputes every joint from
the geometry the way build_bodies.py measures it, so an edited body gets the
pivots it would have had if it had been generated. The test asserts this
against all six shipped bodies, and it independently reproduces the parity
exceptions SPEC 3.2 lists by name: 3-wide arms on both slims and feminine
average, and feminine heavy's 5-wide legs, pivot on a voxel centre. Nothing
else does.

## 4b. The four-tab editor, and special shapes

The editor is now four tabs, each with its own preview: **Bodies** (bare
figures, edit bodies and heads), **Face & Hair** (eyes, hair, facial hair),
**Clothes** (items with all their settings, cycled across all six bodies) and
**Preview** (any combination, nothing edited). One undo timeline runs across
the wardrobe and an open body or head, and nothing unsaved is lost without a
prompt -- body or head first, then the wardrobe -- including on window close.

**How eyes, hair and facial hair work.** They are items, like clothes, with a
`slot` ("hair", "facial_hair"); clothes have no slot. A character has exactly
one per slot, and "none" (bald, clean-shaven) is a valid choice, not a gap.
Eyes are an *eye set*: styles that share one list of expressions, each a 4 x 5
box per eye with white / pupil / line roles and named colourways. Eye colour
therefore now lives in the eye set's colourway rather than on the figure.

**How special shapes are modelled.** Any item -- clothing or feature -- has
its body regions (the parametric part) *and* a list of special shapes. A
special is an **anchor** measured on each body (12 so far: face, brow, crown,
nape, chest, back, waist front/back, hip, shoulder, wrist, ankle) plus a
**form of its own** that does not follow the body:

- *skirt* -- anchored at the hips, hangs as cloth panels that swing with the
  legs. A dress is bodice regions + a skirt.
- *cape* -- anchored behind the shoulders, a panel that trails behind and swings
  back (never forward through the legs) in a stride.
- *hood* -- anchored to the head; grows from its surface and leaves the face
  open, up or down.
- *shape* -- a small voxel drawing (17 x 7 x 21 box) placed at an anchor. It
  either **wraps** (each column is pushed onto the body surface, so a beard
  follows every jaw) or stays **rigid** (a feather, a buckle, a horn). It can
  mirror, and can recolour body cells instead of adding to them.

A hooded cloak is a cape plus a hood on one item.

### Problems found (difficulty / confidence)

1. **The head's regions are too coarse for a face.** The mid-head front band
   (z 31-36) overlaps the eye rows (z 29-33), and the lower band (z 26-30)
   holds the bottom eye rows. (Unchanged in kind by layout B; see 4c.) So hair can only use crown and back regions
   without covering the eyes, and facial hair *has* to be a drawn shape. It
   works, but it means two ways to author the same thing. Fix: finer face
   bands in the region map -- moderate work, and it changes the 32-a-side
   count the owner settled, so it is the owner's call. Confidence the problem
   is real: high.
2. ~~A moustache has two rows to live in.~~ Layout B (4c) gave the lower
   face three rows; the moustache now has a skin row between it and the eyes.
   On the heart head's narrow chin it still sits low and reads more like a
   chinstrap -- part of the coming eyes-and-face pass.
3. **Hats and hoods versus hair.** A hood or hat should hide most hair; right
   now both simply claim cells, and the layering rule decides. The Clothes tab
   has a hair picker so this can at least be checked. A real fix is a "hides
   hair regions" flag on an item -- small, but how much hair a hood should
   leave showing is a look decision.
4. **Anchors are measured, so they can move when a body is edited.** That is
   the point, but a big edit to the shoulders will move every cape. Expected
   behaviour; noted so it is not a surprise.
5. **Drawn shapes are flat-ish.** The wrap mode pushes columns onto the
   surface, which is right for beards and badges but cannot make something
   that curves *around* a corner of the body (a scarf, a belt buckle on a
   side). Those still want regions, or a future "wrap around" mode. Moderate
   difficulty, medium confidence it matters.
6. ~~Skirt panels and trousers.~~ The thigh-gap problem is fixed (4f); a
   skirt's panels already clear thick trousers worn under it (4c).

**Owner's answers (problems above):** 1 -- to be worked out together. 2 --
probably not a problem; later. 3 -- hats will likely need a few options for
how they interact with hair; to be decided. 4 -- to look into once the owner
is using the real program. 5 -- agreed; a final body should be fixed early so
clothing does not keep chasing body changes. 6 -- to be examined later.

### Opportunities

1. ~~A character record.~~ **Ruled out by the owner:** the editor will never
   save an assembled character. It saves only the parts (bodies, heads, eye
   sets, hair, facial hair, clothes, outfits); putting a character together
   and remembering it is the game's job. The Preview tab is for looking only.
2. **The drawn shape is general.** Collars, pauldrons, horns, ears, crowns,
   belt pouches can all be drawn shapes at an anchor, which may mean few new
   generator types are ever needed.
3. **More anchors are cheap.** Each is a few lines (a body part, a band and a
   direction). Knees, elbows and the small of the back would open up knee
   pads, elbow patches and quivers.
4. **Specials on features.** Because features are items, hair can already use
   specials: the ponytail is a rigid shape at the nape. Long braids or a bun
   come for free the same way.

## 4c. Layout B: a bigger head (owner's decision)

The head grew from 14 to 16 rows, and from 14 to 16 wide (oval 12 to 14) and
12 to 14 deep, so faces have more room. The figure stays 42 tall: one belly row
and one upper-thigh row went, and the forearm lost a row so the hands still
hang just below the hips. SPEC 3.1, 3.2, 3.4, 4, 5 and 12 are updated.

**One table for every row.** `tools/build_bodies.py` now places every part,
pivot, ear and the eye box from its `BANDS` table, and `core/body_layout.gd`
is the Godot copy that every row number in core/, the editor and the runtime
now comes from. A test checks the copy against every body and head file, and
`tools/verify_assets.py` reads its rows from the files. Before switching, the
rewrite was checked by regenerating with the old table: the bodies and three
heads came out byte-identical; oval and heart differed only by the corner cell
of each narrowed jaw/crown row, which are now rounded like the others.

**Rounder heads.** Each head row is now a rectangle, inset and then rounded by
a stepped corner profile. Round, oval and heart use a three-cell corner step
and round, strong and heart a two-row rounded crown; strong keeps its square
jaw and boxy stays boxy. The heart's jaw narrowing stops below the eyes, since
the rounding would otherwise cut the eye box's outer corner.

**Eyes:** unchanged (4 x 5, same columns), now on rows z29-33 with three skin
rows under them, pending the owner's eye decision. On the oval head the outer
eye column sits at the edge of the flat face, so one white pixel shows from
the side -- as it did before.

**What else moved with it:** anchors (face, brow, nape, chest, back, waist,
hip, wrist, ankle), the head checks, the body editor's pivot windows, the beard
and moustache drawings (now three rows of face to fill), and the editor's head
framing.

**A bug the new geometry exposed.** A cape hung one voxel behind the deepest
point of the *body*, but the tunic and trousers under it reach that same plane,
so about 150 cells belonged to both the cape and the clothes and the two
meshes flickered there (z-fighting). It was there before layout B; the new
shapes only changed which face won on screen. Fixed: shapes now see the figure
as worn so far, a cape hangs behind everything under it, a skirt's panels
clear trousers and boots, and within one item the hanging shapes are placed
last (so a hooded cloak's cape hangs behind its own hood). A test now checks no
panel shares a voxel with any other part, for every outfit on every body.
One edge case: a skirt over trousers on the slim feminine body meets the hand,
which hangs one voxel clear of the hips; the skirt leaves those few cells out.

**Not changed here:** trousers filled the gap between the thighs from both
legs (fixed later, see 4f), and the tunic and a sleeve still meet in one cell
where an arm hangs against the torso. That one is left alone on purpose: an
arm resting against the body is the normal sprite look.

**Edited bodies and heads** saved before this change (in `assets/edited/`)
would be on the old layout and would need redoing; none existed here.

## 4d. Eyes, lids and brows (owner's design)

Worked out with the owner through mock-ups, neutral only:

- **The open eye is "G7"**: 5 x 6, white, all corners rounded, a black 1 x 2
  pupil dead centre. Locked in as *wide open*.
- **The eyes are the same size on every head, always.** The oval had only 10
  flat columns; its corner rounding was eased one step to give 12. A test and
  the asset oracle fail any head without a flat face for both eye boxes and
  the brow row.
- **Lids and brow** are numbers per eye -- upper lid rows, lower lid rows,
  pupil shift -- applied over the eye (`core/eye_lids.gd`). The brow leads the
  upper lid; the lower lid has no line; the brow is always full width. The one
  line is brow and lash line both: accepted, since it reads as the brow when
  the eyes are wide open (owner).
- **Colours:** lid = skin half a shade darker; brow = hair one shade darker;
  bald = dark-brown brow unless set. Skin is now a choice of six tones.
- **Where it shows:** Preview has Eyelids, Skin tone and Brows controls.
  Bodies and Clothes show neutral; Face & Hair shows wide open, so no lid hides
  the drawing being edited (the raised brow still shows against the hair).
- **Review sheets:** `docs/renders/faces.png`, every lid state on a different
  head, skin tone and hair; `faces_tilt.png`, angry and sad close up.

Still open, from this:

1. ~~Drawn expressions vs lids.~~ **Settled: the drawn expressions are
   retired completely** (owner). An eye set is now just the open eye and its
   colours; the generator ships one face, `face42_open.json`; older wardrobe
   files load their "neutral" drawing as the eye. No ^ ^ arcs for now.

**Owner, 2026-11: very happy with the eyes and the lid system as built**
(G7, lids and brow, tilt, angry and sad included). Treat it as settled; change
it only when asked.
2. **Brow colour on light hair** is the weakest case (fair hair gives a light
   line). Revisit if it reads badly in use.
3. **Runtime cost of blinking (unmeasured).** A lid change rebuilds the
   head's mesh. Fine in the editor; for many blinking characters in the game,
   pre-building each character's few lid states or a separate eye overlay mesh
   may be needed. A game-side decision.

## 4e. Facial hair (owner's choices)

Mocked across heads, skin tones and hair colours. Kept: stubble (always
darker than the skin, with a sideburn strip on the head's side), chinstrap
(raised strap and sideburns), full beard (= chinstrap + stubble). Rejected:
goatee, moustache, moustache + goatee, a volumetric beard, flat sideburns.
The long beard is a *face accessory* (optional slot), hand-drawn under a new
chin anchor so it can be tweaked.

- Built as one generator that reads each head's surface, so **facial hair no
  longer needs finer head zones**. The zone question (problem 1 in 4b) now
  only matters for hair fringes.
- Colours follow the character via colour references `@stubble` and `@hair`,
  resolved at assembly; any item role can use them (the colour panel lists
  them first).
- The old drawn short beard and moustache items are gone.
- Review sheet: `docs/renders/facial_hair.png`.
- Watch: an auburn chinstrap on medium skin is low contrast (hue close to the
  skin). Fine for now; revisit if it matters in use.

## 4f. Evaluation at sprite size, and the trouser fix

**The test.** Assembled characters drawn straight on at one voxel per pixel
are sprites about 24 x 42 px -- classic 16-bit size. Findings (2026-11):

- Faces carry: angry, tired, suspicious and wide open are all told apart at
  the actual 42 px.
- Body types only partly read once dressed alike. Dressed widths are 20 / 24
  / 26 px (masculine slim / average / heavy) and 18 / 20 / 24 (feminine);
  masculine slim and feminine average have almost the same outline (6 px
  differ of about 390). Bare, all six read. Whether to widen the spread or let
  hair and clothes carry it is the owner's call, still open.
- Outlines are all "head on a block": nothing built yet changes the outline
  from the front. A hair pass aimed at volume is the likely fix.
- The bust shows through a tunic as light blotches rather than a shape.
- The homage is in the data (sprite-sized, chibi head, three tones, eyes-only
  faces) but unproven in motion: smoothly rotating rigid parts turn voxels
  off the grid, which reads as a toy rather than a sprite. A small look test
  (one walk cycle in a few styles, at low resolution, from a candidate
  camera) is the recommended next experiment.

**The trouser fix (owner chose it from mock-ups).** Trousers and boots fused
the legs into one block -- the most visible flaw at sprite size. Now:

- Bulk rule 8: nothing worn on the legs or feet grows into the gap between
  them; the leg's inner face is recoloured instead (`BulkBuilder.
  without_leg_gap`, `leg_inner_face`, applied by the assembler to thigh and
  shin parts). Any bulk, either edge style.
- Skin-tight (bulk 0) is the norm for trousers; the starter trousers are now
  skin-tight, so a top's hem reads as worn over them.
- Tests on every body: the everyday outfit and thick legwear in both edge
  styles keep the gap open from feet to hips, leave no skin on the inner
  faces, stay symmetric, and thick legwear still grows outward. (With the rule
  switched off, 36 of those checks fail.)
- Rejected: a dark seam down a fused block (still reads as one block), and
  half-size voxels for clothing (mixed voxel sizes; not pursued).
- Drawn shapes are placed as drawn: rule 8 governs grown bulk, not hand-drawn
  cells.

## 4g. Suspenders, and overalls as an outfit (owner's idea)

Zones alone can make trousers with a bib but not straps: the smallest zone on
the upper chest is a quarter of it. So:

- **Shoulder straps** are a new special type (`core/specials/
  strap_generator.gd`): up the chest, over the top beside the neck, straight
  down the back, one voxel proud, placed halfway between the neck and the
  chest's edge so wide chests carry them wider. Steps in the chest (the
  rounded collar row, a bust) are bridged so each strap is one connected
  strip. Width 1 or 2. A crossed back was tried and reads as a cluster of
  pixels at this size; the owner chose straight.
- **Starter items:** Suspenders (accessory, uses the straps), Bib (zones only,
  draws above tops), and a skin-tight Shirt to wear under them. Trousers gain
  a denim colourway.
- **Overalls are an outfit:** trousers + shirt + bib + suspenders, with the
  three denim pieces in one colour. Each piece is useful alone.
- **Starter outfits were then five:** everyday, travelling, dressed up, shirt
  and suspenders, overalls. (Seven now: see 4h.)
- The bib is skin-tight, so under a thick top (the starter tunic) it is
  hidden by the layering rule; raise its bulk to wear it over one.
- Not yet verified: whether the bib alone reads as an apron.
- **Straps take the shade of the cloth they lie on.** A strap one voxel wide
  is all edge, so the baked lighting made every voxel the light shade and the
  overalls' straps read lighter than the bib (owner noticed). A special's
  claim can now fix its own shade; straps use mid in front, dark behind and
  light on top, which is what a flat garment's faces get there.

## 4h. Skirts as their own items; dress, toga and robe as outfits (owner's design)

- **No dress item.** The owner's rule: skirts are always skirt-only items,
  and a dress is a top that matches the skirt. Checked before building: a
  bodice + a skirt item assemble into exactly the voxels of a one-piece dress
  on all six bodies (a test now builds the one-piece version and compares).
- **What a skirt item is:** the hips in cloth (regions) + the skirt shape,
  category `bottom`. The waistband is on, because a top that stops above the
  waist (the shirt) otherwise leaves one row of skin showing at the join.
- **Honest limit:** "any top with any skirt" works, but the one-garment look
  needs a top made for it, one that ends at the waist: tunic + skirt reads as
  a tunic and a skirt. Shapes that cross the waist as one line (a wrap edge
  from collar to hem, a sash from shoulder to hip) have to be made as a pair.
- **Two fixes the split exposed:**
  - *Placement order.* Panels used to be placed last within their own item.
    A skirt-only item draws before boots, so an ankle-length skirt shared up
    to 34 voxels with the boots (flicker). All hanging shapes are now placed
    after everything worn; draw order still decides contested voxels.
  - *Back shading.* The per-voxel shading printed the legs onto the back of
    every skirt: dark where a leg touched the cloth, lighter between the
    thighs and around the shins. Capes had the same fault (a dark patch where
    the cape touched the back). Panels now take one shade by the way they
    face, the same idea the straps already used; all three go through
    `Shading.face_tone`. This is the third time the per-voxel rule misread
    thin cloth (straps, bust blotches, panels). The bust is still open, and
    "no baked shades" would remove the whole family: see section 5.
- **Asymmetry is two settings on the normal skirt**, not a new item type:
  hem slant and opening (wrap / front), both aimed at one side. Evaluated at
  sprite size first: the slanted hem and the toga read best; the wrap reads
  from the front and in 3D but not from the side (the side panel still
  covers); a narrow slit read as a two-pixel stripe and was dropped; the
  open front reads as a robe but is the busiest of the three.
- **An open front is two flaps**, each following its own leg forward and
  hanging when that leg goes back, so the opening widens in a stride.
- **Starter pieces:** Bodice, Skirt, Wrap skirt, One-shoulder top (mirror
  off), Robe top, Robe skirt. **Starter outfits are now seven:** everyday,
  travelling, dress, toga, robe, shirt and suspenders, overalls.
- **Known and left alone:** an ankle-length skirt over boots stands one
  voxel proud of the hips, because the panels must clear the boot cuffs and a
  panel is flat. Skirts always start at the hips, so a high-waisted dress
  would need a new setting. Colours of the two halves of a dress are kept in
  step by hand (same colourway names; one shared palette colour).
- **Test runner:** a script error stops the suite it happens in and the
  checks after it never run, yet the tally could still say "0 failed".
  `tests/run.sh` now fails the run if any script error is printed.

## 4i. Low-poly is the direction (owner's decision)

- **What led there.** The bodies' shapes were being reworked from a smooth
  "clay" model turned into voxels at 4, 2 and 1.5 times the resolution, and
  then with straight-sided limbs at 2x. The owner had been down the same road
  before this project, more than once, and it ended in the same compromises
  each time. They dropped the voxel look for a low-poly one (`SPEC.md`
  section 0). None of that voxel rework was committed.
- **What carried over** (difficulty low; confidence high): the clay model
  became the source of the bodies. Its unit is the voxel, so the band table,
  the regions, the parts and the pivot heights apply as they are, and the
  wardrobe file needs no change. A check holds the low-poly band table equal
  to the voxel bodies' region table.
- **What was built:** `lowpoly/`; its README has the state, the method and
  what is still to decide. Nothing in `core/`, `runtime/` or `editor/` has
  changed.
- **A bug worth remembering.** On the first low-poly sheet the stand-in head
  was built with its corner points joined in the wrong order, so some faces
  ran through the inside of the head. The body had been checked up close and
  the head only glanced at. Every mesh now goes through a geometry check
  before it is shown (`lowpoly/check.py`; the rule is in `CLAUDE.md`).
- **A deliberate duplication.** `lowpoly/dress.py` applies the bulk rules to
  polygons. The project keeps that logic in one place, `core/`, which today
  only knows voxels. When the Godot side builds polygons the rules move
  there, and `dress.py` goes or shrinks to a cross-check.
- **Joints** (difficulty medium; confidence high on the look, medium on the
  Godot work, which is not started). Two ways were built on the same body and
  poses: rigid pieces with rounded ends, and one skin that bends. Rigid
  showed seams at every joint, steps wherever a joint twists (two faceted
  rims stop lining up), garment ends poking through, and about 60 per cent
  more polygons, with every garment piece needing its own ends. The owner
  chose the bending skin for the body, and expects clothing may need to be
  different. The bends sit in the one-row trim bands, so the bodies needed
  no new edges. Shares and pivots are in the body files (format version 2).
- **Not an experiment.** The owner corrected the framing: low-poly is the
  project. It is built as product work and committed as it goes.
- **Heads** (difficulty low; confidence medium on the look, which is the
  owner's to judge). The five voxel heads are rebuilt as low-poly forms,
  following their ideas and proportions without tracing them. Each is seven
  rounded-rectangle sections; all five share one layout of polygons. What
  section 4 of the spec says every head shares is kept and checked: the
  size, a flat face over both eye boxes and the brow row, the ears. That
  flat face is why none of the heads is round in plan at eye level: the
  front corners can only be rounded outside the eye boxes. The body files
  no longer carry a head; any head goes on any body.

## 4j. Special shapes as polygons: straps, skirt, cape

The first three of the special shapes (`SPEC.md` 7.4) are rebuilt for the
low-poly figures, in `lowpoly/specials.py` and `lowpoly/hang.py`. Each takes
the voxel generator's settings under the same names, and a check holds the
defaults equal to the game's own table. Hood, hair, beards and drawn shapes
are still to come (stubble, chinstrap and full beard followed in 4l).

- **Hanging cloth is laid afresh for every pose** (difficulty medium;
  confidence high that it works in Python, medium on the Godot work, which is
  not started). A skirt or a cape is a few columns of cloth, each fixed at its
  top and of fixed length. For a pose, each column is a taut line from its
  top over whatever of the figure sticks out under it, then straight down.
  Nothing is simulated and nothing is carried from one pose to the next.
  **This replaces the voxel panels' rule** (each panel turned by 0.8 of a
  thigh's swing). It is a call made while building, and the owner's to keep
  or throw out. The reason: a panel hinged where the skirt is fixed cannot
  cover a lap when sitting, and a panel hinged at the hip joint (the voxel
  way) lifts the whole hem in every stride and pokes out past the knees like
  a tray when sitting. The taut line gives the fit over the hips when
  standing, the knee pushing the front out, the heel pushing the back out and
  the lap, from one rule. In Godot it means a cloth is a small mesh whose
  points are worked out when the pose changes (about 50 points), not bones.
- **Tried first and dropped: measuring along each column's own facing.** The
  cloth between two columns is a flat face, and a knee or a toe that stands
  behind a face, between its two columns, came straight through it. Each
  column now minds its two faces.
- **Tried and dropped: arms pushing a cape.** A raised arm carried the cape's
  edge up with it and the cape turned into a funnel. A cape now hangs from
  the shoulder line whatever the arms do; an arm swung far back goes through
  its edge.
- **A flare bug.** Flare was first measured from where the cloth leaves the
  figure. Bulky boots touch a shin-length hem, so "where it leaves the
  figure" became the boots, and the front of the skirt lost its flare while
  the back kept it. Flare is now an even widening below the hips.
- **Straps took three tries** (difficulty medium; confidence medium on the
  look, which is the owner's to judge). (1) A thick band with walls, on a
  plumb line from the shoulder: a blob seen from the side, 64 polygons, and
  no room for it at the masculine waist. (2) A band of true width following
  the surface: thin and uneven from the front. (3) Kept: a flat band one unit
  wide seen from the front, folded over the chest's corners, standing just
  clear of the chest (how far is measured, so nothing comes through it), and
  running from the shoulder straight to the front of the waist. A plumb line
  from the shoulder, the voxel rule, ends on the flank of these rounder
  bodies.
- **Other calls that differ from the voxel shapes.** The skirt hangs from the
  waist line, not from below the hips, because a lap needs the cloth to lift
  off the hips. "Four panels" is one cloth all round and "two panels" is a
  front and a back cloth with the sides open; the voxel four were separate
  slabs that parted at the corners. An open front starts as a point at the
  hips instead of two units wide.
- **A slip in the game's test poses, fixed.** Mid-stride and sitting had the
  forearms written negative, like the shins, which bends the elbows backward.
  It did not show at voxel size. `runtime/poses.gd` is corrected.
- **Found in the wardrobe, not changed.** The shirt stops above the waist row
  and the trousers start below it, so "shirt and suspenders" shows a strip of
  skin at the waist. The voxel figure has the same strip. A skirt hides it
  with its waistband; trousers have none.

## 4k. Rounder heads (owner's request)

- **Why.** The first low-poly heads were blocks with bevelled edges: seven
  rounded rectangles stacked, with a flat top, straight sides and a flat
  back. Beside bodies cut from smooth clay they looked like boxes. The owner
  asked for them to be less blocky and consistent with the bodies.
- **What changed** (difficulty low; confidence medium on the look, which is
  the owner's to judge). A head is now seven rings laid out like a rounded
  form: a domed crown closed by a point, a back that is an ellipse from
  above, cheeks that turn the corner in two steps, and a jaw that tapers to
  a small flat base. 114 polygons, two fewer than before. The five ideas
  are kept: round, a rounded square (boxy), a narrow egg (oval), a wide jaw
  under a round crown (strong), a pointed chin (heart).
- **The one limit is the face.** The eyes are big: together they span 12 of
  the head's 16 units of width, and each has to lie flat. With both on one
  plane, as the spec has it, the front of the head is a flat panel however
  round the rest is. Two treatments are built, one number apart
  (`FACE_BEND`): one flat face, or each eye on its own flat patch with the
  two turned 15 degrees outward, which makes the front round as well. The
  second changes the spec's rule, so the heads were committed with the first
  and the choice was put to the owner (`lowpoly/renders/heads.png`).
  **The owner chose the second:** each eye on its own flat patch, 15
  degrees. The heads are built that way from 4l on.
- **Kept as a record:** the first rebuild's sheet, as
  `lowpoly/renders/heads_first_rebuild.png`.
- **A lesson about asking.** The choice between the two faces was put as a
  paragraph inside a longer report and the owner did not see that anything
  was being asked. A needed answer now goes at the very end, as one marked
  question (`CLAUDE.md`).

## 4l. Eyes and facial hair on the low-poly heads (owner's request)

The owner asked for the voxel faces' eye options and facial hair options on
the low-poly heads. Built in `lowpoly/faces.py` and `lowpoly/specials.py`;
shown on `lowpoly/renders/faces.png`.

- **What is carried over, unchanged** (difficulty low; confidence high,
  because it is checked against the game cell by cell). Eye sets and their
  colourways from the wardrobe file; the ten lid states, each five numbers
  for each eye; the lid colour from the skin tone; the brow colour from the
  hair; the six skin tones; stubble, chinstrap and full beard, with the
  beard taking the hair's colour and the stubble worked out from skin and
  hair. None of it is copied into Python: `lowpoly/dump_wardrobe.gd` now
  also writes the eye box, the lid states, every eye set's cells with every
  state applied, and the colours the game works out, and `faces.py` reads
  them.
- **The eye is drawn with straight edges, which is a call** (difficulty
  low; confidence medium on the look, which is the owner's to judge). On a
  voxel face a lid that tilts is a staircase and the eye's rounded outline
  is cut corners. Drawn as squares on a low-poly head those read as a
  low-resolution texture. So a one-cell step in the outline becomes a
  diagonal, and a tilted lid becomes one sloped edge with the brow as a bar
  along it. Drawing the game's cells as squares is also built ("cells"), so
  the two can be compared on the sheet, row 5.
- **How the straight edges are kept honest.** The eased eye is checked
  against the game's cells: at the middle of every cell it must show what
  the game shows there, and nothing may be drawn at the outer part of a cell
  the game leaves bare. Only the columns where a tilted lid's edge runs
  through the middle of the cells are left out, since there the staircase
  and the slope cannot agree.
- **A pair of eyes is 6 to 18 polygons.** Each eye is worked out strip by
  strip and the strips are joined wherever the result is still a convex
  polygon. The polygons of one eye do not overlap, so they all lie at one
  small height off the face (0.04 units).
- **Facial hair claims the head's own polygons.** The voxel generator found
  cells by looking at the head (its frontmost cell in each column, its
  outermost on each side). Here the head's polygons are tagged with where
  they are (which ring, which place round it), and facial hair marks the
  ones it wants: stubble as a recolour, the chinstrap with one step of bulk.
  The ordinary garment rules then do the work, so a raised beard gets its
  edges the same way a sleeve gets its hem. The head is cut once more, at
  the top of the sideburns, so that a sideburn has an edge to stop at.
- **Ears stay skin under hair.** The short crop's regions include the ears'
  polygons. Coloured and lifted as hair they read as lumps on the side of
  the head, so region coverage never claims an ear.
- **Not ported: the long beard.** It is a drawn (anchored) shape, a relief
  of voxels hung on the chin. Drawn shapes are not rebuilt yet, and what a
  hand-drawn shape should be on a low-poly figure is its own question.
- **Hair is a stand-in.** The short crop is put on by the ordinary region
  rules, which is enough to show brows and beards following its colour. It
  stands off the whole back of the head like a cap. Hair itself is not
  rebuilt.
- **Things the sheet shows that are worth a look.** A chinstrap stands one
  whole step of bulk off the jaw, as the voxel one does, and reads heavy. A
  sideburn stops one row short of the top of the eye, as in the game, which
  leaves a strip of bare temple under the crop's edge. With a tilted lid the
  brow's high end is cut square where it reaches the top of the brow row.
- **For Godot later.** The eyes here are separate flat polygons just off the
  face. In the engine they should be cut into the face's polygons, or drawn
  with a depth offset, so that they cannot flicker against the face.

## 4m. Rounded oval eyes, and a mouth (owner's direction)

Shown the eyes of 4l, the owner answered the question about their edges with
a third way: **the eyes should be rounded ovals, of roughly the same
footprint, and slightly smaller now that voxels do not limit them, which
leaves room for a small mouth.** The sheet of 4l is kept as
`lowpoly/renders/faces_first_port.png`.

- **The eye is an oval, and still the game's eye** (difficulty low to
  medium; confidence high that the lid states are right, medium on the look,
  which is the owner's to judge). The oval fills the box that the eye set's
  drawing fills and its pupil lies over the drawing's pupil cells, so the
  wardrobe's eye set still says how big the eye is and where it looks. The
  lid states are untouched: a lid cuts the oval straight across, the brow is
  a bar along the upper lid. The check of 4l carries over nearly unchanged:
  at the middle of every cell the oval eye shows what the game's cells show.
  That it passes is not luck: the standard eye is an oval drawn in cells.
- **What "slightly smaller" is.** The whole eye box, brow row and all, goes
  on the head at 0.9 of its voxel size (4.5 by 5.4 instead of 5 by 6), from
  the same top line, so all the room it gives up is under the eyes. Lid
  rows shrink with it. The sheet shows 1.0, 0.9 and 0.8 for the owner to
  choose from.
- **The white is cut round the pupil, not laid under it.** A convex shape
  with a convex hole is cut into one sliver for each side of the hole. That
  keeps the rule of 4l (the polygons of an eye tile it, so they lie at one
  height), at the price of more polygons: 6 to 32 for a pair of eyes, 36 to
  92 triangles, with an outline of 20 corners and a pupil of 12. Laying the
  pupil over the white would be about a third fewer triangles and need two
  heights. Both are easy; in Godot the eyes may be better drawn by a shader
  or a small texture than by polygons at all, which is a question for that
  port.
- **A tilted brow is one straight bar now.** The game stops a brow at the
  top of the brow row, which gave the "sad" brow a square end. Here it
  carries on straight, up to half a row higher. The ten states never go
  further, so it agrees with the game everywhere the check looks.
- **The mouth is a first pass** (difficulty low; confidence low to medium
  on the look). The voxel faces have none, so nothing could be carried
  over: its shapes are a small table in `faces.py` (a line that is
  straight, curved up or curved down, and a small open oval), its colour is
  the skin's darkened and a little toward red, and it is lit like the skin.
  It lies across the middle of the face, where the two eye patches meet, so
  it is built in two halves. **Where it can go is limited:** the flat part
  of the face ends at the bottom of the old eye box, and under that the jaw
  slopes away, where a mouth would be hidden from a camera that looks down.
  So it sits level with the bottoms of the eyes, between them. More room
  would need the eyes moved up, or the flat part of the face made taller.
- **Not done:** mouths in the game's data and in the editor, and a rule
  for which mouth goes with which lid state.

## 4n. The face laid out again: lashes, eyebrows, and room for facial hair (owner's direction)

Shown the oval eyes of 4m, the owner chose size B (0.9) and asked for four
things: the eyes a little higher, vertically centred; the mouth a tiny bit
lower, to make proper room for a beard and a moustache; the thick line on
the eyelid made thin, to read as lashes, and kept inside the eye; and
eyebrows added. The owner named the cause: the thick bar, and its double
duty as lashes and eyebrow, are artifacts of voxel art.

- **"Vertically centred" was read as: centred on the flat part of the
  face** (difficulty low; confidence medium that this is what was meant).
  The flat part runs from height 29 to 37, so the eye's middle went from
  32.3 to 33. Centred on the whole head (34) was the other reading. It
  would put the top of the eye at 36.7, with no flat room left for an
  eyebrow under the hairline at 37, so it was not built. Said plainly to
  the owner so that it can be corrected.
- **The mouth is as low as the head allows.** It went from 29.7 to 29.4.
  Its lowest point is now a quarter of a unit above the bottom of the flat
  part of the face. Lower needs the heads changed (a taller flat part, so a
  shorter jaw), which the owner has not asked for. To fit, a smile now
  turns its corners up from the line instead of hanging under it, and a
  frown stands on its corners.
- **The lash line is "the top edge of the open eye"** (difficulty low to
  medium; confidence medium on the look). One rule covers every lid state:
  take everything of the eye under the upper lid's edge, slide a copy of it
  down by the lash's thickness, and what the copy leaves uncovered is the
  lash line. Under a lowered lid that is a thin band along the lid, with
  thin tails down the sides to the eye's corners; on a wide open eye it is
  a crescent round the top of the oval; when the lids meet it is the line
  of the closed eye. It cannot leave the eye, because it is cut from it.
  It is a little thicker toward the outer corner, which is what makes a
  line read as lashes. Its colour is the eye set's "line" colour, a role
  the wardrobe's eye sets already had and the standard eye never used.
- **Eyebrows had to be given a way to move.** On the voxel face the brow
  is the lid's edge, so the lid states move it for free. A brow of its own
  that followed the lid one for one would end up in the middle of a closed
  eye. So it follows only a little: up 0.3 of a row for a wide open eye,
  down 0.3 once the lid is half way down, and with 0.55 of the lid's tilt,
  hanging from its higher end so that it never climbs into the hairline.
  The numbers were chosen by eye. No new data: the game's ten states are
  untouched, and a check still holds the lids and the pupil to the game's
  cells.
- **Dropped before drawing it: a brow tilted as much as the lid.** Worked
  through for "sad", it lands on the lid's own edge, which is where the old
  bar was.
- **Tried and kept: a low arch and a taper.** A straight thin bar read as a
  second lash line. Thicker toward the nose, with the outer third falling
  away, reads as an eyebrow.
- **The cost.** A pair of eyes with brows is now 10 to 50 polygons, 52 to
  132 triangles: about a tenth of a dressed figure. Most are slivers, of the
  white round the pupil and of the lash line round the top of the eye,
  which is the price of the rule that a face's polygons tile and lie at
  one height. For Godot, a small texture or a shader on the two face
  patches would draw the same face for nothing; worth weighing there.
- **Not done, on purpose:** the beard and moustache. The face now has the
  room; what they should be is to be talked through with the owner first.

## 4o. Beards and moustaches for the new face (owner's go-ahead)

With the face laid out again (4n) the owner said to go on to the facial
hair. The proposal put to them first: a moustache as a flat shape like the
eyebrows; stubble and chinstrap kept; a full beard that comes up the cheeks
to the mouth and joins the moustache; beard and moustache chosen
separately. Built as a set of options to choose from
(`lowpoly/renders/facial_hair.png`), in `lowpoly/facial_hair.py`.

- **A beard is cut into the head's own polygons** (difficulty medium;
  confidence high that the mesh is sound, medium on the look). The beard's
  upper edge is a line: it starts beside the mouth, runs out under the eye,
  and climbs across the cheek to the sideburn. Each polygon the line
  crosses is cut along it and the part under it is recoloured. After
  cutting, every polygon is given the corners its neighbours have on its
  edges, so that edges match again; a check holds the head to one closed
  surface on all five heads. So a beard follows each head's own shape with
  no drawing per head.
- **Tried first and dropped: a beard as a shelf.** Lifting the jaw by a
  step of bulk, as a garment is lifted, left a ledge under the mouth that
  caught the light and read as a collar. A full beard and a goatee now
  grow out of the face: no thickness at the top of the jaw, all of it one
  ring lower. For this a claim on a polygon may carry a fade (two heights);
  `dress.py` moves each corner by its own share. A chinstrap keeps its even
  thickness, since a strap is a shelf.
- **Tried first and dropped: the beard beside the mouth as flat shapes laid
  on the face.** They left a light seam where they met the cheek's own
  polygons. That part is now cut into the face's polygons like the rest;
  only the moustache and the mouth are laid on.
- **A window round the mouth.** A full beard stops 1.2 units either side of
  the middle and comes up to just under the mouth. A mouth drawn straight
  onto dark hair cannot be seen.
- **Moustaches hang over the mouth.** A moustache is cut out of the mouth,
  so the two tile. Under one, a smile or a frown shows only its lower edge.
- **Sideburns meet the hair now.** With hair on they run up to the hair's
  edge; on a bald head they stop at the top of the ear. The voxel sideburn
  stopped below the top of the eye either way, which left bare temple under
  the hair (noted in 4l).
- **Thickness is offered three ways** (flat; half a step, as built; a whole
  step): the beard's body is the one place where the owner's earlier remark
  about heaviness applies, and it is one number.
- **Earlier decisions touched** (`SPEC.md` 5.1, made on voxel mock-ups):
  the goatee, the moustache, a volumetric full beard and flat sideburns
  were turned down there. The moustache is now asked for. The goatee, a
  beard with thickness, and the full beard's flat sideburns are put back as
  options because the reasons were about voxel resolution; they are flagged
  to the owner as offered, not decided.
- **Not in the game yet.** The goatee and the moustaches exist only here:
  `dress.py` adds them to the wardrobe it reads, the moustache as a slot of
  its own. The game's wardrobe file, its generator and the editor do not
  know them.
- **Cost.** A moustache is 2 to 6 polygons. A beard adds 8 to 44 to the
  figure, a full beard 12 to 18.

## 4p. Facial hair as four parts and one length (owner's design)

Shown the beards and moustaches of 4o, the owner described how facial hair
should work instead. Thickness the way clothes do it: stubble first,
semi-transparent and no thicker than the face (like skin-tight clothes);
then fully opaque and still flush; then growing out from the face. Shape as
toggles: moustache, sideburns, goatee, and the area between the sideburns
and the goatee, each on or off. A full beard has every part on; an Amish
beard everything but the moustache. One length setting for all the parts,
so as not to be too fine-grained. The styles of 4o (the four moustache
shapes, the separate moustache slot, the fade) are gone.

- **The part between the sideburns and the goatee is called "cheeks"**
  here: the jaw, the lower cheeks and the face beside the mouth.
- **"Semi-transparent" is the game's own stubble colour.** Stubble lies on
  the skin itself, so a see-through stubble would show nothing but the
  skin under it: the result is one blended colour either way. The game's
  stubble colour is that blend, made to stay darker than the skin even
  under fair hair. Confidence high that it looks the same; medium that it
  is what the owner meant.
- **The lengths are four**: stubble, short, medium (half a step of bulk
  out) and long (a whole step). Grown-out facial hair gets its edges from
  the same hem rule as clothes. The fade of 4o (no thickness at the top of
  the jaw) went: with every part grown out together there is no shelf to
  hide, and the owner asked for the clothes' way.
- **Every part is cut into the head's own polygons** (difficulty medium;
  confidence high on the mesh, which is checked: all 15 ways of putting the
  parts together, on all five heads, bald and with hair, leave the head one
  closed surface). Each part is a few planes that cut its edge through
  the polygons it may cover. Cutting with whole planes leaves slivers, so
  pieces of one polygon with the same colour are joined back afterwards
  where the result is convex, and corners on straight runs are dropped
  unless a neighbour needs them. That halved the polygons a beard adds.
- **A bug the checks caught while building that step:** two pieces sharing
  a boundary that was split at a midpoint were joined into a polygon with a
  doubled corner, which left a gap in the head. Pieces are now tidied
  before they are joined, and only pairs sharing exactly one edge join.
- **Every polygon now says which worn item made it** (`by` in the dressed
  polygons). The checks needed it: by colour alone the hair's own fringe
  edge was taken for beard.
- **The sideburn comes down to about the bottom of the ear**, and the
  cheeks' top line meets its foot, so that the two join cleanly whichever
  is on alone.
- **One length for all parts has a cost**: a moustache or sideburns on
  their own, grown out a whole step, stand off the face as much as a full
  beard does, and read chunky. Kept as asked; noted for the owner.
- **The game's three items** are read as parts and a length (stubble:
  every part at stubble; chinstrap: all but the moustache at medium, as
  the narrow strap is not a part; full beard: every part at medium). The
  game's data, generator and editor need the toggles and the length when
  facial hair is ported to Godot.
- **Cost.** A full beard adds about 22 polygons (66 triangles) flush and
  about 56 (134 triangles) grown out, on a bald head; less with hair on.

## 5. Still open, for the owner

Since the move to low-poly (4i), the open questions for that work are listed
in `lowpoly/README.md`. The items below come from the voxel system. Items 6
and 7 are overtaken by the move: baked lighting becomes the choice between
flat and smooth shading, and hoods wait for the special shapes to be rebuilt
as polygons.

Carried from `SPEC.md` section 13, plus what building raised:

1. **Region count**: settled at 32 a side (owner's call). See 4b problem 1
   for why faces might want finer bands.
2. **Authoring canvas size.** The spec recommends 32 × 32 × 48; nothing here
   assumes a canvas yet, because the reference box is not used as a clip.
3. **Cloth panels: rules or physics?** In the voxel system: rule-driven, with
   the front panel following the more forward thigh at 80 per cent of its
   swing (`Poses.PANEL_FOLLOW`). For low-poly a third way is built and
   waiting for the owner's judgement: cloth laid afresh for every pose (4j).
4. **Re-voxelised animation.** Not implemented; it is a rendering choice that
   does not change the data, exactly as the spec says.
5. **Eye colour** now lives in eye-set colourways (4b). Which colourway a
   given character uses -- and its skin tone, lid state and brow colour -- is
   the game's to remember, not the editor's.
6. **Baked lighting: keep it?** The owner is not sure they want baked shades
   at all. Compared as stills: as now; without the edge highlight; no baked
   shades (true colours, form still reads in 3D from the per-face dimming,
   but a front-on sprite is flat colour blocks); and nothing baked with a
   real engine light (form and shadows, shadow-map glitches at voxel size).
   Left open on purpose. Recommendation recorded, not decided: make it a
   setting on the assembler, since the game assembles characters anyway.
7. **Hoods are on hold.** The current hood is a skin-tight shell and does
   not read as a hood. The owner chose: generate a looser hood, then
   hand-tune it. That needs a new hand-editable 3D piece (the drawn shape is
   a thin relief and cannot hold a hood's volume). Not started.
