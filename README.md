<!-- SDIT Tools · Scope -->

# Scope

**Performance & System Health for macOS** — a tool from the [San Diego Institute of Technology](https://sandiegotech.org).

Scope is a lightweight, native menu-bar utility: a quiet icon with small load bars, a
compact dashboard of live system metrics, and a storage-first view of where your disk
actually went. Battery and power draw, CPU and GPU, memory pressure, network
destinations, and thermal state — without opening Activity Monitor, and without the
tool that watches your machine becoming the thing that slows it down.

> Part of [**SDIT Tools**](https://sandiegotech.org/tools/) — free, open-source software
> built for focus, privacy, and performance in the age of AI.
> **Free · Open Source · MIT Licensed · No accounts, no feed, no algorithm.**

Platforms: **macOS**

## Status — in testing

Scope is **currently in testing and not yet distributed through the App Store**. It
builds and runs today, and test builds go out to early testers as we polish it toward
release. If you would like to test it, write to
[brandon@sandiegotech.org](mailto:brandon@sandiegotech.org?subject=Scope%20Testing) and
we'll get you set up. Blunt feedback and bug reports are the most useful contribution
at this stage. You can also build and run it from source in under a minute — see below.

## Run

```sh
swift run Scope
```

The app appears in the macOS menu bar as a quiet Scope icon with small load bars and
opens a compact dashboard for live system metrics.

## Build a Local App Bundle

```sh
./scripts/build-app.sh
open Build/Scope.app
```

## Icon

```sh
swift scripts/make-icon.swift
iconutil -c icns Support/Scope.iconset -o Support/Scope.icns
```

## What it shows

- Menu bar item uses the Scope disk mark with visual load bars, not changing numbers.
- Popover dashboard highlights battery/power state, top estimated app pull, CPU/GPU
  separation, memory, network, and storage.
- Detail window includes power, storage cleanup candidates, power-impact apps,
  high-memory apps, network links, active TCP destinations, battery health, thermal
  state, power mode, GPU, and system status.
- GitHub Sync tab can read optional `.repo-sync` manifests in a local GitHub folder,
  show clean/changed/ahead/behind status, and fetch or sync tracked work repos.
- Deep scans are throttled so storage and network discovery do not run every second.
- Public macOS APIs only, so GPU usage is shown as GPU identity/status rather than
  private per-GPU utilization.
- No background services, accounts, onboarding, or heavy setup.

---

© San Diego Institute of Technology · 501(c)(3) nonprofit · Released under the MIT License.
