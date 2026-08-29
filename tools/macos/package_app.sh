#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="${repo_root}/build/macos-arm64"
dist_dir="${repo_root}/dist/macos-arm64"
runtime_dir="${repo_root}/runtime-macos-arm64"
app_src="${build_dir}/PathOfBuilding-PoE2.app"
app_dst="${dist_dir}/Path of Building (PoE2).app"

"${repo_root}/tools/macos/fetch_fonts.sh"
"${repo_root}/tools/macos/build_app.sh"

rm -rf "${dist_dir}"
mkdir -p "${dist_dir}"
cp -R "${app_src}" "${app_dst}"

# --- Bundle non-system dylibs -------------------------------------------------
# The build links against Homebrew dylibs by absolute path (/opt/homebrew/...),
# which crashes at launch for users without Homebrew. Copy every non-system
# dylib (walking otool -L recursively) into Contents/Frameworks, rewrite the
# install names to @rpath/..., and add an rpath so dyld finds them inside the
# bundle.
binary="${app_dst}/Contents/MacOS/PathOfBuilding-PoE2"
frameworks="${app_dst}/Contents/Frameworks"
mkdir -p "${frameworks}"

is_system_dep() {
  case "$1" in
    /usr/lib/*|/System/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print the load-command paths of a Mach-O file (skips the "file:" header;
# the self-ID line of a dylib is filtered out by the caller).
deps_of() {
  otool -L "$1" | awk 'NR > 1 { print $1 }'
}

# Resolve a dependency path to a real file on disk. @loader_path is resolved
# against the directory the referencing dylib was copied from; a bare @rpath
# dep is looked up in that same directory (its usual meaning for Homebrew).
resolve_dep() {
  local dep="$1" srcdir="$2"
  case "${dep}" in
    @loader_path/*) printf '%s\n' "${srcdir}/${dep#@loader_path/}" ;;
    @rpath/*)       printf '%s\n' "${srcdir}/${dep#@rpath/}" ;;
    @*)             printf '\n' ;;
    *)              printf '%s\n' "${dep}" ;;
  esac
}

# Rewrite every non-system dependency of $1 to @rpath/<name>, bundling the
# dependency first (recursively) if it is not already in Frameworks. $2 is the
# directory the file was copied from, for resolving relative install names.
rewrite_deps() {
  local file="$1" srcdir="$2" dep name resolved
  while IFS= read -r dep; do
    is_system_dep "${dep}" && continue
    name="$(basename "${dep}")"
    # Skip the dylib's own LC_ID_DYLIB line.
    [ "${name}" = "$(basename "${file}")" ] && continue
    if [ ! -e "${frameworks}/${name}" ]; then
      resolved="$(resolve_dep "${dep}" "${srcdir}")"
      if [ -z "${resolved}" ] || [ ! -f "${resolved}" ]; then
        echo "error: cannot resolve dependency ${dep} of ${file}" >&2
        exit 1
      fi
      bundle_dylib "${resolved}"
    fi
    install_name_tool -change "${dep}" "@rpath/${name}" "${file}"
  done < <(deps_of "${file}")
}

bundle_dylib() {
  local src="$1" name dst
  name="$(basename "${src}")"
  dst="${frameworks}/${name}"
  [ -e "${dst}" ] && return 0
  # cp dereferences symlinks (Homebrew opt/ paths are symlinks into Cellar).
  cp "${src}" "${dst}"
  chmod u+w "${dst}"
  install_name_tool -id "@rpath/${name}" "${dst}"
  rewrite_deps "${dst}" "$(cd "$(dirname "${src}")" && pwd -P)"
}

rewrite_deps "${binary}" "$(dirname "${binary}")"

# Drop the Homebrew LC_RPATH entries the linker baked in: dyld searches rpaths
# in order, so leaving them first would load a Homebrew dylib instead of the
# bundled copy on machines that have Homebrew installed.
otool -l "${binary}" | awk '/LC_RPATH/ { f = 1 } f && / path / { print $2; f = 0 }' |
  while IFS= read -r rpath; do
    case "${rpath}" in
      /opt/homebrew/*|/usr/local/*)
        install_name_tool -delete_rpath "${rpath}" "${binary}" ;;
    esac
  done

if ! otool -l "${binary}" | grep -q '@executable_path/\.\./Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${binary}"
fi

# Nothing outside the bundle may remain referenced by absolute Homebrew path.
for machofile in "${binary}" "${frameworks}"/*.dylib; do
  if otool -L "${machofile}" | grep -Eq '/opt/homebrew|/usr/local'; then
    echo "error: ${machofile} still links against Homebrew paths:" >&2
    otool -L "${machofile}" >&2
    exit 1
  fi
done
# -----------------------------------------------------------------------------

resources="${app_dst}/Contents/Resources"
mkdir -p "${resources}"
rsync -a --delete \
  --exclude 'Export' \
  --exclude 'Builds' \
  --exclude 'Settings.xml' \
  --exclude 'HeadlessWrapper.lua' \
  --exclude 'LaunchInstall.lua' \
  "${repo_root}/src" "${resources}/"

mkdir -p "${resources}/runtime/SimpleGraphic"
rsync -a "${repo_root}/runtime/SimpleGraphic/" "${resources}/runtime/SimpleGraphic/"
rsync -a "${repo_root}/runtime/lua/" "${resources}/runtime/lua/"
# Ship a release-style manifest: tag the <Version> element with the macOS
# platform so the app does not fall into "developer mode" (which shows the
# Developer Mode warning and stores user data inside the app bundle). With a
# platform set, user data is stored under ~/Library/Application Support.
python3 - "${repo_root}/manifest.xml" "${resources}/manifest.xml" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, "r", encoding="utf-8").read()
def add_platform(match):
    tag = match.group(0)
    if "platform=" in tag:
        return tag
    return tag[:-2] + ' platform="macos-arm64" />'
text = re.sub(r'<Version\b[^>]*/>', add_platform, text, count=1)
open(dst, "w", encoding="utf-8").write(text)
PY
cp "${repo_root}/changelog.txt" "${resources}/changelog.txt"
cp "${repo_root}/help.txt" "${resources}/help.txt"
cp "${repo_root}/LICENSE.md" "${resources}/LICENSE.md"

# Re-sign ad-hoc: install_name_tool invalidated the binary's signature, and the
# seal must cover the bundled Frameworks and Resources added above. Sign last,
# after every file in the bundle is final.
codesign --force --deep -s - "${app_dst}"
codesign --verify --deep --strict "${app_dst}"

mkdir -p "${runtime_dir}"
rm -rf "${runtime_dir}/Path of Building (PoE2).app"
rsync -a "${app_dst}" "${runtime_dir}/"

zip_name="PathOfBuilding-PoE2-macos-arm64.zip"
ditto -c -k --keepParent "${app_dst}" "${dist_dir}/${zip_name}"

# Publish a SHA-256 checksum next to the zip so users can verify the download
# (see SECURITY.md). Generated with the filename only so it works with
# `shasum -a 256 -c PathOfBuilding-PoE2-macos-arm64.zip.sha256` from the
# directory containing the zip.
(
  cd "${dist_dir}"
  shasum -a 256 "${zip_name}" > "${zip_name}.sha256"
)

echo "${dist_dir}/${zip_name}"
echo "${dist_dir}/${zip_name}.sha256"
