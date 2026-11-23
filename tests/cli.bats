#!/usr/bin/env bats
#
# The command line, run as a real process with every external command faked.

setup() {
    load helpers
    common_setup
}

usage_hint="Try 'expresso --help' for more information."

@test "--help prints usage to stdout and succeeds" {
    run --separate-stderr "$EXPRESSO" --help
    assert_status 0
    assert_stderr ""
    [[ "${lines[0]}" == "Usage: expresso on DURATION [--lid] [--idle] [--notify]" ]] ||
        fail "unexpected first line: ${lines[0]}"
}

@test "--version prints the version" {
    run --separate-stderr "$EXPRESSO" --version
    assert_status 0
    [[ "$output" =~ ^expresso\ [0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "unexpected output: $output"
}

@test "no command is a usage error" {
    run --separate-stderr "$EXPRESSO"
    assert_status 2
    assert_output ""
    assert_stderr "expresso: missing command"$'\n'"$usage_hint"
}

@test "an unknown command is a usage error" {
    run --separate-stderr "$EXPRESSO" start 60
    assert_status 2
    assert_stderr "expresso: unknown command 'start'"$'\n'"$usage_hint"
}

@test "commands without arguments reject arguments" {
    local cmd
    for cmd in --help --version _wait _stopped; do
        run --separate-stderr "$EXPRESSO" "$cmd" extra
        assert_status 2
        assert_stderr "expresso: '$cmd' takes no arguments"$'\n'"$usage_hint"
    done
}

@test "usage errors never touch the system" {
    run "$EXPRESSO" on 10m --lid
    assert_status 2
    run "$EXPRESSO" status --notify extra
    assert_status 2
    assert_equal "$(calls)" ""
}

# --- helpers for the lock's state --------------------------------------------

readonly SHOW_ARGS="--user show --property=ActiveState --property=Environment app-expresso.service"

# fake_lock_off: systemd reports no lock unit.
fake_lock_off() {
    fake systemctl --args "$SHOW_ARGS" --stdout $'ActiveState=inactive\nEnvironment='
}

# fake_lock_on DURATION STARTED LID IDLE: systemd reports a running lock unit.
fake_lock_on() {
    fake systemctl --args "$SHOW_ARGS" --stdout "ActiveState=active"$'\n'"Environment=EXPRESSO_STARTED=$2 EXPRESSO_DURATION=$1 EXPRESSO_LID=$3 EXPRESSO_IDLE=$4"
}

# assert_notified URGENCY TITLE BODY: expresso sent this notification.
assert_notified() { # URGENCY TITLE BODY
    assert_called notify-send --app-name=expresso --expire-time=2000 "--urgency=$1" "$2" "$3"
}

# fake_now TIMESTAMP: the current time, as `date +%s` prints it.
fake_now() {
    fake date --args "+%s" --stdout "$1"
}

# assert_lock_started DURATION STARTED LID IDLE WHAT: systemd-run was called
# exactly as the design specifies.
assert_lock_started() {
    assert_called systemd-run --user --quiet --collect \
        --unit=app-expresso.service --slice=app.slice \
        "--description=expresso: keep the system awake" \
        "--setenv=EXPRESSO_STARTED=$2" \
        "--setenv=EXPRESSO_DURATION=$1" \
        "--setenv=EXPRESSO_LID=$3" \
        "--setenv=EXPRESSO_IDLE=$4" \
        "--property=ExecStopPost=$EXPRESSO _stopped" \
        -- systemd-inhibit "--what=$5" --who=expresso "--why=expresso on" --mode=block \
        "$EXPRESSO" _wait
}

# --- status ------------------------------------------------------------------

@test "status: no lock" {
    fake_lock_off
    run --separate-stderr "$EXPRESSO" status
    assert_status 1
    assert_output "state=off"
    assert_stderr ""
}

@test "status: timed lock" {
    fake_lock_on 1800 1759158600 false true
    fake_now 1759158660
    run --separate-stderr "$EXPRESSO" status
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740 lid=false idle=true)"
    assert_stderr ""
}

@test "status: indefinite lock" {
    fake_lock_on 0 1759158600 true true
    fake_now 1759158660
    run "$EXPRESSO" status
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=0 started=1759158600 \
        until=infinity remaining=infinity lid=true idle=true)"
}

@test "status: sends no notification" {
    fake_lock_on 1800 1759158600 false true
    fake_now 1759158660
    run "$EXPRESSO" status
    refute_called notify-send
}

@test "status --notify: no lock" {
    fake_lock_off
    run --separate-stderr "$EXPRESSO" status --notify
    assert_status 1
    assert_output "state=off"
    assert_stderr ""
    assert_notified normal "Expresso status: off" "No lock is on"
}

@test "status --notify: timed lock" {
    fake_lock_on 1800 1759158600 false true
    fake_now 1759158660
    run --separate-stderr "$EXPRESSO" status --notify
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740 lid=false idle=true)"
    assert_stderr ""
    assert_notified normal "Expresso status: on" "Until 15:40 (29m left) - idle"
}

@test "status --notify: indefinite lock" {
    fake_lock_on 0 1759158600 true false
    fake_now 1759158660
    run "$EXPRESSO" status --notify
    assert_status 0
    assert_notified normal "Expresso status: on" "Indefinitely - lid"
}

@test "status --notify: a failed notification is a system error, after the output" {
    fake_lock_on 1800 1759158600 false false
    fake_now 1759158660
    fake notify-send --exit 1
    run --separate-stderr "$EXPRESSO" status --notify
    assert_status 4
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740 lid=false idle=false)"
    assert_stderr "expresso: could not send a notification"

    fake_lock_off
    run --separate-stderr "$EXPRESSO" status --notify
    assert_status 4
    assert_output "state=off"
}

@test "status --notify: a system error sends no notification" {
    fake systemctl --args "$SHOW_ARGS" --exit 1
    run "$EXPRESSO" status --notify
    assert_status 4
    refute_called notify-send
}

@test "status: arguments other than --notify are usage errors" {
    run --separate-stderr "$EXPRESSO" status extra
    assert_status 2
    assert_stderr "expresso: unexpected argument 'extra'"$'\n'"$usage_hint"
    run --separate-stderr "$EXPRESSO" status --idle
    assert_status 2
    assert_stderr "expresso: unknown option '--idle'"$'\n'"$usage_hint"
}

@test "status: systemd unreachable is a system error" {
    fake systemctl --args "$SHOW_ARGS" --exit 1
    run --separate-stderr "$EXPRESSO" status
    assert_status 4
    assert_output ""
    assert_stderr "expresso: could not read the lock state from systemd"
}

@test "status: a unit expresso did not create is a system error" {
    fake systemctl --args "$SHOW_ARGS" --stdout $'ActiveState=active\nEnvironment=FOO=bar'
    run --separate-stderr "$EXPRESSO" status
    assert_status 4
    assert_stderr "expresso: app-expresso.service is running but was not started by this version of expresso"
}

@test "status: an unreadable clock is a system error" {
    fake_lock_on 60 1759158600 false false
    fake date --args "+%s" --stdout "not a number"
    run --separate-stderr "$EXPRESSO" status
    assert_status 4
    assert_stderr "expresso: could not read the current time"
}

# --- on ----------------------------------------------------------------------

@test "on: starts the lock unit" {
    fake_lock_off
    fake_now 1759158600
    run --separate-stderr "$EXPRESSO" on 1800
    assert_status 0
    assert_output ""
    assert_stderr ""
    assert_lock_started 1800 1759158600 false false sleep
}

@test "on: --lid and --idle extend the inhibitor" {
    fake_lock_off
    fake_now 1759158600
    run "$EXPRESSO" on 0 --idle --lid
    assert_status 0
    assert_lock_started 0 1759158600 true true sleep:handle-lid-switch:idle
}

@test "on: a running lock is not replaced" {
    fake_lock_on 60 1759158600 false false
    run --separate-stderr "$EXPRESSO" on 1800
    assert_status 3
    assert_output ""
    assert_stderr "expresso: a lock is already on; run 'expresso off' first"
    refute_called systemd-run
}

@test "on: systemd-run failing is a system error" {
    fake_lock_off
    fake_now 1759158600
    fake systemd-run --exit 1
    run --separate-stderr "$EXPRESSO" on 60
    assert_status 4
    assert_stderr "expresso: could not start the lock"
}

@test "on: refuses to run from a path systemd would misread" {
    local -r dir="$BATS_TEST_TMPDIR/my tools"
    mkdir -p "$dir"
    cp "$EXPRESSO" "$dir/expresso"
    fake_lock_off
    fake_now 1759158600
    run --separate-stderr "$dir/expresso" on 60
    assert_status 4
    assert_stderr "expresso: cannot run from '$dir/expresso': the path may only contain letters, digits and / . _ + -"
    refute_called systemd-run
}

# --- off ---------------------------------------------------------------------

@test "off: stops the lock unit" {
    fake_lock_on 60 1759158600 false false
    run --separate-stderr "$EXPRESSO" off
    assert_status 0
    assert_output ""
    assert_stderr ""
    assert_called systemctl --user stop app-expresso.service
}

@test "on: sends no notification of its own" {
    fake_lock_off
    fake_now 1759158600
    run "$EXPRESSO" on 1800 --notify
    assert_status 0
    refute_called notify-send

    fake_lock_on 60 1759158600 false false
    run "$EXPRESSO" on 1800
    assert_status 3
    refute_called notify-send
}

@test "on --notify: a lock already on is shown" {
    fake_lock_on 1800 1759158600 true false
    fake_now 1759158660
    run --separate-stderr "$EXPRESSO" on 60 --notify
    assert_status 3
    assert_output ""
    assert_stderr "expresso: a lock is already on; run 'expresso off' first"
    assert_notified normal "Expresso status: already on" "Until 15:40 (29m left) - lid"
    refute_called systemd-run
}

@test "on --notify: a failed notification is a system error" {
    fake_lock_on 0 1759158600 false false
    fake_now 1759158660
    fake notify-send --exit 1
    run --separate-stderr "$EXPRESSO" on 60 --notify
    assert_status 4
    assert_stderr "expresso: could not send a notification"
}

@test "off: no lock" {
    fake_lock_off
    run --separate-stderr "$EXPRESSO" off
    assert_status 1
    assert_stderr "expresso: no lock is on"
    refute_called systemd-run
    [[ "$(calls systemctl)" != *" stop "* ]] || fail "stop was called"
}

@test "off: sends no notification of its own" {
    fake_lock_on 60 1759158600 false false
    run "$EXPRESSO" off --notify
    assert_status 0
    refute_called notify-send

    fake_lock_off
    run "$EXPRESSO" off
    assert_status 1
    refute_called notify-send
}

@test "off --notify: no lock is shown" {
    fake_lock_off
    run --separate-stderr "$EXPRESSO" off --notify
    assert_status 1
    assert_output ""
    assert_stderr "expresso: no lock is on"
    assert_notified normal "Expresso status: already off" "No lock is on"
}

@test "off --notify: a failed notification is a system error" {
    fake_lock_off
    fake notify-send --exit 1
    run --separate-stderr "$EXPRESSO" off --notify
    assert_status 4
    assert_stderr "expresso: could not send a notification"
}

@test "off: arguments other than --notify are usage errors" {
    run --separate-stderr "$EXPRESSO" off extra
    assert_status 2
    assert_stderr "expresso: unexpected argument 'extra'"$'\n'"$usage_hint"
    run --separate-stderr "$EXPRESSO" off --idle
    assert_status 2
    assert_stderr "expresso: unknown option '--idle'"$'\n'"$usage_hint"
}

@test "off: systemctl stop failing is a system error" {
    fake_lock_on 60 1759158600 false false
    fake systemctl --args "--user stop *" --exit 1
    run --separate-stderr "$EXPRESSO" off
    assert_status 4
    assert_stderr "expresso: could not stop the lock"
}

# --- _wait (run by the unit, inside systemd-inhibit) -------------------------
# 1759158600 is Mon 2025-09-29 15:10 UTC; tests run with TZ=UTC.

readonly MONITOR_ARGS=(monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1)

# lock_env DURATION STARTED LID IDLE: the environment the unit gives _wait.
lock_env() {
    export EXPRESSO_DURATION="$1" EXPRESSO_STARTED="$2" EXPRESSO_LID="$3" EXPRESSO_IDLE="$4"
}

# clock T1 T2 ... TN: successive `date +%s` answers; the last one repeats.
clock() {
    local -r times=("$@")
    fake_now "${times[-1]}"
    local i
    for ((i = ${#times[@]} - 2; i >= 0; i--)); do
        fake date --args "+%s" --stdout "${times[i]}" --once
    done
}

@test "_wait: notifies that the lock is on" {
    lock_env 1800 1759158600 false true
    clock 1759158600 1759160400
    run "$EXPRESSO" _wait
    assert_status 0
    assert_notified normal "Expresso on" "Until 15:40 - idle"
}

@test "_wait: waits until the deadline" {
    # gdbus prints nothing, so only the timeout at the deadline ends the wait:
    # a 1-second lock, so the test takes 1 second.
    fake gdbus --hang
    lock_env 1 1759158600 false false
    clock 1759158600 1759158600 1759158601
    SECONDS=0
    run --separate-stderr "$EXPRESSO" _wait
    assert_status 0
    assert_stderr ""
    ((SECONDS <= 3)) || fail "took $SECONDS s"
    assert_called gdbus "${MONITOR_ARGS[@]}"
    refute_called sleep
    refute_hanging gdbus
}

@test "_wait: a logind signal (resume) rechecks the clock at once" {
    lock_env 1800 1759158600 false false
    fake gdbus --stdout "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)" --hang
    # After the signal the clock is past the deadline, as after a long suspend.
    clock 1759158600 1759158600 1759200000
    SECONDS=0
    run --separate-stderr "$EXPRESSO" _wait
    assert_status 0
    assert_stderr ""
    ((SECONDS <= 2)) || fail "took $SECONDS s: it waited instead of rechecking"
    refute_called sleep
    refute_hanging gdbus
}

@test "_wait: without the logind monitor, falls back to sleep and warns" {
    lock_env 1800 1759158600 false false
    # gdbus exits at once (no rule), like when the system bus is unreachable.
    # Clock reads: notification, first check, recheck after the monitor died,
    # after the sleep.
    clock 1759158600 1759158600 1759158600 1759160400
    run --separate-stderr "$EXPRESSO" _wait
    assert_status 0
    assert_stderr "expresso: cannot watch logind for resume; after a suspend, the lock may end late"
    assert_called sleep 1800
}

@test "_wait: returns at once when the deadline already passed" {
    lock_env 60 1759158600 false false
    clock 1759200000
    run "$EXPRESSO" _wait
    assert_status 0
    refute_called sleep
}

@test "_wait: an indefinite lock sleeps forever without the monitor" {
    lock_env 0 1759158600 true false
    clock 1759158600
    run "$EXPRESSO" _wait
    assert_status 0
    assert_notified normal "Expresso on" "Indefinitely - lid"
    assert_called sleep infinity
    refute_called gdbus
}

@test "_wait: a failed notification does not end the lock" {
    lock_env 60 1759158600 false false
    fake notify-send --exit 1
    clock 1759158600 1759158600 1759158600 1759158660
    run --separate-stderr "$EXPRESSO" _wait
    assert_status 0
    assert_called sleep 60
    assert_stderr "expresso: could not send a notification"$'\n'"expresso: cannot watch logind for resume; after a suspend, the lock may end late"
}

@test "_wait: missing or invalid lock values are a system error" {
    run --separate-stderr "$EXPRESSO" _wait
    assert_status 4
    assert_stderr "expresso: missing or invalid EXPRESSO_* variables; '_wait' is run by the lock unit"
    refute_called notify-send

    lock_env 60m 1759158600 false false
    run "$EXPRESSO" _wait
    assert_status 4
}

# --- _stopped (the unit's ExecStopPost) --------------------------------------

@test "_stopped: time's up" {
    EXIT_CODE=exited EXIT_STATUS=0 run "$EXPRESSO" _stopped
    assert_status 0
    assert_notified normal "Expresso off" "Time's up"
}

@test "_stopped: turned off" {
    EXIT_CODE=killed EXIT_STATUS=TERM run "$EXPRESSO" _stopped
    assert_status 0
    assert_notified normal "Expresso off" "Turned off"
}

@test "_stopped: failed" {
    EXIT_CODE=exited EXIT_STATUS=1 run "$EXPRESSO" _stopped
    assert_status 0
    assert_notified critical "Expresso failed" "Could not take the lock. See: journalctl --user -u app-expresso"
}

@test "_stopped: no exit information counts as failed" {
    run "$EXPRESSO" _stopped
    assert_notified critical "Expresso failed" "Could not take the lock. See: journalctl --user -u app-expresso"
}

@test "_stopped: a failed notification is a system error" {
    fake notify-send --exit 1
    EXIT_CODE=exited EXIT_STATUS=0 run --separate-stderr "$EXPRESSO" _stopped
    assert_status 4
    assert_stderr "expresso: could not send a notification"
}
