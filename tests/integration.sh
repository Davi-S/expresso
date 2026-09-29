#!/usr/bin/env bash
#
# Integration test against the real systemd and logind. Run it on your desktop
# session before each release; CI can't, it has no systemd user session.
#
# Usage: tests/integration.sh [--suspend]
#   (or: make integration, make integration SUSPEND=1)
#
#   Without options: automatic checks, about 15 seconds.
#   --suspend:       then a check you take part in: suspend the machine past a
#                    lock's deadline, resume, and see how fast the lock ends.
#
# Tests src/expresso by default. To test an installed copy instead:
#   EXPRESSO=/usr/bin/expresso tests/integration.sh
#
# It refuses to run while a lock is on, so it never touches a lock you started.
# You will see a few notifications while it runs.

set -euo pipefail

EXPRESSO="${EXPRESSO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/expresso}"
readonly EXPRESSO

suspend_check=false
case "${1-}" in
"") ;;
--suspend) suspend_check=true ;;
*)
    echo "usage: $0 [--suspend]" >&2
    exit 2
    ;;
esac

failures=0

pass() {
    printf '  ok    %s\n' "$1"
}

fail() {
    printf '  FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

# check DESCRIPTION EXPECTED ACTUAL
check() {
    if [[ "$3" == "$2" ]]; then
        pass "$1"
    else
        fail "$1: expected '$2', got '$3'"
    fi
}

section() {
    printf '\n%s\n' "$1"
}

# code ARG...: print expresso's exit code, discarding its output.
code() {
    local -i status=0
    "$EXPRESSO" "$@" >/dev/null 2>&1 || status=$?
    printf '%s\n' "$status"
}

# field KEY: print one value from `expresso status`.
field() {
    "$EXPRESSO" status 2>/dev/null | sed -n "s/^$1=//p" || true
}

# inhibitor: print expresso's logind inhibitor as "WHAT MODE", or nothing.
inhibitor() {
    systemd-inhibit --list --no-legend --no-pager |
        awk '$1 == "expresso" { print $6, $NF }'
}

# now_ms: the wall clock in milliseconds.
now_ms() {
    local -r us="${EPOCHREALTIME/./}"
    printf '%s\n' "$((us / 1000))"
}

# wait_until_off TIMEOUT_S: poll every 0.1 s; print the time (ms) the lock was
# first seen off, or nothing on timeout.
wait_until_off() {
    local -r limit=$(($(now_ms) + $1 * 1000))
    while (($(now_ms) < limit)); do
        if [[ "$(code status)" == 1 ]]; then
            now_ms
            return
        fi
        sleep 0.1
    done
}

# Leave no lock behind if the script stops halfway.
cleanup() {
    if [[ "$(code status)" == 0 ]]; then
        "$EXPRESSO" off >/dev/null 2>&1 || true
    fi
}

printf 'Testing %s (%s)\n' "$EXPRESSO" "$("$EXPRESSO" --version)"

if [[ "$(code status)" != 1 ]]; then
    echo "A lock is on, or systemd is unreachable. Run 'expresso off' first." >&2
    exit 1
fi
trap cleanup EXIT
test_start="$(date +%s)"
readonly test_start

# -----------------------------------------------------------------------------
section "Timed lock: on 3 --idle"

check "on succeeds" 0 "$(code on 3 --idle)"
check "status says on" on "$(field state)"
check "duration" 3 "$(field duration)"
check "lid" false "$(field lid)"
check "idle" true "$(field idle)"
started="$(field started)"
until="$(field until)"
check "until = started + duration" "$((started + 3))" "$until"
check "logind holds sleep and idle, in block mode" "sleep:idle block" "$(inhibitor)"
check "on again is refused (exit 3)" 3 "$(code on 60)"

off_ms="$(wait_until_off 10)"
if [[ -z "$off_ms" ]]; then
    fail "the lock did not end within 10 s"
else
    late_ms=$((off_ms - until * 1000))
    if ((late_ms >= 0 && late_ms <= 1000)); then
        pass "ended on time: ${late_ms} ms into its deadline second (polled every 100 ms)"
    else
        fail "ended ${late_ms} ms from its deadline (expected 0 to 1000)"
    fi
fi
check "logind no longer holds the lock" "" "$(inhibitor)"

# -----------------------------------------------------------------------------
section "Indefinite lock: on 0 --lid, then off"

check "on succeeds" 0 "$(code on 0 --lid)"
check "until" infinity "$(field until)"
check "remaining" infinity "$(field remaining)"
check "lid" true "$(field lid)"
check "logind holds sleep and the lid switch" "sleep:handle-lid-switch block" "$(inhibitor)"
check "off succeeds" 0 "$(code off)"
check "off is synchronous: status is off right after" 1 "$(code status)"
check "logind no longer holds the lock" "" "$(inhibitor)"
check "off again: no lock (exit 1)" 1 "$(code off)"

# -----------------------------------------------------------------------------
section "Usage errors"

check "on 10m is a usage error (exit 2)" 2 "$(code on 10m)"
check "and starts nothing" 1 "$(code status)"

# -----------------------------------------------------------------------------
section "Journal"

if journal="$(journalctl --user -u app-expresso.service --since "@$test_start" -o cat 2>/dev/null)"; then
    check "no errors from expresso in the unit's journal" "" "$(grep '^expresso:' <<<"$journal" || true)"
    check "the unit never failed" "" "$(grep -i 'failed' <<<"$journal" || true)"
else
    fail "could not read the journal (journalctl --user)"
fi

cat <<'EOF'

  You should have seen four notifications, each for about 2 seconds:
    Expresso on   Until HH:MM · idle
    Expresso off  Time's up
    Expresso on   Indefinitely · lid
    Expresso off  Turned off
EOF

# -----------------------------------------------------------------------------
if [[ "$suspend_check" == true ]]; then
    section "Suspend past the deadline, then resume"
    cat <<'EOF'
  A 30-second lock will start. Suspend right away and stay suspended for at
  least 45 seconds, then resume. The lock should end as soon as you resume.
  To suspend: close the lid (the lock does not block the lid without --lid),
  or run 'systemctl suspend -i' (may ask for your password).
EOF
    read -rp "  Press Enter to start the lock... "
    check "on succeeds" 0 "$(code on 30)"
    until="$(field until)"
    printf '  Suspend now. Resume after %(%H:%M:%S)T.\n' "$((until + 15))"

    # Poll every 0.1 s. A gap much longer than that means we were suspended;
    # the first poll after it is (within ~0.1 s) the moment of resume.
    last_ms="$(now_ms)"
    resume_ms=""
    off_ms=""
    limit_ms=$((last_ms + 600 * 1000))
    while (($(now_ms) < limit_ms)); do
        now="$(now_ms)"
        if ((now - last_ms > 5000)) && [[ -z "$resume_ms" ]]; then
            resume_ms="$now"
        fi
        last_ms="$now"
        if [[ "$(code status)" == 1 ]]; then
            off_ms="$(now_ms)"
            break
        fi
        sleep 0.1
    done

    if [[ -z "$resume_ms" ]]; then
        fail "no suspend detected (the lock ended or 10 minutes passed first)"
    elif ((resume_ms < until * 1000)); then
        fail "resumed before the deadline; stay suspended longer and run again"
    elif [[ -z "$off_ms" ]]; then
        fail "the lock did not end after resume"
    else
        late_ms=$((off_ms - resume_ms))
        if ((late_ms <= 2000)); then
            pass "ended ${late_ms} ms after resume"
        else
            fail "ended ${late_ms} ms after resume (expected at most 2000)"
        fi
    fi
fi

# -----------------------------------------------------------------------------
printf '\n'
if ((failures == 0)); then
    echo "All checks passed."
else
    echo "$failures check(s) failed."
    exit 1
fi
