# bash completion for expresso

_expresso() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "on off status --help --version" -- "$cur")
        return 0
    fi

    # Only `on` and `status` take arguments. DURATION is free-form seconds, so
    # only the flags are offered, each until it has been used.
    local candidates
    case "${COMP_WORDS[1]}" in
    on) candidates=(--lid --idle) ;;
    status) candidates=(--notify) ;;
    *) return 0 ;;
    esac
    local -r used=" ${COMP_WORDS[*]:2:COMP_CWORD-2} "
    local flag flags=()
    for flag in "${candidates[@]}"; do
        [[ "$used" == *" $flag "* ]] || flags+=("$flag")
    done
    mapfile -t COMPREPLY < <(compgen -W "${flags[*]}" -- "$cur")
}

complete -F _expresso expresso
