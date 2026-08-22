#!/bin/bash
# Shared fixture setup for the suites in scripts/tests/.
#
# Sourced, never executed. Gives every suite its own throwaway TEST_DIR and a
# BIN_DIR to prepend to PATH, which is how these tests stay free of sudo, of
# the network, and of whatever happens to be installed on the machine.
#
# The EXIT trap is set here, so a suite that sources this cleans up after
# itself whether it is run on its own or by the runner.

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"

# Creates a fake binary that does nothing (exit 0)
mock_cmd() {
    printf '#!/bin/bash\nexit 0\n' > "$BIN_DIR/$1"
    chmod +x "$BIN_DIR/$1"
}

# Creates a fake sudo that just runs the rest of the command as current user
mock_sudo() {
    printf '#!/bin/bash\n"$@"\n' > "$BIN_DIR/sudo"
    chmod +x "$BIN_DIR/sudo"
}

# Reports every queried package as installed, so the apt-dep step is skipped.
mock_dpkg_query_all_installed() {
    printf '#!/bin/bash\necho "install ok installed"\nexit 0\n' > "$BIN_DIR/dpkg-query"
    chmod +x "$BIN_DIR/dpkg-query"
}

# Logging mocks: record argv instead of executing, so nothing is really installed.
mock_logging_cmds() {
    local log="$1"; shift
    local cmd
    for cmd in "$@"; do
        cat > "$BIN_DIR/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$log"
exit 0
EOF
        chmod +x "$BIN_DIR/$cmd"
    done
}
