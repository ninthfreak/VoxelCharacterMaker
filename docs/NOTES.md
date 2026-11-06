# Build notes

Decisions taken while building, discrepancies found in the hand-off package,
and what is still open. `SPEC.md` remains the design record; this is the log of
what happened when it met code.

Difficulty and confidence are rated explicitly, because a flat narrative hides
which parts are solid and which are guesses.

---

## 1. Verification status

**Everything compiles and the acceptance suite is green: 1343 checks, 0 failures.**

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
   (z 32-36) overlaps the eye rows (z 30-34), and the lower band (z 28-31)
   holds the bottom eye rows. So hair can only use crown and back regions
   without covering the eyes, and facial hair *has* to be a drawn shape. It
   works, but it means two ways to author the same thing. Fix: finer face
   bands in the region map -- moderate work, and it changes the 32-a-side
   count the owner settled, so it is the owner's call. Confidence the problem
   is real: high.
2. **A moustache has two rows to live in.** Between the eyes and the chin
   there are only z 28-29, and there is no mouth or nose. The test moustache
   reads as a smudge. This is a property of the head design (SPEC 4), not the
   editor; a taller lower face or a mouth row would fix it. High confidence,
   look decision.
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
6. **Skirt panels and trousers.** The deferred thigh-gap problem touches skirts
   too: a long skirt over trousers is two layers of cloth panel. Still
   deferred, as agreed.

### Opportunities

1. **A character record.** Preview selections are not saved. Saving them as a
   "character" (body, head, eye set + colour, hair + colour, facial hair,
   outfit) would give the game exactly what it needs to load an NPC, and is a
   small addition. Recommended next, if characters are wanted soon.
2. **The drawn shape is general.** Collars, pauldrons, horns, ears, crowns,
   belt pouches can all be drawn shapes at an anchor, which may mean few new
   generator types are ever needed.
3. **More anchors are cheap.** Each is a few lines (a body part, a band and a
   direction). Knees, elbows and the small of the back would open up knee
   pads, elbow patches and quivers.
4. **Specials on features.** Because features are items, hair can already use
   specials: the ponytail is a rigid shape at the nape. Long braids or a bun
   come for free the same way.

## 5. Still open, for the owner

Carried from `SPEC.md` section 13, plus what building raised:

1. **Region count**: settled at 32 a side (owner's call). See 4b problem 1
   for why faces might want finer bands.
2. **Authoring canvas size.** The spec recommends 32 × 32 × 48; nothing here
   assumes a canvas yet, because the reference box is not used as a clip.
3. **Cloth panels: rules or physics?** Currently rule-driven, with the front
   panel following the more forward thigh at 80 per cent of its swing
   (`Poses.PANEL_FOLLOW`). The number is a guess that looked reasonable on
   paper; it wants eyes on it.
4. **Re-voxelised animation.** Not implemented; it is a rendering choice that
   does not change the data, exactly as the spec says.
5. **Eye colour** now lives in eye-set colourways (4b). A character record
   would still be where a character's chosen colourway is remembered.
