# Native macOS Apple Silicon Runtime

The macOS port keeps Path of Building's Lua application and calculation engine
unchanged. The native app replaces only the Windows-only SimpleGraphic runtime
bundle with a macOS host that exposes the same Lua globals used by
`src/Launch.lua`.

## Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Homebrew packages: `cmake`, `ninja`, `sdl3`, `luajit`, `curl`, `zlib`, `zstd`

## Build

```bash
brew install cmake ninja sdl3 luajit curl zlib zstd
tools/macos/build_app.sh
```

The build writes `build/macos-arm64/PathOfBuilding-PoE2.app`.

## Package

```bash
tools/macos/package_app.sh
```

The package step creates `dist/macos-arm64/PathOfBuilding-PoE2-macos-arm64.zip`
and refreshes `runtime-macos-arm64/` so `update_manifest.py` can include the
native runtime as `platform="macos-arm64"`.

It also makes the bundle self-contained. The build links SDL3, LuaJIT and zstd
from Homebrew, so the linked executable records absolute install names such as
`/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`; a machine without those formulae
would abort at launch with a dyld `Library not loaded` error. Packaging
therefore:

1. copies every non-system dependency into `Contents/Frameworks/`, walking
   `otool -L` recursively and resolving `@loader_path` / `@rpath` install
   names so library-to-library references are followed too,
2. rewrites the references to `@rpath` and adds
   `@executable_path/../Frameworks`,
3. deletes the absolute Homebrew `LC_RPATH` entries CMake inherits from
   pkg-config -- dyld searches those first, so leaving them in would let a
   Homebrew copy win over the bundled one on any machine that has it,
4. re-signs ad hoc, since editing Mach-O headers invalidates the signature and
   an invalid signature is a hard launch failure on Apple Silicon, and
5. fails the build if any `/opt/homebrew` or `/usr/local` path survives in the
   bundle's load commands.

Homebrew is still required to *build*; it is no longer required to *run* a
packaged app.

## Verify a package

```bash
tools/macos/test_package.sh
```

Checks that nothing in the bundle references `/opt/homebrew` or `/usr/local`,
that every non-system dependency resolves inside `Contents/Frameworks`, that
the rpath set is exactly `@executable_path/../Frameworks`, that the signature
survives the zip round-trip, and that the app launches and maps its libraries
from inside the bundle. The launch check needs a window server, so it is
skipped under CI unless `POB_TEST_LAUNCH=1` is set. CI runs this on every
build and before every release.

## Tests

The existing calculation and feature tests remain the authority for parity:

```bash
docker-compose up
```

For local LuaJIT environments:

```bash
cd src
luajit HeadlessWrapper.lua
cd ..
busted --lua=luajit
```

Before release, verify the native host manually:

- Launches to an unnamed build
- Can resize and redraw the window
- Can paste/import and generate/share build codes
- Opens browser links and trade/wiki URLs
- OAuth redirect server completes account authentication
- Saves builds under `~/Library/Application Support/Path of Building (PoE2)`

## Runtime behaviour

- User data (builds, settings, cached API responses) is stored under
  `~/Library/Application Support/Path of Building (PoE2)/`.
- The packaged manifest tags the `<Version>` element with
  `platform="macos-arm64"`, so the app runs as a normal release rather than in
  developer mode.
- The in-app auto-updater is disabled on macOS (the Windows `Update.exe` runtime
  is not shipped). Update by downloading a newer release.

## Release Notes

The macOS artifact is native Apple Silicon. It does not use Wine, CrossOver, or
the Windows `.exe` runtime. The Windows runtime binaries (`.exe`/`.dll`) are not
part of this port; only the shared Lua sources, fonts
(`runtime/SimpleGraphic/Fonts`) and Lua libraries (`runtime/lua`) are retained.

