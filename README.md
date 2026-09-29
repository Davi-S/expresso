# Expresso

A lightweight system-awake utility for Linux.

`expresso` is a minimal and fast alternative to the classic "Caffeine" utility.
It allows you to temporarily (or indefinitely) block your system from going to
sleep or entering idle states. It features a fully-fledged CLI backend and a
clean, integrated Rofi GUI.

### Features

- **OS-Native Inhibition:** Uses `systemd-inhibit` to natively interface with
  your system's login manager (`logind`).
- **Advanced State Management:** Optionally block laptop lid-close events, or
  prevent Wayland idle daemons from dimming or locking your screen.
- **Infinite or Timed:** Keep your system awake indefinitely, or schedule the
  inhibitor to automatically disable itself after a set amount of time using
  transient `systemd` timers.
- **Integrated Frontend & Backend:** A single, clean Bash script manages both
  the CLI logic and the Rofi graphical interface.
- **Smart Notifications:** Native system notifications via `notify-send` for
  activation, cancellation, and errors.

## Requirements

- **`systemd`**: For system inhibition and timer management.
- **`rofi`**: For the graphical menu.
- **`libnotify`**: For `notify-send` desktop notifications.
- **`wayland-idle-inhibitor`**: Required only if you want to block screen
  dimming, DPMS, and lock screens.

## Installation

### Arch Linux (AUR)

```bash
paru -S expresso
```

### From source

Dependencies: `bash`, `systemd`, `rofi`, `libnotify`, `make`.

```bash
git clone https://github.com/Davi-S/expresso.git
cd expresso
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

## Configuration

`expresso` works out of the box to prevent system suspension. To enable advanced
features like lid-blocking and idle-blocking, create a configuration file at
`~/.config/expresso/expresso.conf`.

```bash
mkdir -p ~/.config/expresso
cp /usr/share/doc/expresso/expresso.conf.example ~/.config/expresso/expresso.conf
```

The example is also in [`examples/expresso.conf`](examples/expresso.conf). Available settings:

```bash
# ~/.config/expresso/expresso.conf

# Set to "true" to prevent the system from sleeping when the laptop lid is closed
BLOCK_LID="false"

# Set to "true" to prevent Wayland idle daemons (like hypridle) from dimming or locking the screen
BLOCK_IDLE="false"
```

## Usage

`expresso` functions as both a CLI tool and a GUI launcher.

### Graphical Interface (Rofi)

To open the interactive menu, run:

```bash
expresso menu
```

### Command Line Interface

You can interact with the backend directly from your terminal or custom scripts:

```bash
# Start a caffeine lock (defaults to minutes if no unit is provided)
expresso start 15     # Stays awake for 15 minutes
expresso start 2h     # Stays awake for 2 hours

# Keep the system awake indefinitely
expresso start inf

# Check the status of an active lock
expresso status
#> 14m
#> Infinite

# Cancel the lock and allow the system to sleep normally again
expresso stop
```

See `man expresso` for the full reference.

## Development

- `make check` runs `shellcheck` and `shfmt`, and `make test` runs the test suite
  (needs `bats`: `pacman -S bash-bats`). CI runs both on every push.
- Record changes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
- Releases and AUR publishing are described in [`RELEASING.md`](RELEASING.md).

## License

[MIT](LICENSE)

