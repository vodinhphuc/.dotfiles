#!/bin/bash
# Cross-cutting checks over every shell script in the repo: bash syntax, plus
# the static-analysis lint that the coding conventions require to be clean.
# (Careful editing this header: a comment line starting with the linter's own
# name is parsed as a directive, not prose.)
#
# Runnable on its own:  bash scripts/tests/test_lint.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"

# --- Syntax checks ---
echo ""
echo "=== Syntax checks ==="
for script in "$DOTFILES_DIR"/scripts/programs/*.sh; do
    name="$(basename "$script")"
    if bash -n "$script" 2>/dev/null; then
        echo "  PASS: $name syntax OK"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name has syntax errors"
        bash -n "$script" 2>&1 | sed 's/^/        /'
        FAIL=$((FAIL + 1))
    fi
done

# --- ShellCheck lint (enforced: every repo script must pass `shellcheck -x`) ---
echo ""
echo "=== ShellCheck lint ==="
# scripts/ is uniformly *.sh, but .local/bin holds extensionless stowed CLIs
# (fan, rgb) sitting next to runtime-installed binaries (uv, uvx) and symlinks,
# which shellcheck cannot read. Select those by shebang instead of globbing
# blindly, and read only the first line -- uv is ~60MB.
lint_targets() {
    local f shebang
    # scripts/tests/ and its lib/ are included deliberately: when the suites
    # moved out of the old monolith they silently dropped out of lint coverage,
    # because this glob only knew about scripts/ and scripts/programs/.
    for f in "$DOTFILES_DIR"/scripts/*.sh \
             "$DOTFILES_DIR"/scripts/programs/*.sh \
             "$DOTFILES_DIR"/scripts/tests/*.sh \
             "$DOTFILES_DIR"/scripts/tests/lib/*.sh; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    for f in "$DOTFILES_DIR"/.local/bin/*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        # Gate on the two magic bytes first, without a command substitution:
        # capturing bytes from the multi-megabyte binaries that also live here
        # makes bash warn about ignored null bytes on every run. Anything that
        # clears this gate is a text script, so reading its first line is safe.
        head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
        IFS= read -r shebang < "$f" || shebang=""
        if [[ "$shebang" =~ ^#!.*[/[:space:]](ba)?sh([[:space:]]|$) ]]; then
            printf '%s\n' "$f"
        fi
    done
}

if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r script; do
        name="${script#"$DOTFILES_DIR"/}"
        if shellcheck -x "$script" >/dev/null 2>&1; then
            echo "  PASS: $name shellcheck clean"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $name has shellcheck findings"
            shellcheck -x "$script" 2>&1 | sed 's/^/        /'
            FAIL=$((FAIL + 1))
        fi
    done < <(lint_targets)
else
    echo "  SKIP: shellcheck not installed — run 'bash scripts/programs/shellcheck.sh' to enable this check"
fi

finish_suite "lint"
