# promptless bash — intercepts Enter via readline macro
# Source this from .bashrc.

if [[ -z "$PROMPTLESS_LOADED" ]]; then
    local_classifier="$(dirname "${BASH_SOURCE[0]}")/../lib/classifier.sh"
    installed_classifier="${HOME}/.promptless/lib/classifier.sh"

    if [[ -f "$local_classifier" ]]; then
        source "$local_classifier"
    elif [[ -f "$installed_classifier" ]]; then
        source "$installed_classifier"
    fi

    PROMPTLESS_LOADED=1
fi


classify_and_route() {
    local user_input="$READLINE_LINE"

    # Escape hatches.
    case "$user_input" in
        /new|/reset)
            reset_project_session
            READLINE_LINE=""
            echo ""
            echo "✅ Session reset — next prompt will start a fresh conversation."
            return 0
            ;;
    esac

    if is_shell_command "$user_input"; then
        return 0
    fi

    if [[ -n "$user_input" ]]; then
        history -s "$user_input"
    fi

    READLINE_LINE="opencode_with_context $(printf '%q' "$user_input")"
    READLINE_POINT=${#READLINE_LINE}
}


bind -x '"\C-x\C-p": classify_and_route'
bind '"\C-m": "\C-x\C-p\n"'
