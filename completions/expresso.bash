# bash completion for expresso

_expresso() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "start stop status menu help version" -- "$cur")
    elif ((COMP_CWORD == 2)) && [[ "$prev" == "start" ]]; then
        mapfile -t COMPREPLY < <(compgen -W "15m 30m 1h 2h inf" -- "$cur")
    fi
}

complete -F _expresso expresso
