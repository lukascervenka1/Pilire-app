# Matěj, travelling merchant

Original model authored for Pilíře in Blender. Sage wool coat, warm silver beard,
terracotta scarf, a leather satchel, open ledger and an oak handcart.
The hands grip the ledger and cart; the wheels have open spokes and iron rims.
He stands on a path with grass, a low hedge and a few stones, in the town's
own grass and path colours. The road and meadow fade together into the market
card. Boots and wheels meet the path and cast real shadows onto it.

He follows the town's art direction, after the low-poly and isometric rules of
the blender-skills pack: flat shading, no subdivision, single-segment bevels,
low segment counts, no stitching or seams, flat colours, an orthographic camera
and the town's light rig (warm sun from camera-left, cool ambient fill). The
eyes are two open dots: lids and dark rims read as a squint at card size.

- `matej.blend` — editable character, handcart, named materials, portrait camera
  and studio lighting. Front is −Y, up is +Z. The saved modelling view
  opens with the material colours and a useful view of the character.
- `matej.glb` — reusable model export, of the character and cart, without studio lighting or the roadside scenery.
- `../../Pilire/Assets.xcassets/MerchantMatej.imageset/merchant-matej.png` — final
  transparent portrait used by the app, 900 px tall. The camera is fitted to
  the visible geometry, so there is no empty band around the figure.

Recreate the model and final portrait from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --threads 8 --python Tools/author_merchant.py
```

Add `-- --preview` to write a quick `matej-preview.png`, 640 px tall, with fewer samples. CPU rendering is
used by default; `-- --metal` opts into the Metal device where it works reliably.
The first Metal attempt stalled on the development M2 Pro, so the verified output
uses Cycles on the CPU with denoising. No external textures or add-ons are needed.

Only the finished PNG is bundled in the app. The editable scene and GLB stay in
`Art/`, and no live 3D renderer runs while the player reads the market.
