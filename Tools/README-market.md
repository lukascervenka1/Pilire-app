# Market and merchant

`MerchantPortrait` uses the transparent portrait of an original Blender model.
The editable source is `Art/Merchant/matej.blend`; `Tools/author_merchant.py`
recreates the model and its portrait in the town's flat-shaded low-poly style,
lit like the town. A softly fading path and meadow ground the merchant in the world.
The image is bundled and reused, so reading the market does not run
another live 3D scene.

`MarketView` has Requests and Supplies sections. Requests show the exchange,
the exact shortfall, a completed state and daily progress. Supplies retains
buying, selling, quantity selection and material exchange. Both use the same
wallet and daily price snapshot. Text is supplied in Czech, Slovak and English.

Requests are seeded by local calendar day and remain stable during that day.
Each visit uses distinct transaction types. Each type has twelve stories,
walked in a scrambled order so none returns within twelve days. The first two offers remain the same when a market hall adds a third.
The screen refreshes on calendar-day/time-zone changes and foregrounding.
An offer from yesterday cannot be accepted after midnight.

Run `zsh Tests/check-market.sh` for 365-day stability/variety checks, market-hall
continuity, insufficient funds, claim-once behaviour and the midnight boundary.

`MarketPreview.swift` is a standalone simulator harness. Link it to the Debug
`Pilire` module/dylib in a separate bundle, including `Assets.car` and
`GLTFKit2.framework`. It uses an in-memory SwiftData container and its own
defaults domain, and never reads the player's saved town. It saves native
screenshots for a 375-point phone, landscape, tablet, the supplies counter and
the largest Dynamic Type size. `--settled` shows a completed visit;
`--english` switches its test UI to English.
