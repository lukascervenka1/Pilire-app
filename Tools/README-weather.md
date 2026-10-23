# Storm weather

`TownWeather.seeded` keeps the existing daily weather distribution: 70% sun,
15% fog, and 15% precipitation. Five percentage points of precipitation are
now storms. The selection follows the local calendar date and refreshes when
the map returns or its minute timer fires; it is not saved in the player's data.

The scene combines time-of-day light with weather on every refresh. Storms use
a cool sky, soft shadows, slanted rain, distant cloud wisps and a low warm glow
in windows and street lamps. A single smooth lightning pulse lasts 1.15 seconds;
after the first 8–14 seconds, subsequent strikes are 27–43 seconds apart. Reduce
Motion and Dim Flashing Lights suppress lightning. Hidden/background maps clear
the pulse and restart the waiting period on return.

Thunder follows the flash by 1.5–2.7 seconds and uses the existing ambient sound
setting and silent-switch behavior. Pending/current thunder stops when muted,
when leaving the map, or when the weather changes. Regenerate the authored audio:

```sh
python3 Tools/author_storm_thunder.py
```

## Preview and checks

For a Debug build, add Xcode launch arguments:

```text
-screenshotWeather storm -screenshotHour 14
```

Use hour `22` for night. Remove these arguments to restore real time/weather.
Release builds ignore them.

`StormWeatherPreview.swift` is a standalone simulator harness, following the
same separate-bundle setup as `DogFeedingPreview.swift`. Link it to the Debug
`Pilire` module/dylib and include `Assets.car`, `GLTFKit2.framework` and
`amb_distant_thunder.m4a`. It uses a temporary town without a SwiftData store.

It saves four native screenshots and `result.json` in its own Documents folder.
Checks cover repeated lighting refreshes, weather transitions, local date
changes, all daylight phases, map expansion, light limits, scheduled lightning,
pause/resume, disabled flashes, audio decoding/playback and thunder cancellation.
Pass `--demo` to keep the sample town running without the checks.
