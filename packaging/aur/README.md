# AUR: `gibson-screensaver`

Everything an AUR push needs. The `PKGBUILD` here builds the project from the
GitHub tag tarball and installs

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

[`.github/workflows/aur.yml`](../../.github/workflows/aur.yml) is the publishing
path. A commit on `main` that changes a `PKGBUILD`, a `.SRCINFO` or an install
hook in this directory or `../aur-bin/` makes it:

1. regenerate `.SRCINFO` with `makepkg --printsrcinfo` and fail if the committed
   one differs;
2. check `pkgver` equals the `[workspace.package]` version in `Cargo.toml`,
   because the release tag is that version and both packages build that tag's
   artifacts;
3. run `makepkg --verifysource`, which downloads every `source` and checks it
   against `sha256sums` - so a `pkgver` bump whose digests were not recomputed
   fails here;
4. `namcap` the `PKGBUILD`, build the package, and `namcap` the result;
5. extract the built package and run the installed binary;
6. push to `ssh://aur@aur.archlinux.org/<pkgname>.git`, and only if all of the
   above passed.

It runs in an `archlinux:base-devel` container holding only the declared
dependencies, so a missing `depends` entry fails there instead of passing on a
machine that happened to have the library. `workflow_dispatch` does the same
work with `dry_run` defaulting to true, so it publishes nothing.

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

   The optional repository *variables* `AUR_GIT_NAME` and `AUR_GIT_EMAIL` set
   the identity on the AUR-side commits; they default to the maintainer line in
   the `PKGBUILD`.

Until the secret exists the workflow still validates and builds both packages -
only the push is skipped, with a notice saying why. The AUR host key is pinned
in the workflow (`SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4`), not
accepted on first use.

### Where this stands

> As of 2026-09-15 the AUR is not accepting new accounts:
>
> > New account registration is temporarily closed. Registration on the AUR is
> > paused while we deal with a wave of automated account creation. [...]
> > There's no manual registration queue [...]
> > (HTTP 503)

So step 1 cannot be completed yet and neither package is on the AUR. Nothing
else is blocking: both packages validate and build in CI today, and the names
`gibson-screensaver` and `gibson-screensaver-bin` are unclaimed.

`AUR_SSH_PRIVATE_KEY` is intentionally **not** set while this lasts: the secret
is what turns the push on, and setting it before an account exists would only
turn every packaging commit red on an `ssh` permission denied CI cannot act on.
Unset, the workflow ends green on that notice.

When registration reopens, [`enable-publishing.sh`](enable-publishing.sh) is the
rest of the work. It generates the key if it is missing, tells you which public
key to paste on the account, sets the secret once the key authenticates, runs
the workflow for real, and checks that **both** packages appeared:

```sh
packaging/aur/enable-publishing.sh --check   # where things stand, changes nothing
packaging/aur/enable-publishing.sh           # do it
```

No code change is needed, and the script does not poll the registration page -
Arch asks people not to, so watch `aur-general` or the Arch news feed instead.

## `.SRCINFO` is generated

**Every `PKGBUILD` edit that touches a field appearing in `.SRCINFO` requires
regenerating it** (`pkgver`, `pkgrel`, `source`, `sha256sums`, `depends`,
`makedepends`, `optdepends`, `provides`, `conflicts`, `pkgdesc`, `arch`,
`license`, `install`):

```sh
makepkg --printsrcinfo > .SRCINFO
```

A stale `.SRCINFO` is the most common reason an AUR page shows the wrong
version, and it fails step 1 of the workflow.

## Digests

All three measured with `updpkgsums` from the published bytes; the release's own
`SHA256SUMS` gives the same asset digests, which is the cross-check.

| Source in the `PKGBUILD`s | SHA256 |
| --- | --- |
| `.../archive/refs/tags/2.1.2.tar.gz` (source package) | `2d792936c551ec259a474fddf36af22ed0f511f3a198190886c2d1a58563b0fb` |
| `.../releases/download/2.1.2/gibson-screensaver-linux-x86_64.tar.gz` (-bin) | `483ac51e5d17e8991cd6cdefe1e4deed83f4deecb1deb987566abef7ff894246` |
| `.../raw/.../2.1.2/LICENSE` (-bin, the asset tarball carries no licence file) | `0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b` |

The LICENSE digest is unchanged from 2.1.1, which is expected - the file did not
change between the tags.

`updpkgsums` re-measures these; run it after any `source` change. A force-retag
(`git tag -f 2.1.2`) makes GitHub regenerate the tag tarball and invalidates the
first digest even though `pkgver` has not moved.

## Package name

A package built from tagged sources takes the bare name. `-git` is for a rolling
build from a branch, and `-bin` is required only for a package built from
prebuilt deliverables - which is why the prebuilt variant is named
`gibson-screensaver-bin` and not `gibson-screensaver`. The AUR RPC returns zero
results for `gibson-screensaver`, `gibson-screensaver-bin` and
`gibson-screensaver-git`, so all three names are free:

```sh
curl -sS 'https://aur.archlinux.org/rpc/v5/info?arg[]=gibson-screensaver' | python3 -m json.tool
```

## The runbook, for when the workflow is not available

The same thing by hand, on an Arch machine - a VM or a container is fine, it
just needs `pacman`, `makepkg` and `devtools`.

**1. Account and key** - the one-time setup above - with an ssh config so the
right key is picked up:

```
# ~/.ssh/config
Host aur.archlinux.org
  IdentityFile ~/.ssh/aur
  User aur
```

**2. Clone the not-yet-existing package repository.** The clone works before the
package exists, and its warning is expected. `master` only, so run
`git branch -m master` if the clone is not on it:

```sh
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/gibson-screensaver.git
cd gibson-screensaver
```

**3. The first commit** is `PKGBUILD`, `.SRCINFO`, the pacman install hook and
the package-source licence:

```sh
cp /path/to/repo/packaging/aur/PKGBUILD /path/to/repo/packaging/aur/.SRCINFO .
cp /path/to/repo/packaging/aur/gibson-screensaver.install .
cp /path/to/repo/packaging/aur/LICENSE .
git add PKGBUILD .SRCINFO LICENSE
git commit -m 'Initial import: gibson-screensaver 2.1.1-1'
```

`makepkg` fails outright if the file named by `install=` is missing, and the AUR
only has the files you commit; `-bin`'s hook is
`gibson-screensaver-bin.install`. That `LICENSE` is the licence of the **package
sources**, not of the software:
[RFC40](https://rfc.archlinux.page/0040-license-package-sources/) makes package
sources `0BSD`, and this is the file devtools ships for that (a `REUSE.toml` is
the accepted alternative). The software's licence is
`license=('GPL-3.0-or-later')` in the `PKGBUILD`, which is what lands in
`/usr/share/licenses/` - do not "correct" that field to `0BSD`.

Do not push yet - test first.

**4. Build, lint, install**, in a clean chroot the way users and CI get it,
after the quick host build that finds a missing `makedepends` fastest:

```sh
updpkgsums                       # re-measures sha256sums in place
makepkg --printsrcinfo > .SRCINFO
makepkg -si

sudo pacman -S --needed devtools namcap
extra-x86_64-build
namcap PKGBUILD
namcap gibson-screensaver-2.1.1-1-x86_64.pkg.tar.zst
```

`extra-x86_64-build` sets up and updates a chroot under
`/var/lib/archbuild/extra-x86_64`, installs `makedepends` inside it, builds and
runs `namcap` on the result; the package lands in the current directory
(`pkgctl build` is the newer spelling). In namcap's output, **missing** for an
ELF soname is a real bug - `depends` is hand-written because the binary
`dlopen()`s nearly every library it uses and namcap only sees linked ones -
**unneeded** means an entry belongs in `optdepends`, and a **file conflict**
with `xscreensaver` would mean the `gibson-screensaver` naming has been broken
somewhere.

Then check the installed pieces, including the host test, which needs an X
server and a Vulkan driver:

```sh
pacman -Ql gibson-screensaver                  # exactly the five paths above
command -v gibson-screensaver                  # /usr/bin/gibson-screensaver
pacman -Qo /usr/share/xscreensaver/config/gibson-screensaver.xml
gibson-screensaver --help
# the repository's own host test, against the installed binary
bash /path/to/repo/platform/linux/smoke-test.sh /usr/bin/gibson-screensaver
```

This host is tested on real hardware - Arch, an NVIDIA GTX 1080 with the
proprietary 580.159.04 driver, and the real `xscreensaver` daemon - and CI
smoke-tests it under Xvfb on every push; the setup and the numbers are in
[platform/linux/README.md](../../platform/linux/README.md).

**5. Regenerate `.SRCINFO` once more and push.**

```sh
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO LICENSE
git commit -m 'gibson-screensaver 2.1.1-1'
git push origin master
```

`master` only. The package appears on
<https://aur.archlinux.org/packages/gibson-screensaver> once the repository
holds a `PKGBUILD`.

**6. What to tell users after installing.** Installing the package does not turn
the screen saver on; one line in `~/.xscreensaver` does:

```
programs: gibson-screensaver
```

No arguments, and in particular no `-root`: the daemon runs that line verbatim
and hands the window over in `$XSCREENSAVER_WINDOW`, while
`xscreensaver-settings` appends `--window-id 0x<id>` itself for its embedded
preview, and this binary accepts either. `-root` only exists in upstream hacks
because they implement the protocol's root-window mode, and the descriptor
declares no `<command>` element for the same reason: whatever is in there is
written into the `programs:` line and breaks one of the two launch paths.

`xscreensaver` is an `optdepends` - the same binary is a standalone desktop app
too, and xscreensaver is X11-only. On Wayland:

```sh
swayidle -w timeout 600 'gibson-screensaver --fullscreen' resume 'pkill gibson-screensaver'
```

## The prebuilt package: gibson-screensaver-bin

Publish it right after the source package; the files are in
[`../aur-bin/`](../aur-bin/). The AUR requires the `-bin` suffix "for packages
that use prebuilt deliverables, when the sources are available", and they are
available - they are the source package next to this one. It costs one extra
`PKGBUILD` and `.SRCINFO` to bump per release and saves the user a long,
memory-hungry wgpu + winit + ash compile, which is the main thing AUR users look
to avoid for this class of software.

The relationship between the two is handled with:

```
provides=('gibson-screensaver')
conflicts=('gibson-screensaver')
```

Both packages install `/usr/bin/gibson-screensaver` and the same descriptor, so
they must never be installed together (`conflicts`), and anything that depends
on `gibson-screensaver` can be satisfied by `gibson-screensaver-bin` alone
(`provides`). `replaces` is not used: AUR guidelines reserve it for a rename, and
`conflicts` is the right tool for two alternatives.

Its `PKGBUILD` is nearly the source package's, with a different `source`: the
Linux asset tarball, plus `LICENSE` from the same tag, because the asset tarball
carries no licence file. Test it the same way - `makepkg -si`,
`extra-x86_64-build`, `namcap`, `makepkg --printsrcinfo > .SRCINFO` - then copy
the same `LICENSE` into its own AUR repository:

```sh
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/gibson-screensaver-bin.git
cd gibson-screensaver-bin
cp /path/to/repo/packaging/aur-bin/PKGBUILD /path/to/repo/packaging/aur-bin/.SRCINFO .
cp /path/to/repo/packaging/aur/LICENSE .
```

## Updating for a new release

Normally nothing is done in an AUR clone at all. The release commit bumps
`[workspace.package]` in `Cargo.toml`, and a second commit pins the packaging to
it - which is the commit that triggers the publish:

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
