#!/usr/bin/env bats
#
# Bash completion, tested by calling the completion function the way bash does.

setup() {
    load helpers
    # shellcheck source=completions/expresso.bash
    source "$PROJECT_ROOT/completions/expresso.bash"
}

# complete WORD...: complete the last WORD of "expresso WORD...", then print
# the candidates on one line.
complete_words() {
    COMP_WORDS=(expresso "$@")
    COMP_CWORD=$#
    COMPREPLY=()
    _expresso
    printf '%s\n' "${COMPREPLY[*]}"
}

@test "the first word completes to the public commands" {
    assert_equal "$(complete_words "")" "on off status --help --version"
}

@test "internal commands are never offered" {
    assert_equal "$(complete_words "_")" ""
}

@test "a partial command completes" {
    assert_equal "$(complete_words "o")" "on off"
    assert_equal "$(complete_words "st")" "status"
    assert_equal "$(complete_words "--v")" "--version"
}

@test "after on: the flags" {
    assert_equal "$(complete_words on "")" "--lid --idle --notify"
    assert_equal "$(complete_words on 1800 "--i")" "--idle"
}

@test "after on: each flag is offered once" {
    assert_equal "$(complete_words on --lid "")" "--idle --notify"
    assert_equal "$(complete_words on 60 --idle --lid --notify "")" ""
}

@test "after on: nothing to suggest for a duration" {
    assert_equal "$(complete_words on "18")" ""
}

@test "after off and status: --notify, once" {
    local cmd
    for cmd in off status; do
        assert_equal "$(complete_words "$cmd" "")" "--notify"
        assert_equal "$(complete_words "$cmd" "--n")" "--notify"
        assert_equal "$(complete_words "$cmd" --notify "")" ""
    done
}

@test "the other commands take no arguments" {
    local cmd
    for cmd in --help --version; do
        assert_equal "$(complete_words "$cmd" "")" ""
    done
}
