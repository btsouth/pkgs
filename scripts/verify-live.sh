#!/usr/bin/env bash
# Checks that what https://pkgs.btso.dev serves is what this repository
# published: the installer and key match the reviewed copies, and each
# database is signed by the repository key and names only expected packages.
set -euo pipefail

site="${BTSOUTH_REPO_URL:-https://pkgs.btso.dev}"
key="${SIGNING_KEY:-AA378A651D659C56BE5DB17B2F78D0FE524BB309}"
fail() { echo "::error::$*"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import btsouth.gpg
[ "$(gpg --list-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')" = "$key" ] ||
  fail "btsouth.gpg in this repository is not the pinned key."
grep -q "^REPO_SIGNING_KEY=\"$key\"\$" install.sh || fail "install.sh does not pin $key."

for file in install.sh btsouth.gpg; do
  curl -fsS "$site/$file" -o "$work/$file" || fail "Could not fetch $site/$file."
  cmp -s "$file" "$work/$file" || fail "The published $file differs from the copy in this repository."
done

allowed="$(grep -vE '^\s*(#|$)' packages.txt | awk '{print $1}')"
for arch in x86_64 aarch64; do
  code="$(curl -s -o "$work/db" -w '%{http_code}' "$site/$arch/btsouth.db")"
  [ "$code" = 404 ] && { echo "$arch: no database"; continue; }
  [ "$code" = 200 ] || fail "$site answered $code for the $arch database."
  curl -fsS "$site/$arch/btsouth.db.sig" -o "$work/db.sig" || fail "The $arch database has no signature."
  gpg --batch --status-fd 1 --verify "$work/db.sig" "$work/db" 2>/dev/null |
    grep -q "^\[GNUPG:\] VALIDSIG .* $key\$" || fail "The $arch database is not signed by the repository key."
  while read -r entry; do
    desc="$(tar -xzOf "$work/db" "$entry/desc")"
    name="$(awk '/^%NAME%$/{getline; print; exit}' <<<"$desc")"
    file="$(awk '/^%FILENAME%$/{getline; print; exit}' <<<"$desc")"
    grep -qxF -- "$name" <<<"$allowed" || fail "The $arch database lists $name, which is not in packages.txt."
    for f in "$file" "$file.sig"; do
      [ "$(curl -s -o /dev/null -I -w '%{http_code}' "$site/$arch/$f")" = 200 ] ||
        fail "$arch/$f is listed but not served."
    done
    echo "$arch: $entry ok"
  done < <(tar -tzf "$work/db" | sed -n 's,/$,,p')
done
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://${site#https://}/install.sh")" = 301 ] ||
  fail "Plain HTTP is no longer redirected to HTTPS."
echo "The published repository matches this one."
