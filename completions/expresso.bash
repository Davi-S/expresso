# bash completion for expresso

_expresso() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "on off status --help --version" -- "$cur")
        return 0
    fi

    # Only `on` takes arguments. DURATION is free-form seconds, so only the
    # flags are offered, each until it has been used.
    [[ "${COMP_WORDS[1]}" == on ]] || return 0
    local -r used=" ${COMP_WORDS[*]:2:COMP_CWORD-2} "
    local flag flags=()
    for flag in --lid --idle; do
        [[ "$used" == *" $flag "* ]] || flags+=("$flag")
    done
    mapfile -t COMPREPLY < <(compgen -W "${flags[*]}" -- "$cur")
}

complete -F _expresso expresso
