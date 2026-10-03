# btsouth packages

A signed pacman repository for my Omarchy and Arch apps. Add it once and the
apps update with the rest of your system (`omarchy update` or `pacman -Syu`).

| Package | Project |
| --- | --- |
| `omaframe` | https://github.com/btsouth/omaframe |
| `omadrop` | https://github.com/btsouth/omadrop |
| `omaroll` | https://github.com/btsouth/omaroll |
| `omakade` | https://github.com/btsouth/omakade |
| `notestrip` | https://github.com/btsouth/notestrip |

## Install

Add the repository and install an app in one step:

```sh
curl -fsSL https://pkgs.btso.dev/install.sh | bash -s -- omaframe
```

Already have one of these apps installed from a release download? Run the same
command. The package name is the same, so it carries on from where you are.

To do it by hand:

```sh
curl -fsSL https://pkgs.btso.dev/btsouth.gpg | sudo pacman-key --add -
sudo pacman-key --lsign-key AA378A651D659C56BE5DB17B2F78D0FE524BB309

printf '\n[btsouth]\nServer = https://pkgs.btso.dev/$arch\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Sy omaframe
```

The second command trusts one exact key fingerprint. If the key served by
`pkgs.btso.dev` is ever a different one, that command fails on purpose.

## Remove

Delete the `[btsouth]` block from `/etc/pacman.conf`, then:

```sh
sudo pacman-key --delete AA378A651D659C56BE5DB17B2F78D0FE524BB309
```

Installed apps stay installed; they just stop receiving updates.

## How packages get here

Each app attaches its Arch package to its GitHub release. The
[publish workflow](.github/workflows/publish.yml) downloads that package,
checks it against the release checksums, signs it and adds it to the
repository. Nothing is rebuilt, so the repository serves the same file as the
release page.

```sh
gh workflow run publish.yml -R btsouth/pkgs -f package=omaframe -f tag=v0.7.4
```
