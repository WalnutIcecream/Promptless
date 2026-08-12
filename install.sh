#!/usr/bin/env bash
# Install promptless into ~/.promptless and add the appropriate source line
# to the user's shell configuration file (.bashrc or .zshrc).
set -euo pipefail

INSTALL_DIR="${HOME}/.promptless"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Installing promptless to ${INSTALL_DIR}"

mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/shell"

cp "${SCRIPT_DIR}/lib/classifier.sh"     "${INSTALL_DIR}/lib/classifier.sh"
cp "${SCRIPT_DIR}/lib/format_output.py" "${INSTALL_DIR}/lib/format_output.py"
cp "${SCRIPT_DIR}/lib/sessions.py"      "${INSTALL_DIR}/lib/sessions.py"
chmod +x "${INSTALL_DIR}/lib/format_output.py" "${INSTALL_DIR}/lib/sessions.py"
cp "${SCRIPT_DIR}/shell/promptless.bash" "${INSTALL_DIR}/shell/promptless.bash"
cp "${SCRIPT_DIR}/shell/promptless.zsh"  "${INSTALL_DIR}/shell/promptless.zsh"

shell_name="$(basename "${SHELL}")"
rc_file=""

case "${shell_name}" in
    zsh)
        rc_file="${HOME}/.zshrc"
        ;;
    bash)
        rc_file="${HOME}/.bashrc"
        ;;
    *)
        echo "⚠  Unknown shell: ${shell_name}. Source manually:"
        echo "   source ${INSTALL_DIR}/shell/promptless.<your-shell>"
        exit 1
        ;;
esac

source_line="[ -f \"\${HOME}/.promptless/shell/promptless.${shell_name}\" ] && source \"\${HOME}/.promptless/shell/promptless.${shell_name}\""

if grep -qF "promptless" "${rc_file}" 2>/dev/null; then
    echo "• Already present in ${rc_file}"
else
    echo "" >> "${rc_file}"
    echo "# promptless — route commands vs prompts to opencode" >> "${rc_file}"
    echo "${source_line}" >> "${rc_file}"
    echo "✓ Added to ${rc_file}"
fi

echo "✓ Done. Restart your shell or run:  source ${rc_file}"
