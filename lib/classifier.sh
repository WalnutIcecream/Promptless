# promptless — dual-mode shell: commands run, prompts go to opencode
#
# Determines whether terminal input is a native shell command or a natural-language
# prompt intended for opencode.  Sessions work the native opencode way: there is no
# per-project session file and no automatic resume of the last session.  Prompts
# default to a fresh session (which then becomes the in-memory "current" one); use
# /session to pick a past session, /new to start fresh.

declare -A COMMAND_CACHE 2>/dev/null
CACHED_PATH=""

# Directory containing this script's lib/ files, resolved at source time.
# Works in both bash (BASH_SOURCE) and zsh ($0 is the sourced file at top level).
if [[ -n "${BASH_VERSION:-}" ]]; then
    PROMPTLESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    PROMPTLESS_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
fi


# ---------------------------------------------------------------------------
# Cache Management
# ---------------------------------------------------------------------------

build_command_cache() {
    local current_path="${PATH}"

    if [[ "$current_path" == "$CACHED_PATH" && "${#COMMAND_CACHE[@]}" -gt 0 ]]; then
        return 0
    fi

    CACHED_PATH="$current_path"
    COMMAND_CACHE=()

    local command_name
    while IFS= read -r command_name; do
        if [[ -n "$command_name" ]]; then
            COMMAND_CACHE["$command_name"]=1
        fi
    done < <(compgen -c 2>/dev/null || compgen -abk 2>/dev/null)
}


# ---------------------------------------------------------------------------
# Ambiguous Verb Detection
# ---------------------------------------------------------------------------

is_ambiguous_verb() {
    local word="$1"

    case "$word" in
        find|make|test|echo|kill|wait|jobs|time|read|\
        set|enable|history|source|help|open|close|\
        create|update|delete|list|check|show|count|\
        start|stop|build|write|diff|sort|join|split|\
        cut|link|copy|move|paste|replace|rename|\
        remove|add|change|format|group|install|setup|\
        edit|view|scan|mount|export|import|fetch|push|\
        pull|merge|patch|release|commit|rebase|clone|\
        monitor|trace|score|rank|filter|search|compare|\
        verify|print|sleep|let|eval|generate|compile|\
        configure|deploy|schedule|cancel|encrypt|decrypt|\
        sign|transform|migrate|restore|backup|benchmark|\
        profile|document|package|publish|audit|review|\
        outline|draft|revise|proofread|annotate|\
        highlight|quote|cite|reference|define|contrast|\
        evaluate|recommend|suggest|propose|estimate|\
        measure|weigh|balance|prioritize|triage|escalate|\
        delegate|assign|unassign|claim|release|lock|\
        unlock|protect|expose|hide|reveal|mask|redact|\
        teach|learn|train|predict|classify|cluster|\
        segment|resolve|normalize|validate|parse|draw|\
        design|implement|refactor|debug|optimize|\
        translate|summarize|convert|upload|download|\
        scrape|sanitize|calculate|compute)
            return 0 ;;
    esac

    return 1
}


# ---------------------------------------------------------------------------
# Main Classifier
# ---------------------------------------------------------------------------

# Returns 0 (shell truthy) if the input should run as a native shell command.
# Returns 1 (shell falsy) if it looks like an opencode prompt.
is_shell_command() {
    local raw_input="$1"

    if [[ -z "$raw_input" ]]; then
        return 0
    fi

    local input="$raw_input"
    if [[ "$input" == " "* ]]; then
        input="${raw_input#"${raw_input%%[![:space:]]*}"}"
    fi

    local first_word="${input%% *}"
    local remainder="${input#* }"
    if [[ "$remainder" == "$input" ]]; then
        remainder=""
    fi

    # ----- Hot path: known, non-ambiguous command --------------------------
    if [[ -n "${COMMAND_CACHE[$first_word]:-}" ]]; then
        if ! is_ambiguous_verb "$first_word"; then
            return 0
        fi
    fi

    # ----- Shell builtins --------------------------------------------------
    case "|$first_word|" in
        \|cd\||\|echo\||\|export\||\|source\||\|alias\||\|eval\||\|exec\||\
\|exit\||\|type\||\|which\||\|help\||\|time\||\|set\||\|unset\||\|shift\||\
\|umask\||\|enable\||\|bind\||\|declare\||\|typeset\||\|local\||\|readonly\||\
\|printf\||\|mapfile\||\|readarray\||\|builtin\||\|caller\||\|command\||\|compgen\||\
\|complete\||\|compopt\||\|dirs\||\|disown\||\|getopts\||\|popd\||\|pushd\||\
\|pwd\||\|return\||\|shopt\||\|suspend\||\|trap\||\|times\||\|false\||\
\|ulimit\||\|logout\||\|continue\||\|break\|)
            return 0 ;;
    esac

    # ----- Single-word unknown input ---------------------------------------
    if [[ -z "$remainder" ]]; then
        return 0
    fi

    # ----- Shell metacharacters --------------------------------------------
    case "$input" in
        *'|'*|*'>'*|*'<'*|*'&'*|*';'*|*'`'*|*--?*|\\*|\"*)
            return 0 ;;
        ./*|../*|/*|~/*|!'*'|'#'*)
            return 0 ;;
    esac

    # ----- Unambiguous NLP signals -----------------------------------------
    case "$input" in
        *'?'|*'? ')
            return 1 ;;
    esac

    case "$first_word" in
        how|what|why|when|where|who|which|whose|\
        can|could|would|should|is|are|do|does|did|will|shall|may|might|\
        please|tell|explain|describe)
            return 1 ;;
    esac

    # ----- NLP structural-word detection -----------------------------------
    if has_nlp_structure "$remainder"; then
        return 1
    fi

    return 0
}


# ---------------------------------------------------------------------------
# NLP Structure Detection
# ---------------------------------------------------------------------------

has_nlp_structure() {
    local arguments="$1"

    if [[ -z "$arguments" ]]; then
        return 1
    fi

    local padded=" $arguments "

    case "$padded" in
        *\ a\ *|*\ an\ *|*\ the\ *|*\ my\ *|*\ our\ *|*\ your\ *|\
        *\ her\ *|*\ his\ *|*\ its\ *|*\ me\ *|*\ us\ *|*\ them\ *|\
        *\ this\ *|*\ these\ *|*\ those\ *|*\ that\ *|*\ it\ *|\
        *\ to\ *|*\ for\ *|*\ of\ *|*\ in\ *|*\ on\ *|*\ at\ *|\
        *\ and\ *|*\ or\ *|*\ but\ *|*\ if\ *|*\ not\ *|\
        *\ should\ *|*\ could\ *|*\ would\ *|*\ might\ *|*\ will\ *|\
        *\ must\ *|*\ can\ *|*\ does\ *|\
        *\ just\ *|*\ also\ *|*\ only\ *|*\ very\ *|*\ really\ *|\
        *\ please\ *|*\ maybe\ *|*\ perhaps\ *|*\ probably\ *|\
        *\ is\ *|*\ are\ *|*\ was\ *|*\ were\ *|*\ have\ *|\
        *\ has\ *|*\ had\ *|*\ been\ *|*\ being\ *|*\ be\ *|\
        *\ from\ *|*\ about\ *|*\ with\ *|*\ without\ *|\
        *\ some\ *|*\ all\ *|*\ every\ *|*\ any\ *|*\ am\ *|\
        *\ like\ *|\
        *\ what\ *|*\ where\ *|*\ when\ *|*\ why\ *|*\ how\ *)
            ;;

        *)
            return 1 ;;
    esac

    # Strong NLP signals (determiners + core prepositions) — high confidence.
    case "$padded" in
        *\ a\ *|*\ the\ *|*\ my\ *|*\ our\ *|*\ your\ *)
            return 0 ;;
    esac

    # File extension in arguments → more likely command arguments.
    case "$arguments" in
        *.[a-zA-Z][a-zA-Z0-9]*[[:space:]]*|\
        *.[a-zA-Z][a-zA-Z0-9]|\
        *.[a-zA-Z])
            return 1 ;;
    esac

    return 0
}


# ---------------------------------------------------------------------------
# Session Management (native opencode style)
# ---------------------------------------------------------------------------

# The current opencode session, tracked in-memory for this shell instance only.
# Empty means "start a new session" (the native opencode default).  Set via
# /session, cleared via /new, and adopted automatically after a fresh run so
# consecutive prompts stay in the same conversation.
PROMPTLESS_ACTIVE_SESSION=""


# Resolve a path to a file inside the lib/ directory, searching the development
# layout first then the installed location.
_promptless_lib_file() {
    local name="$1"
    local dev_path="${PROMPTLESS_LIB_DIR}/${name}"
    local installed_path="${HOME}/.promptless/lib/${name}"

    if [[ -f "$dev_path" ]]; then
        echo "$dev_path"
    elif [[ -f "$installed_path" ]]; then
        echo "$installed_path"
    else
        echo ""
    fi
}


# Interactive /session command: list this directory's sessions and let the user
# pick one to continue, start a new one, or cancel.
promptless_session_picker() {
    local py
    py="$(_promptless_lib_file "sessions.py")"
    if [[ -z "$py" ]]; then
        echo "promptless: sessions.py not found (expected lib/sessions.py)" >&2
        return 1
    fi

    # The picker reads interactively, but the tty is in raw mode inside readline
    # and zle callbacks — switch to cooked mode so input() behaves normally.
    local saved_stty=""
    if [[ -t 0 ]]; then
        saved_stty="$(stty -g 2>/dev/null)" || saved_stty=""
        stty sane 2>/dev/null
    fi

    # Run with stdout redirected to a temp file rather than $(...): zsh's command
    # substitution feeds the child /dev/null, which would EOF the interactive read.
    local result_file
    result_file="$(mktemp "${TMPDIR:-/tmp}/promptless.XXXXXX" 2>/dev/null)" || result_file=""
    local result=""
    if [[ -n "$result_file" ]]; then
        python3 "$py" pick --dir "$(pwd)" --active "$PROMPTLESS_ACTIVE_SESSION" > "$result_file"
        result="$(cat "$result_file" 2>/dev/null)"
        rm -f "$result_file"
    fi

    if [[ -n "$saved_stty" ]]; then
        stty "$saved_stty" 2>/dev/null
    fi

    case "$result" in
        __PROMPTLESS_NEW__)
            PROMPTLESS_ACTIVE_SESSION=""
            echo "promptless: new session — next prompt starts fresh"
            ;;
        __PROMPTLESS_CANCEL__|"")
            echo "promptless: canceled"
            ;;
        *)
            PROMPTLESS_ACTIVE_SESSION="$result"
            echo "promptless: now using session ${result}"
            ;;
    esac
}


# /new: drop the current session so the next prompt starts a fresh one.
promptless_session_new() {
    PROMPTLESS_ACTIVE_SESSION=""
    echo "promptless: new session — next prompt starts fresh"
}


# Launch opencode with the given prompt.  If a session was selected via /session
# (or was created by an earlier prompt in this shell), it is continued with
# --session; otherwise opencode starts a fresh session, whose id the formatter
# captures so it becomes the new in-memory current session.
#
# Uses --auto so tool calls execute without blocking on interactive permission
# prompts, which cannot work in the non-interactive shell-piped mode.  Output is
# streamed through a Python formatter that handles every opencode JSON event
# type: text, tool_use (completed/error/running), and step boundaries.
opencode_with_context() {
    local prompt="$1"

    local formatter
    formatter="$(_promptless_lib_file "format_output.py")"
    if [[ -z "$formatter" ]]; then
        echo "promptless: formatter not found (expected lib/format_output.py)" >&2
        return 1
    fi

    local capture_file
    capture_file="$(mktemp "${TMPDIR:-/tmp}/promptless.XXXXXX" 2>/dev/null)" || capture_file=""
    [[ -n "$capture_file" ]] && rm -f "$capture_file"

    export PROMPTLESS_CAPTURE_FILE="$capture_file"
    if [[ -n "$PROMPTLESS_ACTIVE_SESSION" ]]; then
        opencode run --format json --auto --session "$PROMPTLESS_ACTIVE_SESSION" "$prompt" 2>&1
    else
        opencode run --format json --auto "$prompt" 2>&1
    fi | "$formatter"
    unset PROMPTLESS_CAPTURE_FILE

    if [[ -n "$capture_file" && -f "$capture_file" ]]; then
        local new_session
        new_session="$(cat "$capture_file")"
        if [[ -n "$new_session" ]]; then
            PROMPTLESS_ACTIVE_SESSION="$new_session"
        fi
        rm -f "$capture_file"
    fi
}


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

build_command_cache
