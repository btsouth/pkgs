#!/usr/bin/env bash
# Adds the btsouth pacman repository and installs any packages named as
# arguments. After this, updates arrive with the normal system update.
#
#   curl -fsSL https://pkgs.btso.dev/install.sh | bash -s -- omaframe
set -euo pipefail

# Fingerprint of the key that signs the repository. Pinned here so a swapped
# key at pkgs.btso.dev cannot become trusted. Replace when the key rotates.
REPO_SIGNING_KEY="AA378A651D659C56BE5DB17B2F78D0FE524BB309"

# Overridable so tests can use a scratch pacman.conf and a local mirror.
repo_url="${BTSOUTH_REPO_URL:-https://pkgs.btso.dev}"
pacman_conf="${BTSOUTH_PACMAN_CONF:-/etc/pacman.conf}"

say() { printf '==> %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v pacman >/dev/null 2>&1 ||
  err "This repository is for Arch based systems (pacman not found)."

for pkg in "$@"; do
  [[ "$pkg" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || err "Not a package name: $pkg"
done

sudo=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && sudo="sudo" ||
    err "Adding the repository needs root: re-run as root or install sudo."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Importing the btsouth signing key"
curl -fsSL "$repo_url/btsouth.gpg" -o "$tmp/btsouth.gpg" ||
  err "Could not fetch the signing key from $repo_url/btsouth.gpg"
$sudo pacman-key --add "$tmp/btsouth.gpg" ||
  err "pacman-key could not import the signing key."
# --lsign-key only signs the fingerprint it is given, so importing whatever
# the server sent is harmless; this line is what decides trust.
$sudo pacman-key --lsign-key "$REPO_SIGNING_KEY" ||
  err "pacman-key could not trust $REPO_SIGNING_KEY. The key served by $repo_url is not the one this installer expects."

if grep -q '^\[btsouth\]' "$pacman_conf" 2>/dev/null; then
  say "btsouth repository already configured"
else
  say "Adding the btsouth repository to $pacman_conf"
  # shellcheck disable=SC2016
  printf '\n[btsouth]\nServer = %s/$arch\n' "$repo_url" |
    $sudo tee -a "$pacman_conf" >/dev/null ||
    err "Could not write to $pacman_conf"
fi

if [ "$#" -eq 0 ]; then
  $sudo pacman -Sy || err "pacman could not refresh its package lists."
  say "Repository added. Install with: sudo pacman -S <package>"
else
  say "Installing $*"
  $sudo pacman -Sy --noconfirm --needed "$@" ||
    err "pacman could not install $*. If a dependency is too old, run your system update and try again."
  say "Installed."
fi
say "Updates arrive with your normal system update (omarchy update or pacman -Syu)."
