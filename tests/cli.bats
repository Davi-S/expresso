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
