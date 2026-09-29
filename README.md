# Expresso

Keep your Linux system awake for a while, from the command line or your scripts.

`expresso on 1800` holds a lock that keeps the system from suspending for 30
minutes. `expresso off` releases it. `expresso status` tells a script whether a
lock is on and how long it has left.

- **Native.** The lock is a `systemd-inhibit` inhibitor held by a transient
  systemd user unit. When the unit stops, for any reason, the lock is gone:
  nothing can leak.
- **Exact.** A lock ends at its wall-clock deadline, even if the system was
  suspended past it: it ends as soon as the system resumes.
- **Scriptable.** stdout is data only, errors go to stderr, and every outcome
  has its own exit status.
- **Optional extras.** `--lid` keeps closing the lid from suspending; `--idle`
  keeps idle daemons such as hypridle from dimming, locking or turning off the
  screen.
- **Notifications** when a lock starts, ends or fails.

## Installation

### Arch Linux (AUR)

```bash
paru -S expresso
```

### From source

Dependencies: `bash`, `systemd`, `glib2` (for `gdbus`), `libnotify`, and `make`
to install.

```bash
git clone https://github.com/Davi-S/expresso.git
cd expresso
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

## Usage

```
expresso on DURATION [--lid] [--idle]
expresso off
expresso status
```

`DURATION` is in seconds; `0` means until `off`.

```bash
expresso on 2700              # 45 minutes
expresso on 0 --idle          # until turned off, and keep the screen on
expresso on 3600 --lid        # 1 hour, even with the lid closed
expresso off
```

`status` prints `key=value` lines and exits 0 when a lock is on, 1 when not:

```console
$ expresso status
state=on
duration=2700
started=1759158600
until=1759161300
remaining=2412
lid=false
idle=false
$ expresso off && expresso status
state=off
```

`until` and `remaining` are `infinity` for a lock started with `on 0`.

### Exit status

| Code | Meaning |
|---|---|
| 0 | Success; for `status`, a lock is on |
| 1 | No lock is on (`status`, `off`) |
| 2 | Usage error |
| 3 | A lock is already on (`on`) |
| 4 | System error |

### Scripting

There is no configuration file: put your preferred flags in a keybinding,
alias or script.

```bash
# Toggle, e.g. bound to a key
expresso off 2>/dev/null || expresso on 3600 --idle

# Seconds left, or "infinity"
expresso status | sed -n 's/^remaining=//p'

# Read every value
while IFS='=' read -r key value; do
    printf '%s -> %s\n' "$key" "$value"
done < <(expresso status)
```

See `man expresso` for the full reference, including how suspend and the lid
behave.

## Development

- `make check` runs `shellcheck` and `shfmt`, and `make test` runs the test suite
  (needs `bats`: `pacman -S bash-bats`). CI runs both on every push.
- `make integration` tests against your real systemd session; run it before a
  release (`SUSPEND=1` adds a suspend/resume check).
- The design and the reasons behind it are in [`docs/DESIGN.md`](docs/DESIGN.md).
- Record changes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
- Releases and AUR publishing are described in [`RELEASING.md`](RELEASING.md).

## License

[MIT](LICENSE)
