# tools/art: HULLDOWN brand & icon pipeline

Everything under `assets/brand/` and `assets/icons/` is **generated from code** in this folder.
The SVGs are committed so engineers and the asset uploader never need to run Python, but they are
build outputs: edit the generator, not the SVG. The art direction these tools implement lives in
[`docs/design/brand-art.md`](../../docs/design/brand-art.md).

| Script | What it does | Needs |
|---|---|---|
| `generate_svgs.py` | Rebuilds every brand/icon SVG, `assets/brand/tokens.json` and `assets/icons/INDEX.md`. `--check` fails on size or structure violations, and on any icon SVG that is unlisted in INDEX.md or no longer produced (stale). | `shapely` |
| `render_svgs.py` | Renders every `assets/**/*.svg` to PNG and builds labelled contact sheets for review (paged for big groups). | `cairosvg`, `Pillow`, `numpy` |
| `check_palette.py` | WCAG contrast checks for UI tokens, colour-blind separation checks for the team schemes, and a palette sheet. | `numpy`, `Pillow` |

```bash
pip install shapely                         # only needed to regenerate the SVGs
python3 tools/art/generate_svgs.py --check  # write assets/**.svg and tokens.json, validate
python3 tools/art/render_svgs.py            # build/png/**@{64,128,256}.png, brand also @512/@1024
python3 tools/art/check_palette.py          # contrast + CVD report, build/png/contact_sheet_palette.png
```

Useful flags for `render_svgs.py`: `--only <group>` (`brand`, `factions`, `classes`, `minimap`,
`tiers`, `ranks`, `currency`, `ammo`, `modules`, `crew`, `consumables`, `equipment`, `ui`, `battle`,
`achievements`, `missions`, `markers`), `--no-sheets`, `--sheets-only`, `--page N`, `--assets`, `--out`.

## Outputs

```
build/png/<path under assets>@<size>.png    size = longest edge in px, aspect ratio preserved
build/png/contact_sheet_<group>.png         dark panel on top, light panel below. Each asset is shown
                                            at review size plus true 48/32/24/16 px renders (wide
                                            assets: 128/96/64). White tintable art (title contains
                                            "tint") also shows ImageColor3-style tints: team colours
                                            (default + deuteranopia) for minimap/battle/markers, UI
                                            tokens for ui/.
build/png/contact_sheet_<group>_p<N>.png    the same, paged (18 assets per page, --page) for groups
                                            bigger than one page, so every page reviews at 1:1.
build/png/contact_sheet_palette.png         every UI token, plus each team scheme under simulated
                                            protanopia/deuteranopia/tritanopia
```

`build/` is git-ignored. Review the contact sheets after every change. The rules in the brand
guide's icon checklist are the acceptance criteria.

## Code layout

```
hdart/tokens.py        colour tokens (UI, team + CVD schemes, factions, ammo, equipment) and icon
                       materials (highlight/base/shade)
hdart/geom.py          shapely helpers: chamfered boxes, gears, chevrons, arcs, bevel facets, SVG path output
hdart/svgdoc.py        tiny SVG writer + the shared rendering grammar (keyline, plate, inlay, engrave)
hdart/glyphs.py        "HULLDOWN Stencil": constructed letterforms (A C D E G H I L M N O R U V W X ·)
hdart/proj.py          the fixed 3/4 object camera used by physical-object icons
hdart/solid.py         faceted-solid renderer on that camera: extrude / prism / box / revolve / cylinder,
                       analytic band shading for curved surfaces, planar decals (plane_map)
hdart/kit.py           shared 2D kit: symbol() / glyph() styles, gold rim (special), crack chip and
                       break (damage states), arrows, arcs, wrench, flame, eye, helmet, person, shell
hdart/registry.py      icon registry (group, key, title, intended use, canvas, tint) -> files + INDEX.md
hdart/brand.py         turret silhouette, ridge, emblem, wordmark and every logo lockup
hdart/icons.py         factions, classes, minimap glyphs, tiers, ranks, currencies
hdart/ammo.py          shells (revolve profiles), special rounds
hdart/modules.py       damage-panel module glyphs x 3 states, fire, repair
hdart/crew.py          crew pictograms + injured
hdart/consumables.py   consumables (3/4 objects)
hdart/equipment.py     equipment items (3/4), category tiles, grade overlays, examples
hdart/ui.py            white UI glyphs
hdart/battle.py        minimap markers + pings, command wheel, hit results, status, reticle pieces
hdart/achievements.py  rarity frames, category emblems, mastery badges, examples
hdart/missions.py      mission icons
hdart/markers.py       BillboardGui marker frames, target lock
```

### The rendering grammar (do not bypass it)

* `Doc.keyline(shape)` draws the 2 px ink outline. Every silhouette gets one.
* `Doc.plate(shape, material)` splits the shape into bevel facets lit from the top-left: lit edges
  get the material's highlight, unlit edges its shade, and the face a subtle base gradient.
* `Doc.inlay(motif, material, clip)` is a raised detail. It casts a 1.2 px ink shadow to the
  lower-right, then gets its own small bevel.
* `Doc.engrave(motif, plate_material, clip)` is a cut-in detail: a dark recess with a lit lip on the
  lower-right.
* `icons.fitparts()` and `icons.check_safe()` keep each silhouette and its keyline inside the
  4 px safe margin. The generator raises an error if a shape leaves it.

### Adding an icon

1. Write a draw function in the group's module (`hdart/<group>.py`). Build the shapes on the 64
   grid, keep them in the live area (`kit.check` / `kit.shrink_to`), then draw them with keyline,
   plate, inlay and engrave (or `kit.glyph` for white tintable glyphs, or a `solid.Scene` for a 3/4
   object), using materials from `tokens.MATERIALS`. Never use raw hex values.
2. Register it with `registry.add(group, key, title, use, draw, ...)` in that module's
   `_register()`. The generator writes `assets/icons/<group>/<key>.svg` and the INDEX.md row.
   (The original brand sets in `icons.py` are still wired directly in `generate_svgs.build()`.)
3. Run `generate_svgs.py --check` and then `render_svgs.py --only <group>`, and inspect the sheet.
   At 32 px the icon must read as its silhouette alone, and it must hold up on both the dark and
   the light panel.
4. Go through the "New icon checklist" in the brand guide.

## Constraints enforced by `--check`

* `viewBox` present. Only `<path>`, gradients and `<title>` are used: no `<text>`, `<image>`,
  `<use>`, `<style>`, scripts or external references (`href` or a non-local `url()`).
* Each file is under 40 KB. Current files are 0.4–16 KB.
* Lettering is built from vector paths (`hdart/glyphs.py`). No font files are involved, so the
  output is identical on every machine.

## Roblox import notes

* Upload the PNG renders, not the SVGs. Use `@128` for icons displayed at 64 px or smaller, and
  `@256` for anything larger. For the brand, use `@1024` for loading screens and `@512` for the
  garage header.
* Minimap glyphs (`assets/icons/minimap/*`) and every other white asset (INDEX.md "Tint" column:
  `ui/`, battle markers, pings, commands, reticle pieces, marker frames) are white with an ink
  keyline. Tint them at runtime with `ImageLabel.ImageColor3`, using the team colour of the
  player's active CVD scheme or the UI token named in INDEX.md. Never upload pre-tinted copies.
* Overlays (equipment `grade_*`, achievement `frame_*` + `emblem_*`) are separate images layered at
  the same size; `examples/` folders are previews and need not be uploaded.
* Leave `ResampleMode` at `Default` for icons. Only pixel-snapped HUD glyphs at exactly 1:1 may use
  `Pixelated`.
