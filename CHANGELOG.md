# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `expresso version` / `--version`.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX` and `DESTDIR`).
- `LICENSE` file (MIT), installed by the AUR package.
- Example config at `examples/expresso.conf`.

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

