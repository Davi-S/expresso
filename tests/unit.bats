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
    assert_output "1800 false false false"
}

@test "cli_parse_on: flags in any position" {
    run cli_parse_on 1800 --lid
    assert_output "1800 true false false"
    run cli_parse_on --idle 0
    assert_output "0 false true false"
    run cli_parse_on --idle 60 --lid
    assert_output "60 true true false"
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

@test "cli_parse_on: --notify" {
    run cli_parse_on --notify 60 --idle
    assert_status 0
    assert_output "60 false true true"
    run --separate-stderr cli_parse_on 60 --notify --notify
    assert_status 2
    assert_stderr "expresso: option '--notify' given twice"$'\n'"$usage_hint"
}

# --- cli_parse_notify --------------------------------------------------------

@test "cli_parse_notify: no options" {
    run cli_parse_notify
    assert_status 0
    assert_output "false"
}

@test "cli_parse_notify: --notify" {
    run cli_parse_notify --notify
    assert_status 0
    assert_output "true"
}

@test "cli_parse_notify: repeated --notify" {
    run --separate-stderr cli_parse_notify --notify --notify
    assert_status 2
    assert_stderr "expresso: option '--notify' given twice"$'\n'"$usage_hint"
}

@test "cli_parse_notify: unknown option" {
    run --separate-stderr cli_parse_notify --lid
    assert_status 2
    assert_stderr "expresso: unknown option '--lid'"$'\n'"$usage_hint"
}

@test "cli_parse_notify: unexpected argument" {
    run --separate-stderr cli_parse_notify 60
    assert_status 2
    assert_stderr "expresso: unexpected argument '60'"$'\n'"$usage_hint"
}

# --- is_bool, is_timestamp, is_safe_path -------------------------------------

@test "is_bool accepts only true and false" {
    is_bool true
    is_bool false
    local value
    for value in "" TRUE True 1 0 yes no " true"; do
        if is_bool "$value"; then
            fail "accepted '$value'"
        fi
    done
}

@test "is_timestamp accepts up to 12 digits without leading zeros" {
    local value
    for value in 0 1 1759158600 999999999999; do
        is_timestamp "$value" || fail "rejected '$value'"
    done
    for value in "" -1 01 1.5 1759158600x 1000000000000; do
        if is_timestamp "$value"; then
            fail "accepted '$value'"
        fi
    done
}

@test "is_safe_path accepts absolute paths of plain characters only" {
    local value
    for value in /usr/bin/expresso /home/me/src/expresso-2.0/src/expresso /opt/a_b+c/expresso; do
        is_safe_path "$value" || fail "rejected '$value'"
    done
    # shellcheck disable=SC2016 # a literal $ is the point
    for value in "" expresso ./expresso "/my tools/expresso" '/a$b/expresso' /a%b/expresso '/a"b' "/a;b"; do
        if is_safe_path "$value"; then
            fail "accepted '$value'"
        fi
    done
}

# --- parse_unit_properties ---------------------------------------------------

@test "parse_unit_properties: an inactive or unknown unit" {
    run parse_unit_properties $'ActiveState=inactive\nEnvironment='
    assert_status 0
    assert_output "inactive"
}

@test "parse_unit_properties: every state other than active is inactive" {
    local state
    for state in failed activating deactivating reloading; do
        run parse_unit_properties "ActiveState=$state"$'\nEnvironment='
        assert_output "inactive"
    done
}

@test "parse_unit_properties: an active unit" {
    run parse_unit_properties $'ActiveState=active\nEnvironment=EXPRESSO_STARTED=1759158600 EXPRESSO_DURATION=1800 EXPRESSO_LID=false EXPRESSO_IDLE=true'
    assert_status 0
    assert_output "active 1800 1759158600 false true"
}

@test "parse_unit_properties: property and variable order do not matter" {
    run parse_unit_properties $'Environment=EXPRESSO_IDLE=false EXPRESSO_LID=true EXPRESSO_DURATION=0 EXPRESSO_STARTED=5\nActiveState=active'
    assert_output "active 0 5 true false"
}

@test "parse_unit_properties: an active unit with missing or invalid values fails" {
    local environment
    for environment in \
        "" \
        "EXPRESSO_STARTED=1 EXPRESSO_DURATION=60 EXPRESSO_LID=false" \
        "EXPRESSO_STARTED=1 EXPRESSO_DURATION=60m EXPRESSO_LID=false EXPRESSO_IDLE=true" \
        "EXPRESSO_STARTED=x EXPRESSO_DURATION=60 EXPRESSO_LID=false EXPRESSO_IDLE=true" \
        "EXPRESSO_STARTED=1 EXPRESSO_DURATION=60 EXPRESSO_LID=yes EXPRESSO_IDLE=true" \
        "OTHER=* EXPRESSO_DURATION=60 EXPRESSO_LID=false EXPRESSO_IDLE=true"; do
        run parse_unit_properties "ActiveState=active"$'\n'"Environment=$environment"
        assert_status 1
        assert_output ""
    done
}

# --- parse_lock_values -------------------------------------------------------

@test "parse_lock_values accepts valid values and prints them" {
    run parse_lock_values 1800 1759158600 false true
    assert_status 0
    assert_output "1800 1759158600 false true"
}

@test "parse_lock_values rejects any invalid value" {
    local values
    for values in "60m 1 false false" "60 x false false" "60 1 yes false" \
        "60 1 false 1" " 1 false false"; do
        # shellcheck disable=SC2086 # split into four arguments on purpose
        run parse_lock_values $values
        assert_status 1
    done
    run parse_lock_values "" "" "" ""
    assert_status 1
}

# --- format_until, format_left, describe_lock --------------------------------
# 1759158600 is Mon 2025-09-29 15:10 UTC; tests run with TZ=UTC.

@test "format_until: time only when the deadline is today" {
    assert_equal "$(format_until 1759160400 1759158600)" "Until 15:40"
}

@test "format_until: weekday when the deadline is within 6 days" {
    assert_equal "$(format_until 1759421400 1759158600)" "Until Thu 16:10"
}

@test "format_until: full date when the deadline is further away" {
    assert_equal "$(format_until 1761750600 1759158600)" "Until 2025-10-29 15:10"
}

@test "format_until: English weekdays whatever the locale" {
    local -r locale="$(locale -a 2>/dev/null | grep -iE '^(pt_BR|de_DE|fr_FR)\.utf-?8$' | head -1)"
    [[ -n "$locale" ]] || skip "no non-English locale installed"
    LC_ALL="$locale"
    assert_equal "$(format_until 1759421400 1759158600)" "Until Thu 16:10"
}

@test "format_left: the two largest units, rounded down" {
    assert_equal "$(format_left 0)" "0s left"
    assert_equal "$(format_left 59)" "59s left"
    assert_equal "$(format_left 60)" "1m left"
    assert_equal "$(format_left 1799)" "29m left"
    assert_equal "$(format_left 3600)" "1h 0m left"
    assert_equal "$(format_left 3959)" "1h 5m left"
    assert_equal "$(format_left 86400)" "1d 0h left"
    assert_equal "$(format_left 2147483647)" "24855d 3h left"
}

@test "describe_lock: deadline plus the extras that are on" {
    assert_equal "$(describe_lock 1800 1759158600 false false 1759158600 false)" "Until 15:40"
    assert_equal "$(describe_lock 1800 1759158600 true false 1759158600 false)" "Until 15:40 - lid"
    assert_equal "$(describe_lock 1800 1759158600 false true 1759158600 false)" "Until 15:40 - idle"
    assert_equal "$(describe_lock 1800 1759158600 true true 1759158600 false)" "Until 15:40 - lid, idle"
}

@test "describe_lock: indefinite" {
    assert_equal "$(describe_lock 0 1759158600 false false 1759158600 false)" "Indefinitely"
    assert_equal "$(describe_lock 0 1759158600 true true 1759158600 false)" "Indefinitely - lid, idle"
}

@test "describe_lock: with the time left" {
    assert_equal "$(describe_lock 1800 1759158600 false false 1759158660 true)" "Until 15:40 (29m left)"
    assert_equal "$(describe_lock 1800 1759158600 true true 1759158660 true)" "Until 15:40 (29m left) - lid, idle"
    assert_equal "$(describe_lock 0 1759158600 false true 1759158660 true)" "Indefinitely - idle"
}

@test "describe_lock: no negative time left once the deadline passed" {
    assert_equal "$(describe_lock 60 1759158600 false false 1759158700 true)" "Until 15:11 (0s left)"
}

# --- stop_reason -------------------------------------------------------------

@test "stop_reason maps systemd's exit information to why the lock ended" {
    assert_equal "$(stop_reason exited 0)" "timeout"
    assert_equal "$(stop_reason killed TERM)" "stopped"
    assert_equal "$(stop_reason killed KILL)" "stopped"
    assert_equal "$(stop_reason exited 1)" "failed"
    assert_equal "$(stop_reason exited 4)" "failed"
    assert_equal "$(stop_reason dumped SEGV)" "failed"
    assert_equal "$(stop_reason "" "")" "failed"
}
