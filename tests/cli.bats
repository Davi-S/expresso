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
    [[ "${lines[0]}" == "Usage: expresso on DURATION [--lid] [--idle]" ]] ||
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
    for cmd in off status --help --version; do
        run --separate-stderr "$EXPRESSO" "$cmd" extra
        assert_status 2
        assert_stderr "expresso: '$cmd' takes no arguments"$'\n'"$usage_hint"
    done
}

@test "usage errors never touch the system" {
    run "$EXPRESSO" on 10m --lid
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

@test "off: no lock" {
    fake_lock_off
    run --separate-stderr "$EXPRESSO" off
    assert_status 1
    assert_stderr "expresso: no lock is on"
    refute_called systemd-run
    [[ "$(calls systemctl)" != *" stop "* ]] || fail "stop was called"
}

@test "off: systemctl stop failing is a system error" {
    fake_lock_on 60 1759158600 false false
    fake systemctl --args "--user stop *" --exit 1
    run --separate-stderr "$EXPRESSO" off
    assert_status 4
    assert_stderr "expresso: could not stop the lock"
}
