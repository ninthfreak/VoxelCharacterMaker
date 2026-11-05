# Build notes

Decisions taken while building, discrepancies found in the hand-off package,
and what is still open. `SPEC.md` remains the design record; this is the log of
what happened when it met code.

Difficulty and confidence are rated explicitly, because a flat narrative hides
which parts are solid and which are guesses.

---

## 1. The one thing that is NOT verified yet

**No Godot binary could be run in the session that wrote this code.** The engine
was downloaded successfully (4.7.2 stable, from the official GitHub release),
but the sandbox refused to execute a freshly downloaded binary.

So: the whole GDScript side has never been compiled, let alone rendered.

What that does and does not mean:

- **Verified, on the real assets, by running code:** every structural claim in
  `SPEC.md` section 12 about the assets (all six voxel counts, every pivot x in
  the section 3.2 table, mirror symmetry, one connected piece per body and per
  part, no edge-only contacts, all 11 expressions fitting all 5 heads,
  `look_left` mirroring to `look_right`); and the bulk-growth algorithm's
  behaviour on all six bodies (bulk 0 adds nothing, bulk 1 generates with no
  gaps, soft never exceeds hard, thicker bulk adds more, nothing grows into the
  body or below z0, a mirrored definition yields a mirror-symmetric garment).
- **Verified mechanically, but not by the compiler:** all 345 cross-class
  references in the 36 GDScript files resolve to a declared member; indentation
  is tab-only throughout; brackets balance in every file.
- **Not verified at all:** that the project opens, that any script compiles,
  that the editor UI lays out sensibly, and that the figure renders right side
  out.

**First thing to do with a working Godot:**

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Expect to spend a pass fixing compile errors. Writing ~4,000 lines of GDScript
without a compiler and claiming it builds first time would be dishonest.
Confidence that the *logic* is right: high. Confidence that it *compiles
unchanged*: low — call it 30 per cent, with the likely faults being API details
(exact enum names, a signal signature, a method that moved between 4.x
versions) rather than design.

**The single most likely visual bug: inverted winding.** Godot treats clockwise
triangles as front-facing, which is the opposite of the usual OpenGL
convention. `core/mesher.gd` emits clockwise and `tests/test_mesher.gd` asserts
that explicitly. If the figure renders inside-out — you see the far surface —
flip the two `_tri` calls in `Mesher.build_part` and the expectation in that
test. One line each, and nothing else depends on it.

---

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

In the spec's own build order (section 11), steps 1–5 are done and 6–8 are not:

- **Face editor** (step 6). `FaceDef` already reads and regenerates box cells
  and validates stored voxels against them, so the data side is ready; what is
  missing is the grid UI.
- **Export: .vox, STL, OBJ** (step 7). The STL "edge-contact fix" needed for a
  watertight export is not written. Note that
  `TestReport.edge_only_contacts()` already detects the condition, so the test
  for it exists before the feature does.
- **Body editor** (step 8).
- **Special types beyond hood and skirt.** The generator registry describes its
  own parameters, so adding capes, togas, standing collars or pauldrons needs
  one file and one line in `SpecialItem.types()` — no editor changes.
- **Decals** — deferred in the spec, and still deferred.

---

## 5. Still open, for the owner

Carried from `SPEC.md` section 13, plus what building raised:

1. **The 30-versus-32 region count** above. This one actually blocks nothing but
   is worth settling before much wardrobe authoring happens.
2. **Authoring canvas size.** The spec recommends 32 × 32 × 48; nothing here
   assumes a canvas yet, because the reference box is not used as a clip.
3. **Cloth panels: rules or physics?** Currently rule-driven, with the front
   panel following the more forward thigh at 80 per cent of its swing
   (`Poses.PANEL_FOLLOW`). The number is a guess that looked reasonable on
   paper; it wants eyes on it.
4. **Re-voxelised animation.** Not implemented; it is a rendering choice that
   does not change the data, exactly as the spec says.
5. **Eye colour is per-figure, not per-character-record.** It is currently a
   field on the assembler request with a sensible default. If characters will
   each have their own, it belongs in whatever a "character" record turns out
   to be — which does not exist yet.
