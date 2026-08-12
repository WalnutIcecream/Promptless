# promptless zsh — intercepts Enter via accept-line widget override
# Source this from .zshrc.

if [[ -z "$PROMPTLESS_LOADED" ]]; then
    local_classifier="${0:A:h}/../lib/classifier.sh"
    installed_classifier="${HOME}/.promptless/lib/classifier.sh"

    if [[ -f "$local_classifier" ]]; then
        source "$local_classifier"
    elif [[ -f "$installed_classifier" ]]; then
        source "$installed_classifier"
    fi

    PROMPTLESS_LOADED=1
fi


promptless_accept_line() {
    local user_input="${BUFFER}"

    # Slash commands — handled before classification so they never reach a
    # "command not found" error.  /session lists this directory's sessions and
    # picks one to continue; /new drops the current session.  A leading slash
    # is the only safe prefix that won't collide with real commands (they start
    # with /path syntax which is already captured by the classifier).
    case "$user_input" in
        /session|/sessions|/resume|/continue)
            BUFFER=""
            zle -I
            promptless_session_picker
            return
            ;;
        /new|/clear)
            BUFFER=""
            zle -I
            promptless_session_new
            return
            ;;
    esac

    if is_shell_command "$user_input"; then
        zle .accept-line
        return
    fi

    print -s "$user_input"
    BUFFER=""
    zle -I
    opencode_with_context "$user_input"
}


zle -N promptless_accept_line
bindkey '^M' promptless_accept_line
bindkey '^J' promptless_accept_line
