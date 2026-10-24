# Bird feeder preview

`BirdFeederModel` owns the tray height, perch and seed positions.
`FeederBirdNode` is a separate sparrow model with feet, folded/flight wings,
a neck pivot, bill, lower jaw and a seed carried in the bill. The fly-over
bird uses its existing model.

`FeederVisit.pose(at:)` describes one 12.4-second visit: approach, landing,
five separated bites with glances and blinks, a turning hop, and takeoff.
At each bite the head position is solved from the bill tip to the chosen
seed. The feet remain fixed during feeding. The grain leaves the tray at
contact, travels with the bill, then disappears after the small swallowing
motion. Seeds reset between visits; this is ambient scenery, not inventory.

Visits pause with the scene, and are disabled at night, during precipitation
or with Reduce Motion. Restarting does not create duplicate visitors. The
whole animation is local to the feeder, so moving/rotating it keeps contact.

`FeederPreview.swift` follows the separate simulator-bundle setup used by
`DogFeedingPreview.swift` and `StormWeatherPreview.swift`: link the Debug
`Pilire` module/dylib, include `Assets.car` and `GLTFKit2.framework`, and use
an independent bundle identifier. It never opens the player's saved town.

The harness saves native screenshots and `result.json` in its own Documents
folder. It checks all five bill/seed contacts at all four rotations, pickup
and swallowing, 1,241 trajectory samples, transformed bird geometry against
the roof, foot height, repeat-start behavior, and weather/night transitions.
Pass `--demo` to skip the checks and loop the close-up animation.
