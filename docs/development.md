# Local development: build, run, install, lint

Hard-won notes for hacking on this fork without losing hours to packaging
issues. TL;DR: **use `./dev.sh`**, and **test by running from the repo, not by
installing into system dirs.**

## The golden rule: run from the repo

The project's own CI runs the shell like this:

```bash
QML2_IMPORT_PATH="$PWD/build/qml" qs -p .
```

That is the canonical dev loop. It runs *our* `shell.qml` with *our*
freshly-built C++ plugins from `build/qml`, on the QML import path — no `sudo`,
no system directories, no conflict with the AUR `caelestia-shell-git` package.

`./dev.sh run` does exactly this (after building).

## Build

```bash
./dev.sh build        # cmake configure (Release, prefix /) + ninja build
```

Plain CMake under the hood:

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
cmake --build build
```

Only C++ changes (anything under `plugin/`) need a rebuild. Pure-QML changes are
picked up by re-running the shell.

## ⚠️ Two traps that cost us a long debugging session

### 1. A Qt point-release update breaks everything until rebuilt
Quickshell and the Caelestia C++ plugins are compiled against a specific Qt
version. When the system updates Qt (e.g. 6.11.0 → 6.11.1), on the next restart
you'll get cascading `Type X unavailable` / `... is not a type` errors and a
warning that quickshell was built against the old Qt.

Fix, in order:
1. Rebuild **quickshell** against the new Qt (it's your AUR package, e.g.
   `yay -S quickshell-git`).
2. `./dev.sh clean && ./dev.sh build` to rebuild the plugins against the new Qt.

### 2. `sudo cmake --install` can leave a MISMATCHED plugin set
CMake's install compares timestamps at **whole-second** granularity. If a
freshly-built `.so` has the same second as the installed one, install reports
`-- Up-to-date` and **skips it** — even though the bytes differ. You then end up
with, say, a new `libcaelestia-componentsplugin.so` next to an old
`libcaelestia-components.so` base lib. The plugin loads but its C++ types fail to
register, giving the misleading **`ButtonRow is not a type`** at QML load.

This is exactly why the golden rule is "run from the repo". If you *do* need a
system install (to use `caelestia shell -d` for daily driving), use
`./dev.sh install`, which `touch`es all build artifacts first so every file is
unambiguously newer and actually gets copied. A nuclear option is:

```bash
sudo rm -rf /usr/lib/qt6/qml/Caelestia && sudo cmake --install build
```

### Note on the AUR package
This machine also has `caelestia-shell-git` installed from the AUR. It is a
separate install of the same shell and does **not** contain our changes. For
development, ignore it and use the repo-run loop; for daily use, either keep the
AUR package or do a clean `./dev.sh install`.

## Lint & format (matches CI)

```bash
./dev.sh lint
```

Runs the same three tools the CI does:
- **`qmlformat`** — every `.qml` must be idempotent (`qmlformat f | diff f -`).
- **`clang-format --dry-run --Werror`** — C++ under `plugin/` (`.clang-format`).
- **`qmllint`** — with import paths taken from a generated `.qmlls.ini` (created
  by briefly running the shell, as CI does).

Caveat: `qmlformat`'s output can differ between Qt versions, so `dev.sh lint`
may flag upstream files you never touched (e.g. `services/NotifData.qml`) purely
due to local-vs-CI version drift. Focus on the files **you** changed; the CI uses
a pinned toolchain image and is the source of truth.

## Install (only if you want the system `caelestia shell -d`)

```bash
./dev.sh install      # build + force-copy install to / (asks for sudo)
caelestia shell -d
```

Installs QML to `/etc/xdg/quickshell/caelestia`, plugins to
`/usr/lib/qt6/qml/Caelestia`, libs to `/usr/lib/caelestia`.

## After a Qt update — full reset

```bash
yay -S quickshell-git           # rebuild quickshell against new Qt
./dev.sh clean && ./dev.sh run  # rebuild plugins, run from repo
```
