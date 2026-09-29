# expresso 2.0 design

Ground-up rewrite. No backwards compatibility with 1.x; ships as 2.0.0.
This file records decisions. Open items are listed at the end.

## Goals

- Bash only, minimal runtime dependencies: `bash`, `systemd`, `glib2` (for `gdbus`),
  `libnotify`, and `rofi` once the menu is designed.
- Every feature is always on or doesn't exist (no optional dependencies).
- A strict, scriptable CLI. Users compose their own workflows with shell scripts.
- Fully testable in CI.

## CLI

```
expresso on DURATION [--lid] [--idle]
expresso off
expresso status
expresso --help
expresso --version
```

- **DURATION** is required: whole seconds, matching `^(0|[1-9][0-9]*)$` (no leading
  zeros; Bash would read them as octal), at most `2147483647`. `0` means
  indefinite, as in systemd settings.
- **Always held:** a `sleep` inhibitor. `--lid` adds `handle-lid-switch` (closing the
  lid won't suspend); `--idle` adds `idle` (idle daemons such as hypridle won't
  dim, lock or turn off the screen).
- **No config file.** Preferred flags live in the user's keybind or alias.
- **stdout is data only; messages and errors go to stderr.**
- **The CLI never sends notifications.** The unit sends all of them.
- **`off` is synchronous:** when it returns, the lock is gone and `status` says off.
- **`--help`** prints short usage to stdout and exits 0. `--version` prints
  `expresso X.Y.Z`. The full reference is `man expresso`.
  A usage error prints `expresso: <problem>` and
  `Try 'expresso --help' for more information.` to stderr, and exits 2.

### Exit codes

Each code has one meaning across all commands.

| Code | Meaning | Returned by |
|---|---|---|
| 0 | Success / lock is on | `on`, `off`, `status` (on), `--help`, `--version` |
| 1 | No lock running | `status` (off), `off` (nothing to turn off) |
| 2 | Usage error: bad command, flag or duration | all |
| 3 | A lock is already running | `on` |
| 4 | System error: systemd call failed, lock not acquired, no user manager | all |

### `status` output

`key=value` lines. Exit code 0 when on, 1 when off.

```
state=on              state=on              state=off
duration=1800         duration=0
started=1759158600    started=1759158600
until=1759160400      until=infinity
remaining=1740        remaining=infinity
lid=false             lid=true
idle=true             idle=false
```

- When on, all seven keys are always present. `duration` echoes the `on` argument.
  `started` and `until` are Unix timestamps, and `remaining` is in seconds.
- An indefinite lock has `duration=0` and `until`/`remaining` = `infinity`.
- When off, the only line is `state=off`.

## Runtime model

A lock is **one transient systemd user unit**, `app-expresso.service` in `app.slice`,
started with `systemd-run --user --collect` (removed when it stops, even on failure).
The unit is the whole state: if it is running, the lock is held.

```
expresso on 1800 --idle
   └─ systemd-run --user --unit=app-expresso --slice=app.slice --collect
        --setenv=EXPRESSO_STARTED=… EXPRESSO_DURATION=… EXPRESSO_LID=… EXPRESSO_IDLE=…
        -p ExecStopPost="expresso _stopped"
      └─ systemd-inhibit --what=sleep[:handle-lid-switch][:idle] expresso _wait
            ├─ lock acquired → _wait sends "started" notification
            └─ _wait returns at the deadline
      unit stops, for any reason → _stopped sends "ended" / "failed" notification
```

- **Deadline semantics.** `on N` means "until STARTED + N" on the wall clock.
  Time spent suspended counts.
- **State lives on the unit** as environment variables (`EXPRESSO_STARTED`,
  `EXPRESSO_DURATION`, `EXPRESSO_LID`, `EXPRESSO_IDLE`). `status` reads them with
  `systemctl --user show -p Environment app-expresso.service`. Values are only
  digits and `true`/`false`, so reading them back is safe. `_wait` gets the same
  values as its own environment.
- **The lock cannot leak.** logind ties an inhibitor to the holding process's file
  descriptor; if the process dies for any reason, the lock is released.
- **Install path.** The unit runs this script by absolute path. `on` refuses to
  start (exit 4) if the path contains anything besides letters, digits and
  `/ . _ + -`, because systemd would split, unquote or expand it.
- **Concurrent `on`.** systemd refuses a second unit with the same name, so two
  locks can never exist; the loser of a race gets exit 4 with systemd's message.
- **Internal subcommands** `_wait` and `_stopped` are run by the unit, not by users.
  They are documented as internal and are not part of the public CLI.
- **Users and sessions.** Each user has their own user manager, so their own unit.
  All sessions of one user share one lock; `off` works from any of them.
  Without a user manager (inside a container, `sudo`): exit 4.

### The waiter (`_wait`)

Exact at the deadline, including after suspend, with a single unit:

```
start `gdbus monitor` on logind (before the first clock check, so no resume is missed)
loop:
  now ≥ deadline → exit 0
  read one line from the monitor, with a timeout of (deadline − now) seconds
    line    → a logind signal (PrepareForSleep(false) on resume): recheck the clock
    timeout → the deadline, measured while awake: recheck the clock
    EOF     → the monitor died: warn in the journal, then use `sleep` instead
              (still exact while awake, but may end late after a suspend)
stop the monitor
```

- `read -t` on the monitor's output is both the timer and the resume listener,
  so no separate `sleep` process is needed while the monitor runs.
- Indefinite (`duration=0`): `sleep infinity`, no monitor; it ends when stopped.
- Timestamps are whole seconds. STARTED and each clock check are rounded down,
  and the roundings cancel: a lock ends about DURATION seconds after `on`, which
  is 0 to 1 second after `until`, never before it.
- Measured on real systemd (tests/integration.sh): a lock ends within its
  deadline second; after resuming past the deadline (lid closed), it ended
  26 ms after resume.
- Known limit: a large wall-clock change while awake (manual clock set) is only
  noticed at the next logind signal or at the current timeout.

### Notifications

Sent only by the unit (`_wait` and `_stopped`), with `notify-send
--app-name=expresso --expire-time=2000`. Separate notifications, no replacing.
If the "started" notification fails, the lock is kept (holding it matters more).

| Event | Detected by | Title | Body |
|---|---|---|---|
| Started | `_wait` starts (lock is held) | Expresso on | `Until 15:30` (today) / `Until Tue 09:00` (within 6 days) / `Until 2025-10-29 15:10` / `Indefinitely`, plus ` · lid, idle` when set. Always English. |
| Time's up | `EXIT_CODE=exited`, `EXIT_STATUS=0` | Expresso off | `Time's up` |
| Turned off | `EXIT_CODE=killed` (any signal) | Expresso off | `Turned off` |
| Failed | anything else: non-zero exit, core dump, no information | Expresso failed | `Could not take the lock. See: journalctl --user -u app-expresso` (critical) |

## Code structure

One file, `src/expresso`, in layers that only call downward:

```
cli (argv → validated request)         [menu: to be designed]
                \
     core: on <seconds> <lid> <idle> · off · status → record · _wait · _stopped
                          |
     system: the only code calling systemd-run, systemctl, date, gdbus,
             notify-send; validates their output and reports its own failures
                          |
     values: pure functions (is_duration, parse_unit_properties, format_status…)
```

Discipline in place of types:
- Parse and validate only at the edges. The core receives validated values only.
- Globals are `readonly` constants. Functions communicate through arguments,
  stdout and exit codes. Use `local -r` and `declare -i` where applicable.
- The layer that detects a problem reports it, except the core: it returns a
  code (1 no lock, 3 already on) and the cli prints the message.
- The core never prints for humans. No function calls `exit`; errors propagate
  with `|| return`, since Bash disables `set -e` in many contexts.
- Never do arithmetic on an unvalidated string (Bash evaluates it as code).
- `main` runs only when the file is executed, so tests can source it.

## Testing

```
tests/
  unit.bats          pure functions: duration parsing, status formatting, …
  cli.bats           commands end to end, with fakes
  helpers.bash       shared setup: temp dir, PATH, fake helpers
  fakes/             systemd-run  systemctl  date  gdbus  notify-send
  integration.sh     real systemd, run locally before each release
```

- `make integration`: automatic checks against the real systemd and logind
  (timing, the inhibitor logind holds, exit codes, the unit's journal).
  `make integration SUSPEND=1` adds a suspend/resume check the user performs.

- Plain bats (no helper libraries). `make test`; CI runs it on every push.
- **Recording fakes:** each fake appends its argv to a log and prints the output and
  exit code the test prepared. Tests assert on the commands expresso ran.
- **Time** comes from `date +%s`, so the fake `date` controls "now".

## Open

- The menu: entries, custom input, flags, errors. Designed later, after the CLI works.
