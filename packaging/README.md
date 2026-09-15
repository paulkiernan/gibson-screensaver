# Publishing `gibson-screensaver`

Everything needed to get the project into the distribution channels worth the
effort, plus the runbook for each. Three directories here hold files to be
submitted; two further channels need no files at all and are at the end.

## The release these files pin

Every file here pins release **`2.1.1`**, published 2026-09-11. A release is
created by pushing a bare-semver tag, which runs `.github/workflows/release.yml`
and publishes these assets - the list in that workflow's `RELEASE_ASSETS` is the
single source of truth, so if an asset is ever renamed, every file in this
directory needs a matching edit:

| Asset | Consumed by |
| --- | --- |
| `Gibson.saver.zip` | the Homebrew cask, Screensavers Planet, the awesome list |
| `Gibson.scr` | the Scoop manifest |
| `gibson-screensaver-linux-x86_64.tar.gz` | the AUR `-bin` package (`packaging/aur-bin/`); the source package builds from the tag tarball instead |
| `gibson-screensaver-macos-universal.tar.gz` | nothing here |
| `gibson-screensaver-web.zip` | nothing here |
| `SHA256SUMS` | the hash source for the Scoop and Homebrew manifests |

The AUR gets **two** packages. `aur/PKGBUILD` builds from the **tag tarball**
(`.../archive/refs/tags/2.1.1.tar.gz`), not from
`gibson-screensaver-linux-x86_64.tar.gz`, and that is what lets it take the bare
name `gibson-screensaver`: the AUR reserves `-bin` for packages built from
prebuilt deliverables when the sources are available, and here they are.
`aur-bin/` is the prebuilt variant and therefore *must* carry the suffix - it
installs the Linux tarball, saves the user a Rust compile, and
`provides`/`conflicts` with the source package. The reasoning, and why both are
worth publishing, is in
[`aur/README.md`](aur/README.md#the-prebuilt-package-gibson-screensaver-bin).

## The order to do them in

1. **Screensavers Planet + `awesome-macos-screensavers`** - no file here, no
   account gate, minutes of work. Do these first; see the last section.
2. **Scoop, personal bucket** - [`scoop/`](scoop/). No review, no code-signing
   gate, no admin rights for the default install, and the manifest goes live the
   moment a two-file repository is pushed.
3. **Homebrew, personal tap** - [`homebrew/`](homebrew/). Same shape - a tap is a
   GitHub repository, so there is no review - but the cask's url and digest need
   the release to exist first (it does).
4. **AUR, source package** - [`aur/`](aur/). The largest audience for a Linux
   screensaver, and the only channel here whose package other people will
   rebuild. Build it in a clean chroot and read `namcap`'s output before pushing;
   the runbook is in [`aur/README.md`](aur/README.md).
5. **AUR, `-bin` package** - [`aur-bin/`](aur-bin/). Publish it immediately after
   the source package: same program, prebuilt binary, `provides`/`conflicts` with
   the source package. Rationale in
   [`aur/README.md`](aur/README.md#the-prebuilt-package-gibson-screensaver-bin).

Two further channels are worth doing *after* those, in this order, because both
need something that does not exist yet:

- **`ScoopInstaller/Extras`**: a PR is expected to have been tested on Windows,
  and this manifest's install/uninstall scripts have never run. Ship the personal
  bucket, collect real reports, then submit. Details in
  [`scoop/README.md`](scoop/README.md).
- **`homebrew/cask`**: blocked by two independent requirements - notarization,
  and the notability thresholds for a self-submission (90 forks, 90 watchers or
  225 stars; the repository has 17/3/1). Both are explained in
  [`homebrew/README.md`](homebrew/README.md).

## Channels not pursued

Not pursued: **winget** (no `.scr` installer type exists, and the catalog wants a
wrapped, signed installer validated on Windows - Scoop reaches the same users
today), **Flathub** (this renders into a window another process owns rather than
living in its own container, so the sandbox model fights the design, and Flathub
forbids AI-generated submissions), **MacUpdate** (a curated listing rather than a
distribution path), **SourceForge** (a mirror that rewraps downloads with its own
installer and adds nothing the GitHub release does not already provide), and
**Softpedia** (same shape as SourceForge, plus another signing gate).

## The two channels that need no packaging files

### Screensavers Planet

Submission form: <https://www.screensaversplanet.com/about/submit>

Send `Gibson.saver.zip` (7.0 MiB, well under their 100 MB limit) and, since the
form invites them, a screenshot. Their rules are that the file contains no adware
or viruses and that the submitter has the right to distribute it - both true here,
GPL-3.0-or-later and the project's own source. Say in the submission note that the
saver is ad-hoc signed and not notarized, so a downloaded copy needs one
`xattr -dr com.apple.quarantine` command before it will draw: their reviewers do
check downloads, and it is better they hear it from us than conclude the saver is
broken. Include the GitHub release link as the canonical download too, so future
versions track there.

### `awesome-macos-screensavers`

Pull request against <https://github.com/agarrharr/awesome-macos-screensavers>.
Per its `contributing.md`: one suggestion per PR, additions at the bottom of the
relevant category, and the entry format is a heading, a one-line description
starting with a capital and ending with a full stop, an optional price line, and
a screenshot link. The project belongs under **Sci-Fi**:

```markdown
### The Gibson

> Tower-city flythrough from the 1995 film Hackers, recreated with wgpu.

Free (Open Source)

[![](screenshots/the-gibson.png)](https://github.com/paulkiernan/gibson-screensaver)
```

The screenshot has to be committed to that repository, resized to 1000px wide as
the guide asks. This repository already has a suitable image, so no capture is
needed:

```sh
sips -Z 1000 platform/macos/thumbnail.png --out screenshots/the-gibson.png
```

In the PR description, give the link, why it belongs (a real 3D flythrough, not
another clock, and the only one built on wgpu), and the same quarantine
disclosure as above so the reviewer is not surprised by a Gatekeeper warning.

## Keeping the files in step with a release

On a new tag, in one pass:

```sh
# AUR - source package
cd <aur clone>
# editor: pkgver=2.1.1, pkgrel=1
updpkgsums
makepkg --printsrcinfo > .SRCINFO
# AUR - bin package, in its own clone (pkgver in one place, both digests refreshed)
cd <aur-bin clone>
updpkgsums
makepkg --printsrcinfo > .SRCINFO

# Scoop (on Windows, in the bucket clone)
.\bin\checkver.ps1 gibson-screensaver -u

# Homebrew cask: bump version and sha256 together, sha256 from the release's SHA256SUMS
```

Every digest in these files was measured from the published asset, not copied
from a build log, and `.SRCINFO` must be regenerated on Arch (never hand-edited)
whenever a `PKGBUILD` field it carries changes - forgetting that is the most
common way an AUR page goes stale. The tag and the `[workspace.package]` version
in `Cargo.toml` are asserted equal by the release workflow's guard job, and the
tag has no `v` prefix, so the version string in all three manifests is the tag
verbatim.

None of this can be built or installed on the machine it was prepared on: no Arch
Linux, no pacman, no makepkg, no Windows, no Homebrew tap - which is why each
subdirectory's README is careful about what has actually been run.
