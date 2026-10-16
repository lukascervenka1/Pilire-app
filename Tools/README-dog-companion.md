# Dog companion animation authoring

Run from the Xcode project directory with Python 3 and NumPy:

```sh
python3 Tools/author_dog_companion.py
```

This appends five skeletal clips to `shiba.gltf` and `husky.gltf`:

| Clip | Seconds | Playback |
| --- | ---: | --- |
| Companion_LieDown | 2.2 | Lower chest and fold legs, then lower head |
| Companion_Sleep | 4.8 | Seamless breathing loop |
| Companion_Rise | 1.8 | Raise head, then restore support on all four paws |
| Companion_Pet | 2.4 | Tail response and a small head turn |
| Companion_Sniff | 3.2 | Pause to investigate with the nose |

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
