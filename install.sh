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
# pacman-key is chatty about the whole keyring; show its output only on failure.
$sudo pacman-key --add "$tmp/btsouth.gpg" >"$tmp/key.log" 2>&1 || {
  cat "$tmp/key.log" >&2
  err "pacman-key could not import the signing key."; }
# --lsign-key only signs the fingerprint it is given, so importing whatever
# the server sent is harmless; this line is what decides trust.
$sudo pacman-key --lsign-key "$REPO_SIGNING_KEY" >"$tmp/key.log" 2>&1 || {
  cat "$tmp/key.log" >&2
  err "pacman-key could not trust $REPO_SIGNING_KEY. The key served by $repo_url is not the one this installer expects."; }
say "Trusted key $REPO_SIGNING_KEY"

# SigLevel = Required makes pacman insist on a signed package list as well as
# signed packages, so nobody between you and the server can alter either.
if grep -q '^\[btsouth\]' "$pacman_conf" 2>/dev/null; then
  if grep -A2 '^\[btsouth\]' "$pacman_conf" | grep -q '^SigLevel'; then
    say "btsouth repository already configured"
  else
    say "Requiring signatures for the btsouth repository"
    $sudo sed -i '/^\[btsouth\]$/a SigLevel = Required' "$pacman_conf" ||
      err "Could not write to $pacman_conf"
  fi
else
  say "Adding the btsouth repository to $pacman_conf"
  # shellcheck disable=SC2016
  printf '\n[btsouth]\nSigLevel = Required\nServer = %s/$arch\n' "$repo_url" |
    $sudo tee -a "$pacman_conf" >/dev/null ||
    err "Could not write to $pacman_conf"
fi

# `omarchy refresh pacman` (a channel switch) rewrites pacman.conf from a
# template and drops added repositories. Omarchy runs this hook right after,
# so the repository comes back before packages update.
hook_dir="${BTSOUTH_HOOK_DIR:-$HOME/.config/omarchy/hooks}"
if [ "$(id -u)" -ne 0 ] && [ -d "$hook_dir" ] && [ "$pacman_conf" = /etc/pacman.conf ]; then
  mkdir -p "$hook_dir/pre-refresh-pacman.d"
  cat > "$hook_dir/pre-refresh-pacman.d/btsouth-repo" <<'HOOK'
#!/bin/bash
# Installed by https://pkgs.btso.dev/install.sh. Puts the btsouth package
# repository back after `omarchy refresh pacman` resets /etc/pacman.conf.
# Delete this file if you remove the repository.
grep -q '^\[btsouth\]' /etc/pacman.conf && exit 0
echo "Restoring the btsouth package repository"
printf '\n[btsouth]\nSigLevel = Required\nServer = https://pkgs.btso.dev/$arch\n' |
  sudo tee -a /etc/pacman.conf >/dev/null
HOOK
  say "Added an Omarchy hook so the repository survives a channel switch"
fi

# Fetch only this repository's database. `pacman -Sy` would refresh every
# repository and then install against lists newer than the installed system,
# which is the partial upgrade Arch warns about.
say "Fetching the btsouth package list"
sync_dir="$(pacman-conf DBPath)sync"
for file in btsouth.db btsouth.db.sig; do
  curl -fsSL "$repo_url/$(uname -m)/$file" -o "$tmp/$file" ||
    err "Could not fetch $file from $repo_url (is $(uname -m) supported?)"
  $sudo install -Dm644 "$tmp/$file" "$sync_dir/$file" ||
    err "Could not write to $sync_dir"
done

if [ "$#" -eq 0 ]; then
  say "Repository added. Install with: sudo pacman -S <package>"
else
  # A package with no build for this machine would only fail later as
  # "target not found" with a misleading hint, so name it up front.
  missing=""
  for package in "$@"; do
    pacman -Si -- "$package" >/dev/null 2>&1 || missing="$missing $package"
  done
  if [ -n "$missing" ]; then
    available=$(pacman -Sl btsouth 2>/dev/null | awk '{print $2}' | paste -sd ' ' -)
    err "No $(uname -m) build of:$missing. Available for $(uname -m): ${available:-none yet}."
  fi
  say "Installing $*"
  $sudo pacman -S --noconfirm --needed "$@" ||
    err "pacman could not install $*. If a dependency is missing or too old, run your system update and try again."
  say "Installed."
fi
say "Updates arrive with your normal system update (omarchy update or pacman -Syu)."
