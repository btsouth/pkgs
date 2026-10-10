#!/usr/bin/env bash
# Downloads the Arch packages attached to one GitHub release, checks them, and
# stages them under repo/<arch>/ ready to be signed.
#
#   scripts/collect.sh <package> <github-repo> <tag> [attested]
#
# With `attested`, each package must carry a GitHub build attestation proving
# that the project's own Actions workflow built it.
#
# An x86_64 or any package must also start on Omarchy stable, the oldest
# channel users run: no binary in it may need a Qt or glibc symbol version
# newer than the stable mirror ships. Nothing is staged unless every package
# in the release passes.
set -euo pipefail

package="$1" repo="$2" tag="$3" attested="${4:-}"
fail() { echo "::error::$*"; exit 1; }

[[ "$tag" =~ ^v[0-9][0-9A-Za-z._+-]*$ ]] || fail "$tag does not look like a release tag."
state="$(gh release view "$tag" -R "$repo" --json isDraft,isPrerelease)" ||
  fail "$repo has no published release $tag."
[ "$(jq -r .isDraft <<<"$state")" = "false" ] || fail "$repo $tag is still a draft."
[ "$(jq -r .isPrerelease <<<"$state")" = "false" ] ||
  fail "$repo $tag is a prerelease; the repository is stable only."

assets="$(mktemp -d)"
trap 'rm -rf "$assets"' EXIT

# The version of a package in Omarchy's stable mirror, e.g. 6.11.2 for qt6-base.
stable="${OMARCHY_STABLE_MIRROR:-https://stable-mirror.omarchy.org}"
stable_version() {
  curl -fsSL "$stable/$1/os/x86_64/$1.db" | tar -tzf - |
    sed -n "s,^$2-\([0-9][^-]*\)-[0-9.]*/\$,\1,p" | head -n 1
}
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }

# Fails if a binary in the package needs a newer Qt or glibc than stable has.
check_stable() {
  local pkg="$1" file="$2" root elf need
  [ -n "${stable_qt:-}" ] || {
    stable_qt="$(stable_version extra qt6-base)" || stable_qt=""
    stable_glibc="$(stable_version core glibc)" || stable_glibc=""
    stable_qt="$(cut -d . -f 1,2 <<<"$stable_qt")" stable_glibc="${stable_glibc%%+*}"
    [ -n "$stable_qt" ] && [ -n "$stable_glibc" ] ||
      fail "Could not read Qt and glibc versions from $stable, so $file cannot be checked."
    echo "Omarchy stable ships Qt $stable_qt and glibc $stable_glibc"
  }
  root="$assets/check-$file"
  mkdir "$root"
  tar --zstd -xf "$pkg" -C "$root"
  while IFS= read -r -d '' elf; do
    [ "$(head -c 4 "$elf" | od -An -tx1 | tr -d ' ')" = 7f454c46 ] || continue  # ELF magic
    for need in $(objdump -T "$elf" 2>/dev/null | grep -oE '(Qt_6|GLIBC_2)\.[0-9.]+' | sort -u); do
      case "$need" in
        Qt_*) newer "${need#Qt_}" "$stable_qt" || continue ;;
        GLIBC_*) newer "${need#GLIBC_}" "$stable_glibc" || continue ;;
      esac
      fail "$file needs $need in ${elf#"$root"/}, newer than Omarchy stable (Qt $stable_qt, glibc $stable_glibc). Build it against the stable mirror."
    done
  done < <(find "$root" -type f -print0)
  rm -rf "$root"
  echo "$file: runs on Omarchy stable"
}

gh release download "$tag" -R "$repo" -D "$assets" \
  -p "$package-*.pkg.tar.zst" -p 'SHA256SUMS*'

shopt -s nullglob
found=0
for arch in x86_64 aarch64 any; do
  for pkg in "$assets/$package"-*-"$arch".pkg.tar.zst; do
    file="$(basename "$pkg")"
    # The package must be what the release says it is: right name, right
    # version, right architecture.
    info="$(tar --zstd -xOf "$pkg" .PKGINFO)"
    name="$(sed -n 's/^pkgname = //p' <<<"$info")"
    ver="$(sed -n 's/^pkgver = //p' <<<"$info")"
    parch="$(sed -n 's/^arch = //p' <<<"$info")"
    [ "$name" = "$package" ] || fail "$file contains package $name."
    [ "${ver%-*}" = "${tag#v}" ] || fail "$file is version $ver but the tag is $tag."
    [ "$parch" = "$arch" ] || fail "$file is built for $parch."
    [ "$file" = "$name-$ver-$parch.pkg.tar.zst" ] ||
      fail "$file is not named $name-$ver-$parch.pkg.tar.zst."
    sum="$(sha256sum "$pkg" | cut -d ' ' -f 1)"
    if cat "$assets"/SHA256SUMS* 2>/dev/null | grep -qF "$file"; then
      cat "$assets"/SHA256SUMS* | grep -qE "^$sum [ *]$file\$" ||
        fail "$file does not match the release SHA256SUMS."
    else
      echo "::warning::$repo $tag has no checksum for $file."
    fi
    if [ "$attested" = attested ]; then
      gh attestation verify "$pkg" --repo "$repo" >/dev/null ||
        fail "$file has no valid build attestation from $repo."
      echo "$file: build attestation verified"
    fi
    # Omarchy has no aarch64 channel to check against.
    [ "$arch" = aarch64 ] || check_stable "$pkg" "$file"
    # An `any` package is served from every architecture directory.
    if [ "$arch" = any ]; then dests="x86_64 aarch64"; else dests="$arch"; fi
    for dest in $dests; do
      mkdir -p "$assets/stage/$dest"
      cp "$pkg" "$assets/stage/$dest/"
    done
    echo "$file  $sum"
    found=1
  done
done
[ "$found" = 1 ] ||
  fail "$repo $tag has no $package-<version>-<release>-<arch>.pkg.tar.zst asset."
mkdir -p repo
cp -r "$assets/stage/." repo/
