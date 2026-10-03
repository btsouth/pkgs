#!/usr/bin/env bash
# Stages every package the repository is missing. With a package and tag it
# stages that release; with no arguments it looks at the latest release of
# every project in packages.txt and stages the ones not served yet.
#
#   scripts/plan.sh [<package> <tag>]
set -euo pipefail

site="${BTSOUTH_REPO_URL:-https://pkgs.btso.dev}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# packages.txt: one project per line, "<package> [<owner>/<repo>]". The
# repository defaults to btsouth/<package>.
repo_for() {
  awk -v p="$1" '$1 == p { print ($2 != "" ? $2 : "btsouth/" p); exit }' \
    <(grep -vE '^\s*(#|$)' packages.txt)
}

if [ "$#" -eq 2 ]; then
  repo="$(repo_for "$1")"
  [ -n "$repo" ] || { echo "::error::$1 is not listed in packages.txt."; exit 1; }
  "$here/collect.sh" "$1" "$repo" "$2"
  exit 0
fi

grep -vE '^\s*(#|$)' packages.txt | while read -r package repo _; do
  repo="${repo:-btsouth/$package}"
  # `releases/latest` is the newest release that is neither a draft nor a
  # prerelease. A project with no release yet is skipped, not an error.
  release="$(gh api "repos/$repo/releases/latest" 2>/dev/null)" || {
    echo "$package: no published release yet"; continue; }
  tag="$(jq -r .tag_name <<<"$release")"
  missing=0
  while read -r file; do
    arch="${file%.pkg.tar.zst}"; arch="${arch##*-}"
    [ "$arch" = any ] && arch=x86_64
    code="$(curl -s -o /dev/null -w '%{http_code}' "$site/$arch/$file")"
    case "$code" in
      200) ;;
      404) missing=1 ;;
      *) echo "::error::$site answered $code for $file."; exit 1 ;;
    esac
  done < <(jq -r --arg p "$package" \
    '.assets[].name | select(startswith($p + "-") and endswith(".pkg.tar.zst"))' <<<"$release" |
    grep -E -- '-[0-9]+-(x86_64|aarch64|any)\.pkg\.tar\.zst$' || true)
  if [ "$missing" = 1 ]; then
    echo "$package: publishing $tag"
    "$here/collect.sh" "$package" "$repo" "$tag"
  else
    echo "$package: $tag is already served"
  fi
done
