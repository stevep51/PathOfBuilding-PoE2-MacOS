# Path of Building (PoE2) — Native macOS Port
## An offline build planner for Path of Exile 2, running natively on Apple Silicon macOS.

<p float="middle">
  <img alt="Tree tab" src="https://github.com/user-attachments/assets/225bf25f-1ac4-4639-b280-565a24d2a2fc" width="48%" />
  <img alt="Items tab" src="https://github.com/user-attachments/assets/de8e6dc0-1e1a-46c5-b8a4-18877e67d48d" width="48%" />
</p>

This is a **native macOS (Apple Silicon) port** of [Path of Building Community for Path of Exile 2](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2).

It keeps the original Lua application and the entire calculation engine **unchanged** — every offence/defence calculation, the passive tree, items, skills and import/export logic are identical to the upstream project. Only the Windows-only SimpleGraphic runtime has been replaced with a native macOS host (SDL3 + LuaJIT + a bitmap font/DDS renderer), so it runs as a real `.app` instead of through Wine/CrossOver or the Windows `.exe`.

## Requirements
- Apple Silicon Mac (arm64)
- macOS 13 (Ventura) or newer

## Install
Download the latest `PathOfBuilding-PoE2-macos-arm64.zip` from the Releases page, unzip it, and move **Path of Building (PoE2).app** to your Applications folder. On first launch, macOS Gatekeeper may require you to right‑click the app and choose **Open** (it is not notarized).

Your builds and settings are stored under:
`~/Library/Application Support/Path of Building (PoE2)/`

## Is it safe? (account sign-in & privacy)
Yes — and you don't have to take that on faith. This app talks **only** to
Grinding Gear Games' official servers, has no telemetry, and never sends your
account, tokens, or builds to anyone. Sign-in is optional and uses the standard
OAuth + PKCE flow: you log in on `pathofexile.com` in your browser, and the app
never sees your password. See **[SECURITY.md](SECURITY.md)** for the full
breakdown (including how to verify or build the app yourself).

## Features
* Comprehensive offence + defence calculations:
  * Calculate your skill DPS, damage over time, life/mana/ES totals and much more!
  * Can factor in auras, buffs, charges, curses, monster resistances and more, to estimate your effective DPS
  * Also calculates life/mana reservations
  * Shows a summary of character stats in the side bar, as well as a detailed calculations breakdown tab
  * Supports all skills and support gems, and most passives and item modifiers
  * Full support for minions, party play and support builds
* Passive skill tree planner:
  * Support for jewels including most radius/conversion and timeless jewels
  * Alternate path tracing (mouse over a sequence of nodes while holding shift, then click to allocate them all)
  * Fully integrated with the offence/defence calculations
  * Can import PathOfExile.com and PoEPlanner.com passive tree links
* Skill planner: add any number of main or supporting skills; toggle auras/curses/buffs on and off
* Item planner: paste items straight from the game, search trade, craft items, and browse a unique/rare database
* Import your characters directly from your Path of Exile account (OAuth sign-in)
* Share builds with other Path of Building users via build codes

## Building from source
See **[docs/macos.md](docs/macos.md)** for full build/package instructions. In short:

```bash
brew install cmake ninja sdl3 luajit curl zlib zstd
tools/macos/build_app.sh      # builds build/macos-arm64/PathOfBuilding-PoE2.app
tools/macos/package_app.sh    # produces dist/macos-arm64/PathOfBuilding-PoE2-macos-arm64.zip
```

## What's different from upstream
- **Native macOS host** (`macos/`) replaces SimpleGraphic: SDL3 rendering with layer-correct draw ordering, a bitmap font renderer, DDS/TGA decoders, libcurl-backed downloads, a loopback OAuth server, and background sub-scripts.
- The Windows runtime (`.exe`/`.dll`) has been removed; the shared Lua, fonts (`runtime/SimpleGraphic/Fonts`) and Lua libraries (`runtime/lua`) are retained.
- Auto-update is disabled on macOS (there is no native updater yet); update via a new release download.

## Changelog
You can find the full version history [here](CHANGELOG.md).

## Credits
This port stands entirely on the work of the **[Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2)** team, who created and maintain Path of Building and the PoE2 fork. All calculation logic, data and UI are theirs.

## Licence
[MIT](https://opensource.org/licenses/MIT)

For 3rd-party licences, see [LICENSE](LICENSE.md). The licensing information is considered to be part of the documentation.
