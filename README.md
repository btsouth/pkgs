# btsouth packages

A signed pacman repository for my Omarchy and Arch apps. Add it once and the
apps update with the rest of your system (`omarchy update` or `pacman -Syu`).

| Package | Project |
| --- | --- |
| `omaframe` | https://github.com/btsouth/omaframe |
| `omadrop` | https://github.com/btsouth/omadrop |
| `omaroll` | https://github.com/btsouth/omaroll |
| `omakade` | https://github.com/btsouth/omakade |

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
sudo pacman -Syu omaframe
```

The second command trusts one exact key fingerprint. If the key served by
`pkgs.btso.dev` is ever a different one, that command fails on purpose.

On Omarchy, switching release channel resets `/etc/pacman.conf` and drops
added repositories. The installer adds a small hook at
`~/.config/omarchy/hooks/pre-refresh-pacman.d/btsouth-repo` that puts this one
back, so there is nothing to redo.

## Remove

Delete the `[btsouth]` block from `/etc/pacman.conf`, then:

```sh
sudo pacman-key --delete AA378A651D659C56BE5DB17B2F78D0FE524BB309
rm -f ~/.config/omarchy/hooks/pre-refresh-pacman.d/btsouth-repo
```

Installed apps stay installed; they just stop receiving updates.

## How packages get here

Each app attaches its Arch package to its GitHub release. Every hour the
[publish workflow](.github/workflows/publish.yml) looks at the latest release
of each project in [packages.txt](packages.txt). If a package is not in the
repository yet, it downloads it, checks it against the release checksums,
signs it and adds it. Nothing is rebuilt, so the repository serves the same
file as the release page.

To publish straight after a release instead of waiting for the hourly run:

```sh
gh workflow run publish.yml -R btsouth/pkgs
```

## Pulling a release

The repository follows each project's latest release. To roll back a bad one,
delete that GitHub release or mark it as a prerelease, then run the publish
workflow. It republishes the release that is now the latest. People who
already took the bad version get the older one with `sudo pacman -Syuu`, or
the fix on its next release.

To take a project out altogether, remove its line from
[packages.txt](packages.txt), then:

```sh
gh workflow run remove.yml -R btsouth/pkgs -f package=<package>
```

## Adding a project

1. Attach the package to the project's GitHub release, named the way
   `makepkg` names it: `<package>-<version>-<release>-<arch>.pkg.tar.zst`.
   The version must match the tag (`v1.2.0` for `1.2.0`), and a `SHA256SUMS`
   asset listing the file is checked when present.
2. Add one line to [packages.txt](packages.txt) and push. That publishes it.
3. Add the project to the table at the top.

Nothing needs setting up in the project's own repository. The page at
https://pkgs.btso.dev lives in [site/](site) and is deployed with
`wrangler deploy`.
