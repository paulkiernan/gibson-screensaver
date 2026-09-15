# Homebrew cask: `gibson-screensaver.rb`

A cask for my own tap, using the `screen_saver` stanza so `brew install --cask`
moves `Gibson.saver` into `~/Library/Screen Savers`.

| Field | Value |
| --- | --- |
| Version | `2.1.1` |
| Asset | `Gibson.saver.zip` from release `2.1.1` |
| SHA256 | `7a11cb1df741888e7908311b119478da91903c581cb2f2f46b2e900a9d2f86dc` |
| Minimum macOS | `>= :sonoma` (14.0), from the bundle's own `LSMinimumSystemVersion` |

The hash is the one in that release's published `SHA256SUMS`, so it describes the
bytes users download.

## Why a personal tap and not `homebrew/cask`

Two hard requirements stand in the way, either one disqualifying on its own:

1. **Gatekeeper.** `docs.brew.sh/Acceptable-Casks` requires that "apps,
   installers and other executable artefacts that Gatekeeper can assess must
   pass Homebrew's Gatekeeper checks and must not require System Integrity
   Protection or Gatekeeper to be disabled or bypassed". `Gibson.saver` is
   ad-hoc signed and **not notarized**, so a downloaded copy is quarantined and
   fails assessment; the only way to run it is to clear the quarantine flag,
   which is precisely the bypass that clause rules out. Notarization is
   mandatory for `homebrew/cask`, not a nice-to-have.
2. **Notability.** `docs.brew.sh/Package-Acceptance-Policy#notability` requires a
   new package to "demonstrate public interest beyond its author": at least 30
   forks, 30 watchers or 75 stars normally, and at least **90 forks, 90 watchers
   or 225 stars for a self-submission by the repository owner**. This repository
   has **17 stars, 3 forks and 1 watcher**, so a self-submission would be
   rejected on the numbers alone.

What would change it: notarize `Gibson.saver` with an Apple Developer ID (which
also removes the `xattr` step users need today), and grow past 225 stars or 90
forks or 90 watchers. A personal tap carries none of that - `brew tap` fetches a
plain GitHub repository, and casks in it install exactly like official ones - but
the caveats stay, because the quarantine problem is real either way.

## Publishing

The tap repository has to be named `homebrew-<tap>` - `brew tap paulkiernan/tap`
resolves to `paulkiernan/homebrew-tap`. Create it, then:

```sh
git clone git@github.com:paulkiernan/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks/h
cp /path/to/packaging/homebrew/gibson-screensaver.rb Casks/h/
git add Casks/h/gibson-screensaver.rb
git commit -m 'gibson-screensaver 2.1.1'
git push
```

`Casks/h/gibson-screensaver.rb` mirrors the layout `homebrew-cask` itself uses -
casks live under a directory named for the first letter of the token. A tap also
accepts the file at the repository root, but matching the official layout keeps a
later move to `homebrew/cask` a straight copy.

Users then run:

```sh
brew tap paulkiernan/tap
brew install --cask paulkiernan/tap/gibson-screensaver
```

After a new release, bump `version` and `sha256` together, taking the digest from
the release's own `SHA256SUMS` rather than from a local download:

```sh
shasum -a 256 Gibson.saver.zip    # or read the value out of the release's SHA256SUMS
```

`brew audit --cask` and `brew style` are worth running for tidiness, though
`audit` will complain about things only required in `homebrew/cask` - a `url`
whose host does not match `homepage`, and the quarantine caveat. Neither is a
correctness problem in a tap.

## What the cask does

- `screen_saver "Gibson.saver"` installs the bundle into `~/Library/Screen
  Savers`. The stanza's path is relative to the unpacked archive, which contains
  exactly one top-level item: `Gibson.saver`.
- `depends_on macos: :sonoma` matches the bundle's `LSMinimumSystemVersion` of
  14.0 and the `macos-15` runner the release is built on. The symbol form is
  required: Homebrew deprecated the string comparison form (`">= :sonoma"`), and
  `brew tap` warns and names the line, while `ruby -c` accepts the deprecated
  form happily.
- The bundle's display name is **"The Gibson"** (`CFBundleName` and
  `CFBundleDisplayName` in `platform/macos/Info.plist`), which is the name the
  System Settings list shows, hence `name "The Gibson"` rather than the project
  name.
- `zap` removes the desktop app's config directory
  (`~/Library/Application Support/gibson-screensaver`, the path
  `crates/gibson-app/src/config.rs` uses) and the saver's preferences domain. The
  saver stores its options through `ScreenSaverDefaults` under the bundle
  identifier `org.hackthegibson.TheGibson`
  (`platform/macos/Sources/Settings.swift`), which is the domain the plist path
  is derived from. That identifier still says `hackthegibson`: the project rename
  changed the repository and the product name, not the bundle identifier, and
  changing it would strand every existing user's saved options. Leave it alone.
