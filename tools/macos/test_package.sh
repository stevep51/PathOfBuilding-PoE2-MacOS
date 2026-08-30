#!/usr/bin/env bash
#
# Verifies that a packaged .app is self-contained.
#
# The host links SDL3, LuaJIT and zstd from Homebrew. Without the bundling step
# in package_app.sh the shipped executable keeps absolute install names such as
# /opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib, and every user who does not happen
# to have those formulae gets a dyld "Library not loaded" abort at launch --
# the app never starts. That failure is invisible on a build machine, which has
# the libraries, so it needs a test that does not trust the build host.
#
# Usage:
#   tools/macos/test_package.sh [path/to/Some.app]
#
# The launch check needs a window server, so it is skipped under CI unless
# POB_TEST_LAUNCH=1 is set. Set POB_TEST_LAUNCH=0 to skip it anywhere.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dist_dir="${repo_root}/dist/macos-arm64"
app="${1:-${dist_dir}/Path of Building (PoE2).app}"
zip_path="${dist_dir}/PathOfBuilding-PoE2-macos-arm64.zip"

executable="${app}/Contents/MacOS/PathOfBuilding-PoE2"
frameworks="${app}/Contents/Frameworks"

# Libraries dyld may resolve from outside the bundle. Anything else must ship
# inside the .app.
system_prefixes='^(/usr/lib/|/System/)'

passed=0
failed=0
tmp_root=""

cleanup() {
  if [ -n "${tmp_root}" ]; then
    rm -rf "${tmp_root}"
  fi
}
trap cleanup EXIT

pass() {
  passed=$((passed + 1))
  printf 'ok    %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf 'FAIL  %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/        /'
  fi
}

skip() {
  printf 'skip  %s (%s)\n' "$1" "$2"
}

# Every Mach-O file that ships inside the bundle.
bundle_macho_files() {
  find "${app}/Contents/MacOS" "${frameworks}" -type f 2>/dev/null
}

if [ ! -d "${app}" ]; then
  echo "No .app at: ${app}" >&2
  echo "Run tools/macos/package_app.sh first." >&2
  exit 2
fi

echo "Testing: ${app}"
echo

# --- 1. The bundle must not reference anything outside itself ----------------
# Covers LC_LOAD_DYLIB and LC_RPATH in one sweep. Both matter: a Homebrew
# install name fails on a machine without Homebrew, and a Homebrew rpath is
# searched *before* ours, so it silently wins over the bundled copy on a
# machine that has it -- reintroducing the version skew this bundling removes.
leftover=""
while IFS= read -r macho; do
  hits="$(otool -l "${macho}" 2>/dev/null | grep -E '(/opt/homebrew|/usr/local)/')"
  if [ -n "${hits}" ]; then
    leftover="${leftover}${macho}:
${hits}
"
  fi
done < <(bundle_macho_files)

if [ -z "${leftover}" ]; then
  pass "no /opt/homebrew or /usr/local paths in any load command"
else
  fail "bundle references libraries outside the .app" "${leftover}"
fi

# --- 2. Every non-system dependency resolves inside the bundle ---------------
missing=""
while IFS= read -r dep; do
  case "${dep}" in
    @rpath/*)
      base="${dep#@rpath/}"
      if [ ! -f "${frameworks}/${base}" ]; then
        missing="${missing}${dep} (no ${frameworks}/${base})
"
      fi
      ;;
    *)
      if ! printf '%s' "${dep}" | grep -qE "${system_prefixes}"; then
        missing="${missing}${dep} (absolute path outside the bundle)
"
      fi
      ;;
  esac
done < <(otool -L "${executable}" | tail -n +2 | awk '{print $1}')

if [ -z "${missing}" ]; then
  pass "every non-system dependency of the executable ships in Contents/Frameworks"
else
  fail "executable has dependencies that will not resolve on a clean machine" "${missing}"
fi

# --- 3. The executable's rpath points into the bundle ------------------------
rpaths="$(otool -l "${executable}" | awk '/LC_RPATH/ { found = 1 } found && /^ *path / { print $2; found = 0 }')"
if [ "${rpaths}" = "@executable_path/../Frameworks" ]; then
  pass "executable rpath is exactly @executable_path/../Frameworks"
else
  fail "unexpected rpath set on the executable" "${rpaths}"
fi

# --- 4. The libraries are actually present -----------------------------------
if [ -d "${frameworks}" ] && [ -n "$(find "${frameworks}" -name '*.dylib' -type f 2>/dev/null)" ]; then
  pass "Contents/Frameworks contains bundled libraries:$(find "${frameworks}" -name '*.dylib' -type f -exec basename {} \; | tr '\n' ' ' | sed 's/ $//' | sed 's/^/ /')"
else
  fail "Contents/Frameworks is missing or empty"
fi

# --- 5. Signature -----------------------------------------------------------
# install_name_tool invalidates the signature, and on Apple Silicon an invalid
# signature is a hard launch failure, so an unsigned-after-edit bundle looks
# exactly like the bug we are fixing.
if codesign_out="$(codesign --verify --deep --strict "${app}" 2>&1)"; then
  pass "code signature is valid"
else
  fail "code signature is invalid" "${codesign_out}"
fi

# --- 6. The shipped zip round-trips -----------------------------------------
# Users get the zip, not the .app, and ditto/codesign disagree often enough
# that this is worth checking on the actual artifact.
if [ -f "${zip_path}" ]; then
  tmp_root="$(mktemp -d)"
  if ditto -x -k "${zip_path}" "${tmp_root}" 2>/dev/null; then
    extracted="$(find "${tmp_root}" -maxdepth 1 -name '*.app' -print -quit)"
    if [ -n "${extracted}" ] && codesign --verify --deep --strict "${extracted}" 2>/dev/null; then
      pass "release zip extracts with a valid signature"
    else
      fail "release zip does not extract to a validly signed .app"
    fi
  else
    fail "release zip could not be extracted"
  fi
else
  skip "release zip round-trip" "no zip at ${zip_path}"
fi

# --- 7. It actually launches, from the bundled libraries ---------------------
# The checks above are static. This one proves the thing the user cares about:
# the process starts and maps the libraries from inside the .app.
run_launch_check() {
  local target="$1"
  local target_exe="${target}/Contents/MacOS/PathOfBuilding-PoE2"
  local pid mapped

  # alarm() caps the run; exec'ing the list form avoids the shell, which would
  # choke on the parentheses in the bundle name.
  perl -e 'alarm 20; exec {$ARGV[0]} @ARGV' "${target_exe}" >/dev/null 2>&1 &
  pid=$!
  perl -e 'select(undef, undef, undef, 5)'

  if ! kill -0 "${pid}" 2>/dev/null; then
    fail "app exited immediately after launch (dyld failure looks like this)"
    return
  fi

  # -Fn prints one "n<path>" record per line. The default table output splits
  # on whitespace, and the bundle name contains spaces, so paths come back
  # truncated there.
  mapped="$(lsof -p "${pid}" -Fn 2>/dev/null | sed -n 's/^n//p' | grep '\.dylib$' | grep -v -E "${system_prefixes}" | sort -u)"
  kill "${pid}" 2>/dev/null
  wait "${pid}" 2>/dev/null

  if [ -z "${mapped}" ]; then
    fail "could not determine which libraries the running app mapped"
    return
  fi

  local outside
  outside="$(printf '%s\n' "${mapped}" | grep -v -F "${target}/Contents/Frameworks/")"
  if [ -z "${outside}" ]; then
    pass "app launches and maps only libraries from inside the bundle"
  else
    fail "running app mapped libraries from outside the bundle" "${outside}"
  fi
}

launch_default=1
if [ -n "${CI:-}" ]; then
  launch_default=0
fi
if [ "${POB_TEST_LAUNCH:-${launch_default}}" = "1" ]; then
  # Prefer the copy extracted from the zip: it is furthest from the build tree,
  # so it catches anything that only works in place.
  if [ -n "${tmp_root}" ] && [ -n "${extracted:-}" ]; then
    run_launch_check "${extracted}"
  else
    run_launch_check "${app}"
  fi
else
  skip "launch check" "needs a window server; set POB_TEST_LAUNCH=1 to force"
fi

echo
echo "${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
