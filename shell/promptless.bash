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

    # Slash commands — handled before classification so they never reach a
    # "command not found" error.  /session lists this directory's sessions and
    # picks one to continue; /new drops the current session.
    case "$user_input" in
        /session|/sessions|/resume|/continue)
            promptless_session_picker
            READLINE_LINE=""
            READLINE_POINT=0
            return 0
            ;;
        /new|/clear)
            promptless_session_new
            READLINE_LINE=""
            READLINE_POINT=0
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
