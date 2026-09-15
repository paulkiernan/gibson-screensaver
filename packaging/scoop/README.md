# Scoop: `gibson-screensaver.json`

A Scoop manifest for the Windows `.scr`, pinned to the release asset and its
published digest:

| Field | Value |
| --- | --- |
| Version | `2.1.1` |
| Asset | `Gibson.scr` (from release `2.1.1`) |
| SHA256 | `22f96ad6c15177f8ab977b2020a11472bcfb300ee7b463a6ce3988577f44b86f` |

The hash is the one GitHub's own `SHA256SUMS` asset carries for that release, not
a value computed from a local download, so it describes the bytes users actually
get. `Gibson.scr` is the release workflow's `target/release/gibson-app.exe`
copied byte for byte (`Copy-Item`).

`checkver` + `autoupdate` keep the manifest current: `checkver` follows GitHub's
"latest release" for the repository (prereleases are ignored, and this project
tags bare semver with no `v`), and `autoupdate` rebuilds the URL for the new tag
and re-reads the digest out of that release's `SHA256SUMS`:

```json
"hash": {
  "url": "https://github.com/paulkiernan/gibson-screensaver/releases/download/$version/SHA256SUMS",
  "find": "$sha256\\s+Gibson\\.scr"
}
```

To apply it by hand on a Windows box with Scoop installed:

```powershell
cd <bucket repo>
.\bin\checkver.ps1 gibson-screensaver -u
```

## Where a `.scr` has to live

From the documentation, without a Windows machine to try it on:

- **The active screen saver is a registry value, and that part is
  Microsoft-documented.** `HKCU\Control Panel\Desktop\SCRNSAVE.EXE` (REG_SZ)
  names it. Microsoft documents setting it from a file path with
  `rundll32.exe desk.cpl,InstallScreenSaver <file>`
  (<https://learn.microsoft.com/en-us/windows/win32/devnotes/scrnsave-exe>).
  Windows writes that value when you pick a saver in the UI and deletes it if you
  choose *(None)*, and Group Policy can supersede it.
- **The drop-down list is populated by scanning `%SystemRoot%\System32`.** Not
  stated by Microsoft anywhere I can find: it is what the community documents,
  what the shell's right-click **Install** verb does (copy the file into
  `System32`, then set the value), and what matches the behaviour on Windows
  10/11, so treat it as very likely rather than certain. On 64-bit systems
  `SysWOW64` is mentioned in some sources; a 64-bit `.scr` belongs in `System32`
  either way.
- **So a per-user Scoop install is not offered in Settings.** `Gibson.scr` lands
  in `%USERPROFILE%\scoop\apps\gibson-screensaver\<version>`, a directory Windows
  does not enumerate. What works straight away: double-clicking the file, or
  `Gibson.scr /s` (full screen) and `/c` (opens the settings file in the default
  editor) - both handled by the binary itself, see
  `crates/gibson-app/src/saver_args.rs`.

The manifest therefore installs the file, checks its digest, and - only for a
global install (`scoop install -g`, already elevated) - copies it into
`System32`, exactly as the shell's Install verb would, removing that copy on
uninstall. It writes no registry value: assigning a screen saver is something the
user does in Settings or through the documented `InstallScreenSaver` call, and a
mistake in that key is a support burden. It does not shim the `.scr` onto `PATH`
either - it is a screen saver, not a CLI tool people call by name.

## Route 1: personal bucket (works immediately)

Create a public GitHub repository named `scoop-bucket` (the name matters only in
that the bucket is added by URL, but that is what users expect), put the manifest
at the repository root as `gibson-screensaver.json`, and commit. That is the
whole publishing step - Scoop buckets are read straight out of the repository,
with no review and no signing gate. Users then:

```powershell
scoop bucket add paulkiernan https://github.com/paulkiernan/scoop-bucket
scoop install paulkiernan/gibson-screensaver
# or, to get the System32 copy so it appears in Screen Saver Settings,
# from an elevated PowerShell:
scoop install -g paulkiernan/gibson-screensaver
```

Tradeoff: the extra `scoop bucket add` line, and `scoop search` only finds it
within that bucket - in exchange for a manifest that is live the moment it is
pushed, and room to iterate without a review round-trip.

## Route 2: `ScoopInstaller/Extras`

Extras is the general-purpose official bucket: a pull request against
<https://github.com/ScoopInstaller/Extras> adding
`bucket/gibson-screensaver.json`. It wants a valid manifest (the bucket's CI
validates every manifest against its JSON schema), a working `checkver`, and the
acceptance criteria at
<https://github.com/ScoopInstaller/Scoop/wiki/Criteria-for-including-apps-in-the-main-bucket>.
Once `checkver` works the excavator autoupdates it hourly, so the manifest stops
needing hand-edits.

The real obstacle is not the schema: **a PR is expected to be tested on
Windows**, and these install and uninstall paths cannot be tested here. Ship the
personal bucket first, let real users hit it, then open the Extras PR with the
confidence those reports give you. The trade is reach for a review cycle, a
stricter `installer.script` bar, and a reviewer who may ask for the `System32`
copying to move into a documented, tested form.

## Updating for a new release

```powershell
# in the bucket clone, on Windows, with the manifest's version set back
.\bin\checkver.ps1 gibson-screensaver -u
# then check that url, hash and the version all moved together and install it
scoop install gibson-screensaver
scoop uninstall gibson-screensaver
```

If `checkver` is unavailable, bump `version`, the two URLs in `autoupdate`, and
`hash`, taking the new `hash` from the `SHA256SUMS` asset on that release rather
than from a local download.
