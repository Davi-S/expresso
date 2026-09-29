#!/usr/bin/env bats
#
# Pure functions, tested by sourcing the script (main does not run).

setup() {
    load helpers
    common_setup
    # shellcheck source=src/expresso
    source "$EXPRESSO"
}

# --- is_duration -------------------------------------------------------------

@test "is_duration accepts whole seconds from 0 to the maximum" {
    local value
    for value in 0 1 9 10 1800 86400 999999999 2147483647; do
        is_duration "$value" || fail "rejected '$value'"
    done
}

@test "is_duration rejects anything else" {
    local value
    for value in "" " " "-1" "+1" "01" "00" "007" "1.5" "1,5" "10m" "1h" \
        " 10" "10 " $'10\n' "1e3" "0x10" "inf" "infinity" "2147483648" \
        "9999999999" "99999999999999999999999"; do
        if is_duration "$value"; then
            fail "accepted '$value'"
        fi
    done
}

@test "is_duration never evaluates its input as arithmetic" {
    # Bash arithmetic on an unvalidated string can run commands.
    local -r marker="$BATS_TEST_TMPDIR/pwned"
    run is_duration "a[\$(touch $marker)]"
    assert_status 1
    [[ ! -e "$marker" ]] || fail "input was evaluated"
}

# --- inhibit_what ------------------------------------------------------------

@test "inhibit_what always includes sleep and adds lid and idle on request" {
    assert_equal "$(inhibit_what false false)" "sleep"
    assert_equal "$(inhibit_what true false)" "sleep:handle-lid-switch"
    assert_equal "$(inhibit_what false true)" "sleep:idle"
    assert_equal "$(inhibit_what true true)" "sleep:handle-lid-switch:idle"
}

# --- format_status -----------------------------------------------------------

@test "format_status: timed lock" {
    run format_status 1800 1759158600 false true 1759158660
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740 lid=false idle=true)"
}

@test "format_status: indefinite lock" {
    run format_status 0 1759158600 true false 1759999999
    assert_output "$(printf '%s\n' state=on duration=0 started=1759158600 \
        until=infinity remaining=infinity lid=true idle=false)"
}

@test "format_status: remaining is 0, never negative, once the deadline passed" {
    run format_status 60 1000 false false 5000
    assert_equal "$(grep '^remaining=' <<<"$output")" "remaining=0"
    assert_equal "$(grep '^until=' <<<"$output")" "until=1060"
}

# --- cli_parse_on ------------------------------------------------------------

@test "cli_parse_on: duration only" {
    run cli_parse_on 1800
    assert_status 0
    assert_output "1800 false false"
}

@test "cli_parse_on: flags in any position" {
    run cli_parse_on 1800 --lid
    assert_output "1800 true false"
    run cli_parse_on --idle 0
    assert_output "0 false true"
    run cli_parse_on --idle 60 --lid
    assert_output "60 true true"
}

usage_hint="Try 'expresso --help' for more information."

@test "cli_parse_on: missing duration" {
    run --separate-stderr cli_parse_on --lid
    assert_status 2
    assert_output ""
    assert_stderr "expresso: missing DURATION"$'\n'"$usage_hint"
}

@test "cli_parse_on: invalid duration" {
    local value
    for value in 10m -5 01 2147483648; do
        run --separate-stderr cli_parse_on "$value"
        assert_status 2
        assert_stderr "expresso: invalid DURATION '$value': expected whole seconds from 0 to 2147483647"$'\n'"$usage_hint"
    done
}

@test "cli_parse_on: two durations" {
    run --separate-stderr cli_parse_on 60 120
    assert_status 2
    assert_stderr "expresso: unexpected argument '120'"$'\n'"$usage_hint"
}

@test "cli_parse_on: repeated flag" {
    run --separate-stderr cli_parse_on 60 --lid --lid
    assert_status 2
    assert_stderr "expresso: option '--lid' given twice"$'\n'"$usage_hint"
}

@test "cli_parse_on: unknown option" {
    run --separate-stderr cli_parse_on 60 --forever
    assert_status 2
    assert_stderr "expresso: unknown option '--forever'"$'\n'"$usage_hint"
}
