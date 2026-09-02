#!/bin/bash
# Tests for scripts/programs/docker.sh
#
# Runnable on its own:  bash scripts/tests/test_docker.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

DOCKER_SH="$DOTFILES_DIR/scripts/programs/docker.sh"

# `id -nG` decides the group step. Mock it rather than depend on whoever runs the
# suite actually being in (or out of) the docker group.
mock_id_groups() {
    printf '#!/bin/bash\necho "%s"\n' "$1" > "$BIN_DIR/id"
    chmod +x "$BIN_DIR/id"
}

# --- docker.sh: every step skips on a fully provisioned machine ---
echo ""
echo "=== docker.sh: skip when already installed ==="
mock_failing_cmd snap          # `snap list docker` fails => no snap install
mock_cmd docker
mock_id_groups "tester sudo docker"
EXISTING_LIST="$TEST_DIR/docker.list"
touch "$EXISTING_LIST"
output=$(PATH="$BIN_DIR:$PATH" DOCKER_APT_LIST="$EXISTING_LIST" bash "$DOCKER_SH" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when already installed" "$code"
assert_output_contains "docker.sh skips the apt repo" "Already installed: Docker apt repo" "$output"
assert_output_contains "docker.sh prints 'Already installed: docker'" "Already installed: docker" "$output"
assert_output_contains "docker.sh skips the group step" "in docker group" "$output"
assert_output_not_contains "docker.sh does not reinstall the package" "Installing Docker..." "$output"

# --- docker.sh: refuses to run alongside the confined snap ---
# A snap install satisfies `command -v docker`, so without the guard the script
# would report success and leave the confined version in place.
echo ""
echo "=== docker.sh: warns and stops when the docker snap is present ==="
mock_cmd snap                  # `snap list docker` succeeds => snap is installed
output=$(PATH="$BIN_DIR:$PATH" DOCKER_APT_LIST="$EXISTING_LIST" bash "$DOCKER_SH" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when the snap is present" "$code"
assert_output_contains "docker.sh warns about the snap" "installed as a snap" "$output"
assert_output_contains "docker.sh says how to remove it" "snap remove --purge docker" "$output"
assert_output_not_contains "docker.sh installs nothing while the snap is there" "Installing Docker..." "$output"
assert_output_not_contains "docker.sh does not touch the apt repo" "Adding Docker apt repo" "$output"
mock_failing_cmd snap          # back to "no snap" for the remaining cases

# --- docker.sh: adds the apt repo when the sources file is absent ---
echo ""
echo "=== docker.sh: adds Docker's apt repo when missing ==="
APT_LOG="$TEST_DIR/apt.log"
mock_sudo
mock_logging_cmds "$APT_LOG" curl chmod apt-get
MISSING_LIST="$TEST_DIR/new-docker.list"
output=$(PATH="$BIN_DIR:$PATH" DOCKER_APT_LIST="$MISSING_LIST" \
    DOCKER_KEYRING="$TEST_DIR/keyrings/docker.asc" bash "$DOCKER_SH" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when adding the repo" "$code"
assert_output_contains "docker.sh announces the repo step" "Adding Docker apt repo..." "$output"
assert_file_exists "docker.sh writes the apt sources file" "$MISSING_LIST"
assert_file_contains "docker.sh points apt at download.docker.com" \
    "$MISSING_LIST" "https://download.docker.com/linux/ubuntu"
assert_file_contains "docker.sh signs the repo with the keyring" "$MISSING_LIST" "signed-by="
assert_dir_exists "docker.sh creates the keyring dir" "$TEST_DIR/keyrings"
assert_file_contains "docker.sh fetches the key with curl" "$APT_LOG" "download.docker.com/linux/ubuntu/gpg"
assert_file_contains "docker.sh refreshes the package lists" "$APT_LOG" "apt-get update"

# --- docker.sh: the group step is guarded separately from the install ---
# Regression test. The previous version wrapped the install and the usermod in
# one `command -v docker` check, so on a machine that already had Docker the
# group was never added and every docker call needed sudo. docker is mocked as
# present here, and the group step must still run.
echo ""
echo "=== docker.sh: adds the docker group even when docker is installed ==="
GROUP_LOG="$TEST_DIR/group.log"
mock_id_groups "tester sudo"   # deliberately NOT in the docker group
mock_logging_cmds "$GROUP_LOG" groupadd usermod
output=$(PATH="$BIN_DIR:$PATH" DOCKER_APT_LIST="$EXISTING_LIST" bash "$DOCKER_SH" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when adding the group" "$code"
assert_output_contains "docker.sh skips the install" "Already installed: docker" "$output"
assert_output_contains "docker.sh still runs the group step" "to the docker group..." "$output"
assert_file_contains "docker.sh calls usermod -aG docker" "$GROUP_LOG" "usermod -aG docker"
assert_output_contains "docker.sh tells the user to re-login" "Log out and back in" "$output"

finish_suite "docker.sh"
