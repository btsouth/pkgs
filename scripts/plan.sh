#!/usr/bin/env bash
# Stages every package the repository is missing. With a package and tag it
# stages that release; with no arguments it looks at the latest release of
# every project in packages.txt and stages the ones not served yet.
#
#   scripts/plan.sh [<package> <tag>]
set -euo pipefail

site="${BTSOUTH_REPO_URL:-https://pkgs.btso.dev}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# packages.txt: one project per line, "<package> [<owner>/<repo>] [attested]".
# The repository defaults to btsouth/<package>.
entries() {
  grep -vE '^\s*(#|$)' packages.txt | while read -r package rest; do
    repo="btsouth/$package" attested=""
    for word in $rest; do
      case "$word" in
        attested) attested=attested ;;
        */*) repo="$word" ;;
        *) echo "::error::packages.txt: unknown option $word for $package." >&2; exit 1 ;;
      esac
    done
    echo "$package $repo $attested"
  done
}

if [ "$#" -eq 2 ]; then
  read -r _ repo attested < <(entries | awk -v p="$1" '$1 == p') ||
    { echo "::error::$1 is not listed in packages.txt."; exit 1; }
  "$here/collect.sh" "$1" "$repo" "$2" "$attested"
  exit 0
fi

# What each architecture's database lists right now, as "<name>-<version>".
# The database decides, not the files in the bucket: a release that was
# rolled back still has its file there but is no longer listed.
served="$(mktemp -d)"
trap 'rm -rf "$served"' EXIT
for arch in x86_64 aarch64; do
  code="$(curl -s -o "$served/$arch.db" -w '%{http_code}' "$site/$arch/btsouth.db")"
  case "$code" in
    200) tar -tzf "$served/$arch.db" | sed -n 's,/$,,p' > "$served/$arch" ;;
    404) : > "$served/$arch" ;;
    *) echo "::error::$site answered $code for the $arch database."; exit 1 ;;
  esac
done

entries | while read -r package repo attested; do
  # `releases/latest` is the newest release that is neither a draft nor a
  # prerelease. A project with no release yet is skipped, not an error.
  release="$(gh api "repos/$repo/releases/latest" 2>/dev/null)" || {
    echo "$package: no published release yet"; continue; }
  tag="$(jq -r .tag_name <<<"$release")"
  files="$(jq -r --arg p "$package" \
    '.assets[].name | select(startswith($p + "-") and endswith(".pkg.tar.zst"))' <<<"$release" |
    grep -E -- '-[0-9]+-(x86_64|aarch64|any)\.pkg\.tar\.zst$' || true)"
  if [ -z "$files" ]; then
    echo "::warning::$package: release $tag has no Arch package attached."
    continue
  fi
  missing=0
  while read -r file; do
    entry="${file%.pkg.tar.zst}"; arch="${entry##*-}"; entry="${entry%-*}"
    if [ "$arch" = any ]; then arches="x86_64 aarch64"; else arches="$arch"; fi
    for arch in $arches; do
      grep -qxF -- "$entry" "$served/$arch" || missing=1
    done
  done <<<"$files"
  if [ "$missing" = 1 ]; then
    echo "$package: publishing $tag"
    "$here/collect.sh" "$package" "$repo" "$tag" "$attested"
  else
    echo "$package: $tag is already served"
  fi
done
