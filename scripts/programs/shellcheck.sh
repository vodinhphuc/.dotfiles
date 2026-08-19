#!/bin/bash
set -euo pipefail

# Static analysis linter (shellcheck) for shell scripts. Used to vet the
# install scripts and utilities in this repo before they touch a real machine.
if ! command -v shellcheck &>/dev/null; then
    echo "Installing shellcheck..."
    sudo apt-get install -y shellcheck
else
    echo "Already installed: shellcheck"
fi
