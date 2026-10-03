#!/usr/bin/env bash
# Updates the signed package database for each architecture under repo/.
#
#   scripts/database.sh add               add every staged repo/<arch>/*.pkg.tar.zst
#   scripts/database.sh remove <package>  drop a package from both architectures
#
# Needs the signing key in the gpg keyring and the R2 credentials in the
# environment. Leaves the files to upload under repo/<arch>/.
set -euo pipefail

action="$1" package="${2:-}"
repo_name="${REPO_NAME:-btsouth}"
endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
# repo-add ships with pacman, which the Ubuntu runner does not have. The image
# is pinned by digest and runs with no network, no signing key and no
# credentials; what it produces is checked below before it is signed.
image="archlinux@sha256:b21322c663be387c0ed9cbc7bbbfe18e41633ad4e7b7c77cfad45f128be20040"
fail() { echo "::error::$*"; exit 1; }

signed_by_us() {
  gpg --batch --status-fd 1 --verify "$1.sig" "$1" 2>/dev/null |
    grep -q "^\[GNUPG:\] VALIDSIG .* $SIGNING_KEY\$"
}

allowed="$(grep -vE '^\s*(#|$)' packages.txt | awk '{print $1}')"

case "$action" in
  add) arches="$(for d in repo/*/; do basename "$d"; done)" ;;
  remove) arches="x86_64 aarch64" ;;
  *) fail "Unknown action $action." ;;
esac

for arch in $arches; do
  dir="repo/$arch"
  mkdir -p "$dir"
  for kind in db files; do
    file="$repo_name.$kind.tar.gz"
    # A missing database is expected the first time; any other failure must
    # not be mistaken for an empty repository.
    if aws s3api head-object --endpoint-url "$endpoint" --bucket "$R2_BUCKET" \
         --key "$arch/$file" >/dev/null 2>head.err; then
      aws s3 cp "s3://$R2_BUCKET/$arch/$file" "$dir/" --endpoint-url "$endpoint" --only-show-errors
      aws s3 cp "s3://$R2_BUCKET/$arch/$file.sig" "$dir/" --endpoint-url "$endpoint" --only-show-errors
      # Never build on a database that someone else changed in the bucket:
      # signing it again would put our signature on their edit.
      signed_by_us "$dir/$file" ||
        fail "The published $arch/$file is not signed by the repository key. Stopping."
    elif ! grep -q 'Not Found\|404' head.err; then
      cat head.err; fail "Could not read the existing $arch database."
    fi
  done

  if [ "$action" = remove ]; then
    if [ ! -f "$dir/$repo_name.db.tar.gz" ] ||
       ! tar -tzf "$dir/$repo_name.db.tar.gz" | grep -qE "^$package-[^-]+-[^-]+/\$"; then
      echo "$arch: $package is not listed"
      rm -rf "$dir"
      continue
    fi
    command="repo-remove $repo_name.db.tar.gz $package"
  else
    command="repo-add $repo_name.db.tar.gz *.pkg.tar.zst"
  fi
  docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    -u "$(id -u):$(id -g)" -v "$PWD/$dir:/repo" -w /repo "$image" bash -euc "$command"

  # The database may only name packages this repository is meant to carry.
  while read -r entry; do
    desc="$(tar -xzOf "$dir/$repo_name.db.tar.gz" "$entry/desc")"
    name="$(awk '/^%NAME%$/{getline; print; exit}' <<<"$desc")"
    grep -qxF -- "$name" <<<"$allowed" || fail "$arch database lists $name, which is not in packages.txt."
    [ "$action" = remove ] && [ "$name" = "$package" ] && fail "$package is still listed for $arch."
  done < <(tar -tzf "$dir/$repo_name.db.tar.gz" | sed -n 's,/$,,p')

  for kind in db files; do
    file="$dir/$repo_name.$kind.tar.gz"
    gpg --batch --yes --local-user "$SIGNING_KEY" --detach-sign --no-armor "$file"
    # pacman requests `<repo>.db` and `<repo>.db.sig`.
    # repo-add leaves symlinks under those names; replace them with files.
    rm -f "$dir/$repo_name.$kind" "$dir/$repo_name.$kind.sig" "$file.old" "$file.old.sig"
    cp "$file" "$dir/$repo_name.$kind"
    cp "$file.sig" "$dir/$repo_name.$kind.sig"
  done
  ls -la "$dir"
done
