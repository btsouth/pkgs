#!/usr/bin/env bash
# Downloads the Arch packages attached to one GitHub release, checks them, and
# stages them under repo/<arch>/ ready to be signed.
#
#   scripts/collect.sh <package> <github-repo> <tag>
set -euo pipefail

package="$1" repo="$2" tag="$3"
fail() { echo "::error::$*"; exit 1; }

[[ "$tag" =~ ^v[0-9][0-9A-Za-z._+-]*$ ]] || fail "$tag does not look like a release tag."
state="$(gh release view "$tag" -R "$repo" --json isDraft,isPrerelease)" ||
  fail "$repo has no published release $tag."
[ "$(jq -r .isDraft <<<"$state")" = "false" ] || fail "$repo $tag is still a draft."
[ "$(jq -r .isPrerelease <<<"$state")" = "false" ] ||
  fail "$repo $tag is a prerelease; the repository is stable only."

assets="$(mktemp -d)"
trap 'rm -rf "$assets"' EXIT
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
    # An `any` package is served from every architecture directory.
    if [ "$arch" = any ]; then dests="x86_64 aarch64"; else dests="$arch"; fi
    for dest in $dests; do
      mkdir -p "repo/$dest"
      cp "$pkg" "repo/$dest/"
    done
    echo "$file  $sum"
    found=1
  done
done
[ "$found" = 1 ] ||
  fail "$repo $tag has no $package-<version>-<release>-<arch>.pkg.tar.zst asset."
