# ProTech Support

The remote-support app of [ProTech IT Solutions](https://protechitsolutions.com.au). Customers download it from https://support.prtch.com.

It is [RustDesk](https://github.com/rustdesk/rustdesk) 1.5.3 (AGPL-3.0, Copyright Purslane Tech Pte. Ltd.) with a small set of ProTech changes.
This repository holds **those changes and the scripts that build them**, so anyone can get the exact source of the apps we give to customers
(the AGPL "Corresponding Source"). The upstream code itself is not copied here: it is fetched from RustDesk at the commit recorded in [`BASE.txt`](BASE.txt).

## What is different from upstream

| Patch | What it does |
|---|---|
| `patches/hbb_common/0001`, `0002` | Fail-closed defaults: the app can never fall back to RustDesk's public servers or the RustDesk name, and never registers the computer with an API server unless ProTech's settings say so. |
| `patches/main/0001` | Drops the hardware-codec libraries (ffmpeg) from the dependency list, so the app builds with software codecs only. |
| `patches/main/0002` | Settings files (`custom.txt`) are accepted only when signed with **ProTech's own key**; upstream's key is replaced. |
| `patches/main/0003` | ProTech look (theme, icons, About page with a link to this source), Windows file properties. |
| `patches/main/0004` | **macOS only.** Visible name "ProTech Support", its own bundle id and URL scheme (so it never collides with a stock RustDesk on the same Mac), no "install the service" card. |

The Windows apps are built from patches 0001-0003; the Mac app also applies 0004.

## How the customer app is locked down

The settings live in a signed file next to the program (`variants/customer.json` shows them, with the server details filled in from `config/server.json`):
**incoming connections only; the customer must click Accept for every session**; no session recording, camera, terminal, port forwarding, remote printing,
remote restart, input blocking or privacy mode; no unattended access; server, network and security settings hidden; no automatic update.
When it runs it tells ProTech's server the computer name, Windows/Mac user name, system version, processor and memory size, app version and
internet address so a technician can see which computer is theirs (details: https://protechitsolutions.com.au/remote-support).

## Get the exact source

```
scripts/assemble-source.sh <empty-directory> [--mac]
```

It fetches upstream at the recorded commit (and the `hbb_common` submodule), applies the patches and **checks the result against the git tree hashes
in `BASE.txt`**. If the hashes match, you have precisely what the Windows apps were built from.

## Build

* **Windows:** built on a Windows PC from the assembled source with the toolchain in the RustDesk build documentation (Flutter 3.24.5, Rust 1.75, vcpkg), without `--hwcodec`.
* **Mac:** GitHub Actions workflow *Build ProTech Support for Mac* (`.github/workflows/build-mac.yml`): the macOS part of upstream's own workflow, same pinned actions and
  tool versions, building Apple-chip and Intel apps on GitHub's Macs. Then `scripts/package-mac.sh` on any Mac renames the app, adds the signed settings file,
  signs it "ad hoc" and zips it. The Mac app is **not notarised by Apple**, so macOS asks the customer to approve it once
  (System Settings > Privacy & Security > Open Anyway); https://support.prtch.com explains the steps.

## What is not in this repository

The private key that signs the settings file, the server's private key, and ProTech's server configuration. Nothing here is secret: if you can read it, so can everyone.

## Licence

GNU Affero General Public License v3.0 (see `LICENSE`), the same as RustDesk.
