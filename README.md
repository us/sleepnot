# SLEEPNOT

Tiny macOS menu bar utility. Prevents idle system sleep while letting the display sleep normally. Sleep is for humans.

## Behavior

- **ON**: blocks idle system sleep via `ProcessInfo.beginActivity([.idleSystemSleepDisabled])`. The display can still turn off.
- **OFF**: normal macOS sleep behavior.

No window, no Dock icon (`LSUIElement`), no accounts, no network, no dependencies.

## Usage

- **Left click** the menu bar icon: toggle on/off indefinitely.
- **Right click** (or control+click): pick a duration (Indefinitely, 5 / 15 / 30 minutes, 1 / 2 / 5 hours) or quit.

The icon is hollow when OFF and filled when ON. Timed runs stop automatically and the icon flips back.

SLEEPNOT never blocks display sleep, never wakes a sleeping Mac, never touches lid-closed sleep, and holds no state between launches. Every launch starts OFF.

## Project

```
Sleepnot/
├── SleepnotApp.swift      # NSStatusItem, icon, menu (left toggle, right durations)
├── AwakeController.swift  # single ProcessInfo activity, optional timer
├── IconOff.png / IconOn.png
```

192 lines of Swift plus two icon files. No third-party code.

## Install

Via Homebrew (after the first GitHub Release):

```sh
brew install --cask ./Casks/sleepnot.rb
```

Or download `SLEEPNOT-<version>.zip` from Releases, unzip, move `SLEEPNOT.app` to Applications.

## Build from source

Requires Xcode on macOS 13+.

```sh
make build   # Release build into build/Release/SLEEPNOT.app
make verify  # static guarantees (no display assertion, agent-only app)
make zip     # distributable zip plus its sha256
open build/Release/SLEEPNOT.app
```

## Release process

1. Bump `MARKETING_VERSION` in the Xcode project.
2. Update `version` in `Casks/sleepnot.rb` to match.
3. Commit, tag `v<version>`, push the tag. The release workflow builds the zip and publishes the GitHub Release.
4. Run `make zip` locally, paste the printed sha256 into `Casks/sleepnot.rb`.

## Privacy

No network calls, no analytics, no file or process inspection, no special permissions. It creates one idle-sleep assertion while ON and removes it when OFF.

## License

MIT, see `LICENSE`.
