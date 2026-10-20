# Dog companion animation authoring

Run from the Xcode project directory with Python 3 and NumPy:

```sh
python3 Tools/author_dog_companion.py
```

This appends seven skeletal clips to `shiba.gltf` and `husky.gltf`:

| Clip | Seconds | Playback |
| --- | ---: | --- |
| Companion_LieDown | 2.2 | Lower chest and fold legs, then lower head |
| Companion_Sleep | 4.8 | Seamless breathing loop |
| Companion_Rise | 1.8 | Raise head, then restore support on all four paws |
| Companion_Pet | 2.4 | Tail response and a small head turn |
| Companion_Sniff | 3.2 | Pause to investigate with the nose |
| Companion_Eat | 6.4 | Four planted paws, lower the muzzle to the bowl, chew, then raise the head |
| Companion_Fed | 2.8 | Wag the tail and tilt the head toward the player |

Original geometry, skins, materials, bind transforms and clips are preserved.
Generated data uses a separate embedded buffer. `extras.companionAuthoring`
records the original array lengths so rerunning replaces, rather than duplicates,
our clips. Constant tracks only store two endpoints.

The rigs use separate IK paw bones. Sagittal limb IK follows these paws as they
slide forward along the ground. The chest and haunches lower without scaling the
animal. `Neck3` owns the skull and ear roots; `Head` controls only the muzzle.
Counter-rotating only `Head` would fold the ears through the forehead.

The authoring script checks skinned geometry for floor penetration at every
sampled frame. Runtime sequencing lives in `AnimalNode` in `Animals.swift`:
walk into bed → lie down → breathe → rise → resume behavior. Generation tokens
invalidate queued action completions after commands, carrying or rig replacement.
The kennel remains reserved until standing has finished. Reduce Motion omits the
extra sniff/tail gestures, while retaining the necessary posture transitions.

## Feeding

`AnimalFeeding.swift` defines the shared clip timing and a reservation for one
reachable bowl. `TownScene` finds the nearest free bowl using the navigation
grid and honors all four doghouse rotations. Refilling wakes a sleeping pet;
a walking pet changes course at its next tile boundary.

The pet stands outside the bowl with its muzzle over the food. Nine timed bites
gradually hide the granules. Only the last bite persists consumption of that
specific bowl. An interrupted meal restores the visible portions and leaves
the stored food available; a failed save does the same. Reservations prevent
two pets eating from the same bowl. The pet leaves the eating spot before
releasing its reservation, faces the camera, wags and shows an affection heart.
Reduce Motion keeps the eating posture and affection heart with a calm idle
instead of the extra tail/head gesture.

Verify the exported clips' skinned geometry, planted paws, muzzle placement,
tail movement and return to standing:

```sh
python3 Tools/check_dog_feeding.py
```

`DogFeedingPreview.swift` is a standalone simulator fixture linked against a
Debug build with `@testable import Pilire`. Bundle the app's debug dylib,
GLTFKit2 framework, Assets.car and the two dog assets in a separate preview
app. It uses an in-memory SwiftData container and never opens the player's
town. Launch arguments: `--case=complete`, `carry`, `remove`, `save-failure`,
`two-dogs` or `sleeping`; `--rotation=0` through `3`; optionally `--husky`.
The fixture writes `Documents/feeding-result.json` with its verdict, bowl
identity checks, visible portion counts and maximum simultaneous eaters.

## Navigation to a kennel

`AnimalNavigation.swift` searches dry, unoccupied cardinal grid cells. The scene
picks the nearest reachable free doorway, honoring all four kennel rotations.
The pet reserves that kennel before travelling and replans at each tile. A manual
visit lasts 12–18 seconds before the pet stands and leaves through the same door.
The reservation is released after departure, a failed trip or pickup. A door
blocked during sleep is checked again before leaving.

Run the navigation regression checks from the project directory:

```sh
swiftc -module-cache-path /private/tmp/pilire-swift-cache Pilire/AnimalNavigation.swift Tools/check_animal_navigation.swift -o /private/tmp/pilire-navigation-check
/private/tmp/pilire-navigation-check
```
