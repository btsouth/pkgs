# Security

Report a problem privately through
[GitHub security advisories](https://github.com/btsouth/pkgs/security/advisories/new).
Please do not open a public issue for anything that could put users at risk.

## What protects you

- Every package and the package list are signed with one key, fingerprint
  `AA378A651D659C56BE5DB17B2F78D0FE524BB309`. The installer trusts that exact
  fingerprint and sets `SigLevel = Required`, so pacman refuses anything that
  is unsigned or altered, whoever serves it.
- The repository only carries the projects in [packages.txt](packages.txt),
  taken from their published GitHub releases and checked against the release
  checksums. Projects marked `attested` must also carry a GitHub build
  attestation showing the project's own workflow built the package.
- Before each change the publish workflow checks that the existing package
  list is still signed by the repository key. Every hour it checks that the
  installer, key and package lists being served match this repository.
- The site redirects plain HTTP to HTTPS.

## What it does not protect against

- The installer itself is fetched over HTTPS and run without a signature.
  The manual steps in the [README](README.md) avoid running a script.
- pacman cannot tell that a signed package list is old, so someone in control
  of the server could withhold updates. They could not alter packages.
- A package is only as trustworthy as the project release it came from.
