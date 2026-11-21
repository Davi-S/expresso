# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.0] - 2026-11-21

### Added

- `status --notify` also shows the lock's state as a desktop notification, for
  keybindings: "Expresso on" with `Until 15:40 (29m left) - idle`, or
  "Expresso off" with `No lock is on`. The output and exit code are those of
  `status`.

### Changed

- The "Expresso on" notification separates the extras with a plain hyphen
  (` - `) instead of a middle dot: `Until 15:40 - lid, idle`.

## [2.0.0] - 2026-09-29

A ground-up rewrite. **Not compatible with 1.x**: commands, options and output
all changed, and the configuration file is gone.

### Changed

- Commands are now `on DURATION [--lid] [--idle]`, `off` and `status`
  (were `start`, `stop`, `status`).
- `DURATION` is whole seconds, and required; `0` means until `off`
  (was minutes by default, with units, and `inf`/`infinite`).
- `status` prints `key=value` lines (`state`, `duration`, `started`, `until`,
  `remaining`, `lid`, `idle`) and exits 0 when a lock is on, 1 when not.
- Every outcome has its own exit status: 1 no lock, 2 usage error,
  3 lock already on, 4 system error. Errors go to stderr.
- `on` refuses to replace a running lock; `off` fails when there is none.
- A lock is one transient user unit, `app-expresso.service`, holding a
  `systemd-inhibit` lock; the timer unit is gone.
- A lock's deadline is wall-clock time: time suspended counts, and a lock whose
  deadline passed during suspend ends as soon as the system resumes.
- Notifications come from the lock unit: when a lock starts, ends (time's up or
  turned off) or fails. Commands send none themselves.
- Dependencies: adds `glib2` (for `gdbus`); drops `rofi`.

### Added

- `--version`.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX` and `DESTDIR`).
- `LICENSE` file (MIT), installed by the AUR package.

### Removed

- The configuration file and its `BLOCK_LID` / `BLOCK_IDLE` settings:
  use `--lid` / `--idle`.
- The `wayland-idle-inhibitor` integration: `--idle` takes logind's idle lock,
  which idle daemons such as hypridle respect.
- The `menu` command (rofi). A redesigned menu is planned for a later release.
- `help` and `version` commands: use `--help` and `--version`.

### Fixed

- An invalid duration could leave the system awake indefinitely.
- `status` misreported the time left, depending on locale and date format.
- The configuration file was executed as shell code.
- No notification when a timed lock ended.

## [1.0.2] - 2026-06-24

### Added

- `BLOCK_IDLE` option to keep Wayland idle daemons from dimming or locking the screen.

### Fixed

- Configuration file not being loaded.

## [1.0.1] - 2026-06-24

### Added

- `BLOCK_LID` option to prevent sleep when the laptop lid is closed.

## [1.0.0] - 2026-06-24

- Initial release.

