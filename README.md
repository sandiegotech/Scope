# Disko

Disko is a lightweight native macOS menu bar utility for quick computer metrics with a storage-first point of view.

## Run

```sh
swift run Disko
```

The app appears in the macOS menu bar as a quiet Disko icon with small load bars and opens a compact dashboard for live system metrics.

## Icon

```sh
swift scripts/make-icon.swift
iconutil -c icns Support/Disko.iconset -o Support/Disko.icns
```

## Build a Local App Bundle

```sh
./scripts/build-app.sh
open Build/Disko.app
```

## Current Scope

- Menu bar item uses the Disko disk mark with visual load bars, not changing numbers.
- Popover dashboard highlights battery/power state, top estimated app pull, CPU/GPU separation, memory, network, and storage.
- Detail window includes power, storage cleanup candidates, power-impact apps, high-memory apps, network links, active TCP destinations, battery health, thermal state, power mode, GPU, and system status.
- Deep scans are throttled so storage and network discovery do not run every second.
- Public macOS APIs only, so GPU usage is shown as GPU identity/status rather than private per-GPU utilization.
- No background services, accounts, onboarding, or heavy setup.
