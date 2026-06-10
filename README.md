# Scope

Scope is a lightweight native macOS menu bar utility for quick computer metrics with a storage-first point of view.

## Run

```sh
swift run Scope
```

The app appears in the macOS menu bar as a quiet Scope icon with small load bars and opens a compact dashboard for live system metrics.

## Icon

```sh
swift scripts/make-icon.swift
iconutil -c icns Support/Scope.iconset -o Support/Scope.icns
```

## Build a Local App Bundle

```sh
./scripts/build-app.sh
open Build/Scope.app
```

## Current Scope

- Menu bar item uses the Scope disk mark with visual load bars, not changing numbers.
- Popover dashboard highlights battery/power state, top estimated app pull, CPU/GPU separation, memory, network, and storage.
- Detail window includes power, storage cleanup candidates, power-impact apps, high-memory apps, network links, active TCP destinations, battery health, thermal state, power mode, GPU, and system status.
- GitHub Sync tab reads the hidden `.repo-sync` manifests in `/Users/megalith2/Documents/GitHub`, shows clean/changed/ahead/behind repo status, and can fetch or sync the tracked work repos.
- Deep scans are throttled so storage and network discovery do not run every second.
- Public macOS APIs only, so GPU usage is shown as GPU identity/status rather than private per-GPU utilization.
- No background services, accounts, onboarding, or heavy setup.
