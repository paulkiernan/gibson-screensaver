# AUR: `gibson-screensaver`

Everything an AUR push needs. `PKGBUILD` here builds the project from the GitHub
tag tarball and installs

| Path | What |
| --- | --- |
| `/usr/bin/gibson-screensaver` | the binary (built as `gibson-app`) |
| `/usr/share/xscreensaver/config/gibson-screensaver.xml` | the xscreensaver descriptor |
| `/usr/share/licenses/gibson-screensaver/LICENSE` | GPL-3.0-or-later |
| `/usr/share/doc/gibson-screensaver/README.md` | project README |
| `/usr/share/doc/gibson-screensaver/xscreensaver-host.md` | how the xscreensaver host works |

The prebuilt alternative is in [`../aur-bin/`](../aur-bin/) - see
[the prebuilt package](#the-prebuilt-package-gibson-screensaver-bin) below.

## Publishing is automated

[`.github/workflows/aur.yml`](../../.github/workflows/aur.yml) is the
publishing path. A commit on `main` that changes a `PKGBUILD`, a `.SRCINFO` or
an install hook in this directory or `../aur-bin/` makes it:

1. regenerate `.SRCINFO` with `makepkg --printsrcinfo` and fail if the
   committed one differs;
2. check `pkgver` equals the `[workspace.package]` version in `Cargo.toml`,
   because the release tag is that version and both packages build that tag's
   artifacts;
3. run `makepkg --verifysource`, which downloads every `source` and checks it
   against `sha256sums` - so a `pkgver` bump whose digests were not recomputed
   fails here;
4. `namcap` the `PKGBUILD`, build the package, and `namcap` the result;
5. extract the built package and run the installed binary;
6. push to `ssh://aur@aur.archlinux.org/<pkgname>.git` only if all of that
   passed.

It runs in an `archlinux:base-devel` container, which is also the
clean-environment check this document used to ask a maintainer to do by hand: a
`depends` entry that is missing fails there instead of passing on a machine that
happens to have the library installed.

`workflow_dispatch` runs the same pipeline with `dry_run` defaulting to true,
which validates and builds without touching the AUR. Use it to check a
packaging change before merging it.

The manual runbook below is still the fallback, and still describes what the
automation does; it is no longer the normal route.

### One-time setup

1. Register at <https://aur.archlinux.org/register>. This account is separate
   from the Arch Linux BBS/wiki account.
2. Generate a dedicated key and add the **public** half to the account under
   My Account -> SSH Public Key:

   ```sh
   ssh-keygen -t ed25519 -C 'aur-publish@gibson-screensaver (github actions)' -f ~/.ssh/aur_ed25519
   ```

3. Put the **private** half in this repository's secrets as
   `AUR_SSH_PRIVATE_KEY`:

   ```sh
   gh secret set AUR_SSH_PRIVATE_KEY < ~/.ssh/aur_ed25519
   ```

   Optionally set the `AUR_GIT_NAME` and `AUR_GIT_EMAIL` repository *variables*
   to control the identity on the AUR-side commits; they default to the
   maintainer line in the `PKGBUILD`.

Until the secret exists the workflow still validates and builds both packages -
only the push is skipped, with a notice saying why. The AUR host key is pinned
in the workflow (`SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4`), not
accepted on first use.

## `.SRCINFO` is generated, not hand-written

Both `.SRCINFO` files were originally written by hand on macOS, where `makepkg`
does not exist. They have since been regenerated on Arch with
`makepkg --printsrcinfo` and committed, and the diff was confined to the header
comment and one `pkgdesc` edit - the hand-written files were otherwise byte for
byte what the generator produces, which is a good result for the method
described under
[Checking the two files agree](#checking-the-two-files-agree).

**Every `PKGBUILD` edit that touches a field appearing in `.SRCINFO` requires
regenerating it** (`pkgver`, `pkgrel`, `source`, `sha256sums`, `depends`,
`makedepends`, `optdepends`, `provides`, `conflicts`, `pkgdesc`, `arch`,
`license`, `install`):

```sh
makepkg --printsrcinfo > .SRCINFO
```

A stale `.SRCINFO` is the most common reason an AUR page shows the wrong
version. Forgetting is no longer a way to ship it, though: step 1 of the
workflow fails the build.

## Digests recorded in these files

All measured by downloading the published bytes on 2026-09-11 and hashing them
locally; the release's own `SHA256SUMS` gives the same asset digests.

| Source in the `PKGBUILD`s | SHA256 |
| --- | --- |
| `.../archive/refs/tags/2.1.1.tar.gz` (source package) | `c3d3f667f10432dd352532fdb2aa434ec2200dd48da2347193b9334b7725a6d8` |
| `.../releases/download/2.1.1/gibson-screensaver-linux-x86_64.tar.gz` (-bin) | `f510a53b9f380089f07fdc02af2c5da8b089d303aabae6686962177080a3f6a9` |
| `.../raw/.../2.1.1/LICENSE` (-bin, the asset tarball has no licence file) | `0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b` |

`updpkgsums` re-measures these; run it after any `source` change. A force-retag
(`git tag -f 2.1.1`) makes GitHub regenerate the tag tarball and invalidates the
first digest even though `pkgver` has not moved.

## Package name

A package built from tagged sources takes the bare name. `-git` is for a rolling
build from a branch, and `-bin` is required only for a package built from
prebuilt deliverables - which is exactly why the prebuilt variant is named
`gibson-screensaver-bin` and not `gibson-screensaver`.

Checked live on 2026-09-11: the AUR RPC returns zero results for
`gibson-screensaver`, `gibson-screensaver-bin` and `gibson-screensaver-git`, so
the names are free.

```sh
curl -sS 'https://aur.archlinux.org/rpc/v5/info?arg[]=gibson-screensaver' | python3 -m json.tool
```

## The runbook (fallback: what the workflow automates)

Kept because it documents what [`aur.yml`](../../.github/workflows/aur.yml)
does, and because it is what to follow if the workflow is ever unavailable.
Steps 2-5 happen on an **Arch machine** (a VM or a container is fine; it just
has to have `pacman`, `makepkg` and `devtools`). Step 1 is the same one-time
account setup as above; step 6 is for users, not for you.

### 1. One-time account and SSH key

Register at <https://aur.archlinux.org/register>. This account is separate from
the Arch Linux BBS/wiki account.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/aur -C 'aur@archlinux.org'
```

Paste `~/.ssh/aur.pub` into <https://aur.archlinux.org/account> (My Account and
then SSH Public Key), then point ssh at that key:

```
# ~/.ssh/config
Host aur.archlinux.org
  IdentityFile ~/.ssh/aur
  User aur
```

Confirm the key works. A successful connection prints a greetings banner and
hangs up at once:

```sh
ssh aur@aur.archlinux.org help
```

### 2. Clone the (not yet existing) package repository

```sh
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/gibson-screensaver.git
cd gibson-screensaver
```

The clone works before the package exists and the warning it prints is expected:

```
warning: You appear to have cloned an empty repository.
```

`init.defaultBranch=master` matters: the AUR only accepts pushes to `master`. If
the clone is not on `master`, rename it with `git branch -m master`.

The commit author is your global Git identity. It is hard to change afterwards,
so set it per package if you push under different credentials:

```sh
git config user.name  'Paul Kiernan'
git config user.email 'paulkiernan1@gmail.com'
```

### 3. What the first commit must contain

`PKGBUILD`, `.SRCINFO`, the pacman install hook, and the package-source
licence. Copy all four of these from this repository:

```sh
cp /path/to/repo/packaging/aur/PKGBUILD /path/to/repo/packaging/aur/.SRCINFO .
cp /path/to/repo/packaging/aur/gibson-screensaver.install .
cp /path/to/repo/packaging/aur/LICENSE .
```

The `.install` file is not optional dressing: `makepkg` fails outright if the
file named by `install=` is missing, and the AUR only has the files you commit.
For `gibson-screensaver-bin` the hook is named
`gibson-screensaver-bin.install` instead, and everything else about the step is
the same.

**Why the `LICENSE` file is there.** This rule has changed over the years, so it
was checked against the live guidelines on 2026-09-11 rather than assumed. The
current *AUR submission guidelines* "Rules of submission" say:

> Add a `LICENSE` file and/or a [REUSE.toml](https://reuse.software/tutorial/)
> file to your repository.

and the upload checklist says to "add a package source license". The *Arch
package guidelines* § [Package sources
licenses](https://wiki.archlinux.org/title/Arch_package_guidelines#Package_sources_licenses)
fills in what that means: per [RFC40](https://rfc.archlinux.page/0040-license-package-sources/),
package sources are licensed `0BSD`, with a `LICENSE` file whose content is
exactly Arch's own [`data/LICENSE`](https://gitlab.archlinux.org/archlinux/devtools/-/blob/master/data/LICENSE)
from devtools. `packaging/aur/LICENSE` is a byte-identical copy of that file, so
committing it satisfies the rule. A `REUSE.toml` is the accepted alternative; if
you add one, `pkgctl license check` should pass.

This `LICENSE` is the licence of the **package sources** (the `PKGBUILD` and
friends). It is *not* the licence of the packaged software: that is the
`license=('GPL-3.0-or-later')` field inside the `PKGBUILD`, which is what ends up
at `/usr/share/licenses/gibson-screensaver/LICENSE`. Do not "correct" the
`license=` field to `0BSD`.

The first commit therefore looks like:

```sh
git add PKGBUILD .SRCINFO LICENSE
git commit -m 'Initial import: gibson-screensaver 2.1.1-1'
```

Do not push yet - test first.

### 4. Build and test on Arch

Regenerate `.SRCINFO` first, so the tested recipe and the tested metadata are the
same files that will be pushed:

```sh
updpkgsums                       # re-measures sha256sums in place
makepkg --printsrcinfo > .SRCINFO
```

Then build it against the host system, which is the quickest way to find a
missing `makedepends`:

```sh
makepkg -si
```

Then build it the way the AUR expects users and CI to - in a clean chroot, from
the extra repositories:

```sh
sudo pacman -S --needed devtools namcap
extra-x86_64-build
```

`extra-x86_64-build` sets up and updates a chroot under
`/var/lib/archbuild/extra-x86_64`, installs `makedepends` inside it, builds, and
runs `namcap` on the result; the package lands in the current directory.
`pkgctl build` is the newer spelling of the same thing.

Lint both the recipe and the built package and read the output rather than
skimming it:

```sh
namcap PKGBUILD
namcap gibson-screensaver-2.1.1-1-x86_64.pkg.tar.zst
```

The three classes of `namcap` finding that matter here:

- **missing** for an ELF soname - `depends` was derived by hand, because the
  binary `dlopen()`s nearly every library it uses and `namcap` only sees linked
  ones (see the `PKGBUILD` header). A missing entry here is a real bug;
- **unneeded** - an entry that should move to `optdepends`;
- a **file conflict** with `xscreensaver`, which would mean the load-bearing
  `gibson-screensaver` naming has been broken somewhere.

Then install the package and check the pieces by hand:

```sh
pacman -Ql gibson-screensaver                  # exactly the five paths above
command -v gibson-screensaver                  # /usr/bin/gibson-screensaver
pacman -Qo /usr/share/xscreensaver/config/gibson-screensaver.xml
gibson-screensaver --help
# the repository's own host test, against the installed binary
bash /path/to/repo/platform/linux/smoke-test.sh /usr/bin/gibson-screensaver
```

The host test needs an X server and a Vulkan driver. On a real desktop it uses
both for real, which is the first time this host has ever been exercised that
way - see [Honesty about the Linux host](#honesty-about-the-linux-host).

### 5. Regenerate `.SRCINFO` once more and push

If step 4 changed anything about the `PKGBUILD` (it should not have, except
possibly `pkgrel`), regenerate again. Then commit and push:

```sh
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO LICENSE
git commit -m 'gibson-screensaver 2.1.1-1'
git push origin master
```

`master` only. The package appears on <https://aur.archlinux.org/packages/gibson-screensaver>
once the repository holds a `PKGBUILD`.

### 6. What to tell users after installing

Installing the package does not turn the screen saver on. The user adds one line
to `~/.xscreensaver`:

```
programs: gibson-screensaver
```

No arguments, and in particular no `-root`. Two reasons, both from how
xscreensaver launches hacks:

- The daemon runs the `programs:` line verbatim and hands the window over in
  `$XSCREENSAVER_WINDOW`; it never appends a window-id argument.
  `xscreensaver-settings` appends `--window-id 0x<id>` itself when it builds the
  command for the embedded preview. The binary accepts either.
- `-root` exists in upstream xscreensaver hacks because they implement the
  xscreensaver protocol's root-window mode. This binary has no `-root` switch -
  it adopts the window it is given - so a `programs:` line carrying `-root` fails
  to start (clap rejects an unknown argument). The descriptor deliberately
  declares no `<command>` element for the same reason: whatever is in there is
  written into the `programs:` line and would break one of the two launch paths.

`xscreensaver` is an `optdepends`, not a dependency: the same binary is also a
standalone desktop app, and xscreensaver is X11-only. On a Wayland session the
supported route is fullscreen mode under `swayidle`:

```sh
swayidle -w timeout 600 'gibson-screensaver --fullscreen' resume 'pkill gibson-screensaver'
```

## The prebuilt package: gibson-screensaver-bin

**Recommendation: publish it, right after the source package.** The files are in
[`../aur-bin/`](../aur-bin/).

Why:

- The AUR requires the `-bin` suffix "for packages that use prebuilt
  deliverables, when the sources are available". The sources *are* available
  (that is the source package next to this one), so a package installing the
  release's Linux tarball **must** be named `gibson-screensaver-bin` - it is not
  optional naming.
- It removes the single biggest reason someone bounces off this package on Arch.
  wgpu + winit + ash + the rest of the tree is a long, memory-hungry Rust
  compile; a `-bin` install is a download and a copy. AUR users routinely look
  for `-bin` first for exactly this class of software.
- The cost is one extra `PKGBUILD` and `.SRCINFO` to bump per release, and the
  `updpkgsums` + `makepkg --printsrcinfo` pair is already in the release
  checklist, so the marginal effort is two file edits.
- The honest downside: the binary's provenance is the GitHub release workflow,
  not the user's own compiler, and a `-bin` package cannot be as tightly checked
  as a local build. That is inherent to `-bin`, and it is why the two packages
  are meant to coexist rather than replace each other.

The relationship between the two is handled with:

```
provides=('gibson-screensaver')
conflicts=('gibson-screensaver')
```

Both packages install `/usr/bin/gibson-screensaver` and the same descriptor, so
they must never be installed together (`conflicts`), and anything that depends on
`gibson-screensaver` can be satisfied by `gibson-screensaver-bin` alone
(`provides`). `replaces` is deliberately not used: AUR guidelines reserve it for
a rename, and `conflicts` is the less invasive, correct tool for two
alternatives.

Its `PKGBUILD` is nearly the source package's with a different `source`: the
Linux asset tarball, plus `LICENSE` from the same tag, because the asset tarball
itself carries no licence file. Test it the same way - `makepkg -si`,
`extra-x86_64-build`, `namcap`, and `makepkg --printsrcinfo > .SRCINFO`. Its own
AUR repository needs its own `LICENSE` too (it is a separate repository with its
own package sources), so copy the same `packaging/aur/LICENSE` file into it, and
copy `packaging/aur-bin/PKGBUILD` and `packaging/aur-bin/.SRCINFO`:

```sh
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/gibson-screensaver-bin.git
cd gibson-screensaver-bin
cp /path/to/repo/packaging/aur-bin/PKGBUILD /path/to/repo/packaging/aur-bin/.SRCINFO .
cp /path/to/repo/packaging/aur/LICENSE .
```

## Updating for a new release

Normally nothing is done in an AUR clone at all. The release commit bumps
`[workspace.package]` in `Cargo.toml`, and a second commit pins the packaging
to it - which is the commit that triggers the publish:

```sh
# in this repository, for each of packaging/aur and packaging/aur-bin:
# 1. edit pkgver= (and reset pkgrel=1)
updpkgsums                          # re-measures every sha256sum
makepkg --printsrcinfo > .SRCINFO   # must be regenerated, or CI fails
git commit -am 'build(packaging): pin every channel to <version>'
git push                            # main -> the AUR workflow publishes
```

`updpkgsums` needs the release assets to exist, so this comes *after* the
release workflow has published them. `-bin` additionally has a
`LICENSE-<pkgver>::` source whose digest `updpkgsums` refreshes, and the same
`pkgver` edit in two places.

To publish by hand instead, in each AUR clone on Arch:

```sh
updpkgsums && makepkg --printsrcinfo > .SRCINFO && makepkg -si
git commit -am 'upgpkg: gibson-screensaver <version>-1'
git push origin master
```

## Honesty about the Linux host

Stated at exactly the strength the evidence supports:

- The X11 / xscreensaver host **is smoke-tested in CI** on every push. The CI
  job runs it under Xvfb with Mesa's lavapipe software Vulkan rasteriser, adopts
  a real X window, exercises **both** launch paths (`$XSCREENSAVER_WINDOW` and
  `--window-id`), and asserts a nonzero presented-frame count on exit.
- It **has now run on real Linux hardware with a real GPU driver**, and **has**
  been driven by the xscreensaver daemon itself: Arch Linux, NVIDIA GeForce GTX
  1080 with the proprietary 580.159.04 driver, Vulkan backend. Both launch paths
  presented frames (384 and 346 in a recorded run) and the real `xscreensaver`
  daemon forked the hack onto its own window in a nested X server, with the
  rendered frame captured off that screen. `make smoke-linux` and
  `make daemon-linux` reproduce both.
- This package was also **built with `makepkg` on that machine**, `check()`
  included, and the runtime library set was confirmed by capturing
  `/proc/<pid>/maps` of the running binary and mapping every loaded object to
  its owning package — see the `depends` comment in the `PKGBUILD`.
- What is still uncovered: a build in a **clean chroot**, a **namcap** run,
  multi-GPU / hybrid setups, real multi-head Xinerama/RANDR layouts, and
  non-NVIDIA drivers on hardware. Step 4's hand check of the installed binary
  therefore still earns its place.

## Checking the two files agree

The check performed when these files were prepared, for both packages:

1. `bash -n PKGBUILD` (parse).
2. Source the `PKGBUILD` in a subshell and dump each field with `declare -p`,
   so the values and array element order come from bash, not from a re-reading
   of the file.
3. Parse `.SRCINFO` independently (skip comments; a non-indented line opens a
   section, a tab-indented `key = value` line appends to that key).
4. Compare the two field sets: the same keys, and the same values in the same
   order, allowing only for the two expansions `makepkg` performs
   (`$pkgname`/`$pkgver` in `source`) and for `pkgbase` repeating `pkgname` in
   the single-package case.

Both `.SRCINFO` files agreed with their `PKGBUILD`s on every field. On Arch this
whole question disappears: `makepkg --printsrcinfo > .SRCINFO` makes `.SRCINFO` a
projection of the `PKGBUILD` by construction, which is why step 5 regenerates it
one last time before the push.
