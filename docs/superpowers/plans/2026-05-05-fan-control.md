# Fan Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add motherboard fan control (CPU + case fans) from the command line via an idempotent `lm-sensors`/`fancontrol` installer, a stowed `fan` CLI wrapper, and a user guide — matching the existing pattern of `nvim` / `tmux` / `cli-readers` in this dotfiles repo.

**Architecture:** Three artifacts. `scripts/programs/fan_control.sh` apt-installs `lm-sensors` + `fancontrol` and persists the `nct6775` kernel module. `.local/bin/fan` (stowed → `~/.local/bin/fan`) is a single bash script that reads `/sys/class/hwmon/*` to display fan/temp/pwm state, writes raw PWM values for manual override, and toggles the `fancontrol` systemd service. `docs/guides/fans.md` walks through the irreducibly-manual `sensors-detect`/`pwmconfig` setup. The CLI accepts `HWMON_ROOT` and `FAN_DRY_RUN` env vars so tests can run without root and against a fake sysfs tree.

**Tech Stack:** bash, GNU Stow, lm-sensors, fancontrol, systemd, sysfs.

**Reference:** [`docs/superpowers/specs/2026-05-05-fan-control-design.md`](../specs/2026-05-05-fan-control-design.md)

---

## File structure

| Path | Status | Responsibility |
|---|---|---|
| `scripts/programs/fan_control.sh` | new | Idempotent installer: apt + modprobe + persist kernel module |
| `.local/bin/fan` | new | CLI: status/list/set/manual/auto |
| `docs/guides/fans.md` | new | One-time setup walkthrough + daily usage + troubleshooting |
| `scripts/test_fan_cli.sh` | new | Unit tests for the CLI against a fake hwmon tree |
| `scripts/test_programs.sh` | modify | Add `fan_control.sh` test case + invoke `test_fan_cli.sh` |
| `README.md` | modify | Add fan control to "What gets installed" + "User guides" |

---

## Task 1: Installer for `lm-sensors` + `fancontrol` + `nct6775`

**Files:**
- Create: `scripts/programs/fan_control.sh`
- Modify: `scripts/test_programs.sh` (add new test cases at the end of the program-script section, before the syntax-checks block at line 248)

- [ ] **Step 1: Write the failing tests in `scripts/test_programs.sh`**

Insert these blocks after the `custome_zsh.sh` test (after line 245) and before the `Syntax checks` block (line 247).

```bash
# --- fan_control.sh: skip when already installed ---
echo ""
echo "=== fan_control.sh: skip when already installed ==="
mock_sudo
# dpkg-query mock that reports both packages installed
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
# Args we care about: -W -f=${Status} <pkg>
exit 0
EOF
chmod +x "$BIN_DIR/dpkg-query"
MOCK_HOME="$TEST_DIR/home_fan_skip"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
touch "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
output=$(PATH="$BIN_DIR:$PATH" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=1 \
    bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1)
code=$?
assert_exit_zero "fan_control.sh exits 0 when already installed" "$code"
assert_output_contains "fan_control.sh prints 'Already installed: fan_control'" "Already installed: fan_control" "$output"
rm -f "$BIN_DIR/dpkg-query" "$BIN_DIR/sudo"

# --- fan_control.sh: installs packages, loads module, writes modules-load.d ---
echo ""
echo "=== fan_control.sh: installs packages and persists module ==="
FAN_LOG="$TEST_DIR/fan_calls.log"
: > "$FAN_LOG"
mock_sudo
cat > "$BIN_DIR/apt-get" <<EOF
#!/bin/bash
echo "apt-get \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/apt-get"
cat > "$BIN_DIR/modprobe" <<EOF
#!/bin/bash
echo "modprobe \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/modprobe"
MOCK_HOME="$TEST_DIR/home_fan_install"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
output=$(PATH="$BIN_DIR" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=0 \
    /bin/bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1) || true
log_content="$(cat "$FAN_LOG" 2>/dev/null)"
assert_output_contains "fan_control.sh apt-installs lm-sensors" "lm-sensors" "$log_content"
assert_output_contains "fan_control.sh apt-installs fancontrol" "fancontrol" "$log_content"
assert_output_contains "fan_control.sh modprobes nct6775" "modprobe nct6775" "$log_content"
assert_file_exists "fan_control.sh writes /etc/modules-load.d/nct6775.conf" "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
assert_output_contains "fan_control.sh prints next-steps pointer" "docs/guides/fans.md" "$output"
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/modprobe" "$BIN_DIR/sudo"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test_programs.sh 2>&1 | grep -E "fan_control|FAIL"`
Expected: at least one `FAIL` because `scripts/programs/fan_control.sh` does not exist yet.

- [ ] **Step 3: Create `scripts/programs/fan_control.sh`**

```bash
#!/bin/bash
set -euo pipefail

# Test hooks (overridable via env). Defaults match production paths.
MODULES_LOAD_DIR="${FAN_MODULES_LOAD_DIR:-/etc/modules-load.d}"
FORCE_PKG_INSTALLED="${FAN_FORCE_PKG_INSTALLED:-}"

pkg_installed() {
    local pkg="$1"
    if [ -n "$FORCE_PKG_INSTALLED" ]; then
        [ "$FORCE_PKG_INSTALLED" = "1" ]
        return
    fi
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

if pkg_installed lm-sensors \
    && pkg_installed fancontrol \
    && [ -f "$MODULES_LOAD_DIR/nct6775.conf" ]; then
    echo "Already installed: fan_control"
    exit 0
fi

echo "Installing lm-sensors + fancontrol via apt..."
sudo apt-get install -y lm-sensors fancontrol

# nct6775 covers the Nuvoton NCT67xx family used on most modern Intel/AMD
# motherboards (incl. ASRock B660M Pro RS). If your board uses ITE (it87) or
# Fintek (f71*) instead, see docs/guides/fans.md.
echo "Loading nct6775 kernel module..."
sudo modprobe nct6775 || \
    echo "warning: 'modprobe nct6775' failed. Some boards need 'acpi_enforce_resources=lax' on the kernel cmdline. See docs/guides/fans.md."

echo "Persisting nct6775 across reboots..."
echo nct6775 | sudo tee "$MODULES_LOAD_DIR/nct6775.conf" >/dev/null

cat <<'EOF'

Next steps (interactive, must be run by you):

  1. sudo sensors-detect          # answer YES to Super-I/O probe; reboot when done
  2. sudo pwmconfig               # maps PWM channels to physical fans, writes /etc/fancontrol
  3. sudo systemctl enable --now fancontrol

Full walkthrough and safety notes: docs/guides/fans.md
EOF
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test_programs.sh 2>&1 | grep -E "fan_control|FAIL"`
Expected: PASS lines for each `fan_control.sh ...` assertion, no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/programs/fan_control.sh scripts/test_programs.sh
git commit -m "feat(fan): idempotent installer for lm-sensors + fancontrol

Installs packages, loads nct6775, persists via /etc/modules-load.d.
Interactive sensors-detect/pwmconfig steps deliberately left to user."
```

---

## Task 2: CLI scaffolding — usage banner + test harness

**Files:**
- Create: `.local/bin/fan`
- Create: `scripts/test_fan_cli.sh`
- Modify: `scripts/test_programs.sh` (add invocation of `test_fan_cli.sh` after the new fan_control tests, before the syntax-checks block)

- [ ] **Step 1: Write the failing test — create `scripts/test_fan_cli.sh`**

```bash
#!/bin/bash
# Unit tests for .local/bin/fan against a fake hwmon tree.
# Sourced shared assertions from test_programs.sh would couple the files;
# keep this file standalone so it can also be run directly.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAN="$DOTFILES_DIR/.local/bin/fan"
PASS=0
FAIL=0

assert_exit_zero() {
    local desc="$1" code="$2"
    if [ "$code" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code: $code)"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_nonzero() {
    local desc="$1" code="$2"
    if [ "$code" -ne 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code was 0)"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: '$expected'"
        echo "        actual: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contents() {
    local desc="$1" file="$2" expected="$3"
    if [ -f "$file" ] && [ "$(cat "$file")" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        file: $file"
        echo "        expected: '$expected'"
        echo "        actual: '$(cat "$file" 2>/dev/null || echo '<missing>')'"
        FAIL=$((FAIL + 1))
    fi
}

# --- fixture: build a fake hwmon tree ---
HW="$(mktemp -d)"
trap 'rm -rf "$HW"' EXIT

# hwmon0: nct6798 — controllable, has fan/temp/pwm
mkdir -p "$HW/hwmon0"
echo nct6798 > "$HW/hwmon0/name"
echo 1200    > "$HW/hwmon0/fan1_input"
echo CPU_FAN > "$HW/hwmon0/fan1_label"
echo 128     > "$HW/hwmon0/pwm1"
echo 2       > "$HW/hwmon0/pwm1_enable"
echo 42000   > "$HW/hwmon0/temp1_input"
echo CPU     > "$HW/hwmon0/temp1_label"

# hwmon1: nvme — must be skipped (no pwm)
mkdir -p "$HW/hwmon1"
echo nvme    > "$HW/hwmon1/name"
echo 38000   > "$HW/hwmon1/temp1_input"

# hwmon2: coretemp — must be skipped
mkdir -p "$HW/hwmon2"
echo coretemp > "$HW/hwmon2/name"
echo 45000    > "$HW/hwmon2/temp1_input"

run_fan() { HWMON_ROOT="$HW" FAN_DRY_RUN=1 "$FAN" "$@" 2>&1; }

# --- help ---
echo ""
echo "=== fan: help / no args ==="
output=$(run_fan -h); code=$?
assert_exit_zero "fan -h exits 0" "$code"
assert_output_contains "fan -h shows usage" "Usage: fan" "$output"

# --- list ---
echo ""
echo "=== fan list ==="
output=$(run_fan list); code=$?
assert_exit_zero "fan list exits 0" "$code"
assert_output_contains "fan list shows pwm1 from nct6798" "pwm1" "$output"
assert_output_contains "fan list shows label" "CPU_FAN" "$output"
# Negative: must not list nvme/coretemp (no pwm there)

# --- status ---
echo ""
echo "=== fan status ==="
output=$(run_fan status); code=$?
assert_exit_zero "fan status exits 0" "$code"
assert_output_contains "fan status shows fan RPM" "1200" "$output"
assert_output_contains "fan status shows temp in C" "42" "$output"
assert_output_contains "fan status shows PWM percent" "50%" "$output"
assert_output_contains "fan status shows mode label" "auto" "$output"

# --- set: validation ---
echo ""
echo "=== fan set: validation ==="
output=$(run_fan set pwm1 101); code=$?
assert_exit_nonzero "fan set rejects >100" "$code"
output=$(run_fan set pwm1 -1); code=$?
assert_exit_nonzero "fan set rejects negative" "$code"
output=$(run_fan set pwm1 abc); code=$?
assert_exit_nonzero "fan set rejects non-integer" "$code"
output=$(run_fan set pwm1 0); code=$?
assert_exit_nonzero "fan set rejects 0 without --force" "$code"
output=$(run_fan set pwm9 50); code=$?
assert_exit_nonzero "fan set rejects unknown channel" "$code"
assert_output_contains "fan set unknown-channel error lists pwm1" "pwm1" "$output"

# --- set: writes ---
echo ""
echo "=== fan set: writes pwm and pwm_enable ==="
output=$(run_fan set pwm1 60); code=$?
assert_exit_zero "fan set pwm1 60 exits 0" "$code"
assert_file_contents "pwm1_enable was set to 1 (manual)" "$HW/hwmon0/pwm1_enable" "1"
assert_file_contents "pwm1 was set to 153 (60% of 255)" "$HW/hwmon0/pwm1" "153"

# --force allows zero
echo 2 > "$HW/hwmon0/pwm1_enable"  # reset
echo 128 > "$HW/hwmon0/pwm1"
output=$(run_fan set pwm1 0 --force); code=$?
assert_exit_zero "fan set pwm1 0 --force exits 0" "$code"
assert_file_contents "pwm1 was set to 0 with --force" "$HW/hwmon0/pwm1" "0"

# --- manual / auto: dry-run prints systemctl invocation ---
echo ""
echo "=== fan manual / auto (dry run) ==="
output=$(run_fan manual); code=$?
assert_exit_zero "fan manual exits 0 (dry run)" "$code"
assert_output_contains "fan manual would stop fancontrol" "systemctl stop fancontrol" "$output"
output=$(run_fan auto); code=$?
assert_exit_zero "fan auto exits 0 (dry run)" "$code"
assert_output_contains "fan auto would start fancontrol" "systemctl start fancontrol" "$output"

# --- empty hwmon tree: status fails clearly ---
echo ""
echo "=== fan status: no controllable fans ==="
EMPTY="$(mktemp -d)"
trap 'rm -rf "$HW" "$EMPTY"' EXIT
output=$(HWMON_ROOT="$EMPTY" FAN_DRY_RUN=1 "$FAN" status 2>&1); code=$?
assert_exit_nonzero "fan status exits non-zero on empty tree" "$code"
assert_output_contains "fan status references the guide" "docs/guides/fans.md" "$output"

# --- summary ---
echo ""
echo "=========================================="
echo "  fan CLI: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
```

Make it executable:

```bash
chmod +x scripts/test_fan_cli.sh
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bash scripts/test_fan_cli.sh`
Expected: every assertion FAILS with "No such file or directory" because `.local/bin/fan` does not exist yet.

- [ ] **Step 3: Create `.local/bin/fan` skeleton**

```bash
#!/bin/bash
set -euo pipefail

HWMON_ROOT="${HWMON_ROOT:-/sys/class/hwmon}"
FAN_DRY_RUN="${FAN_DRY_RUN:-0}"

# Chips that expose controllable PWM channels. Other hwmon devices
# (nvme, coretemp, iwlwifi, …) only expose temps and are filtered out.
fan_chip_pattern='^(nct6|it87|f71)'

usage() {
    cat <<'EOF'
Usage: fan <command> [args]

Commands:
  status                 Show fans, temps, PWM levels, and fancontrol service state
  list                   List controllable PWM channels (pwm1, pwm2, …) with paths
  set <pwmN> <0-100>     Set PWM as a percentage. Add --force to allow 0.
                         Switches the channel to manual mode (pwm_enable=1).
  manual                 Stop the fancontrol service so manual values stick
  auto                   Start the fancontrol service (curve resumes)
  help, -h, --help       Show this help

Environment:
  HWMON_ROOT             Override sysfs root (default: /sys/class/hwmon)
  FAN_DRY_RUN=1          Print systemctl commands instead of running them

See docs/guides/fans.md for setup, fan curves, and safety notes.
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        help|-h|--help) usage ;;
        list)           cmd_list ;;
        status)         cmd_status ;;
        set)            cmd_set "$@" ;;
        manual)         cmd_manual ;;
        auto)           cmd_auto ;;
        *)              usage; exit 1 ;;
    esac
}

# Stubs filled in by later tasks. Each prints "not implemented" and exits 1
# so the suite shows clear failures until each subcommand lands.
cmd_list()    { echo "not implemented: list"   >&2; exit 1; }
cmd_status()  { echo "not implemented: status" >&2; exit 1; }
cmd_set()     { echo "not implemented: set"    >&2; exit 1; }
cmd_manual()  { echo "not implemented: manual" >&2; exit 1; }
cmd_auto()    { echo "not implemented: auto"   >&2; exit 1; }

main "$@"
```

Make it executable:

```bash
chmod +x .local/bin/fan
```

- [ ] **Step 4: Wire `test_fan_cli.sh` into `test_programs.sh`**

Add this block in `scripts/test_programs.sh` immediately before the `# --- Syntax checks ---` block (around line 247):

```bash
# --- fan CLI: dispatch to dedicated test file ---
echo ""
echo "=== fan CLI ==="
if bash "$DOTFILES_DIR/scripts/test_fan_cli.sh"; then
    echo "  PASS: fan CLI suite"
    PASS=$((PASS + 1))
else
    echo "  FAIL: fan CLI suite"
    FAIL=$((FAIL + 1))
fi
```

- [ ] **Step 5: Run only the help test to verify the skeleton works**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "help|Usage|FAIL" | head -5`
Expected: PASS for `fan -h exits 0` and `fan -h shows usage`. The other subcommand tests will still FAIL — that's expected; they're filled in by later tasks.

- [ ] **Step 6: Commit**

```bash
git add .local/bin/fan scripts/test_fan_cli.sh scripts/test_programs.sh
git commit -m "feat(fan): scaffold 'fan' CLI with help and test harness

Subcommands stubbed; fake-hwmon test fixture in scripts/test_fan_cli.sh
covers list/status/set/manual/auto via HWMON_ROOT + FAN_DRY_RUN."
```

---

## Task 3: `fan list`

**Files:**
- Modify: `.local/bin/fan` (replace `cmd_list` stub)

- [ ] **Step 1: Run the existing `fan list` test to confirm it fails**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan list|FAIL"`
Expected: FAIL for `fan list exits 0`, `fan list shows pwm1 from nct6798`, `fan list shows label`.

- [ ] **Step 2: Add helpers + implement `cmd_list`**

Add these helpers above the `cmd_list` stub in `.local/bin/fan`:

```bash
# Iterate over hwmon dirs whose 'name' matches the fan-chip allowlist.
# Prints one chip path per line.
fan_chips() {
    local d name
    for d in "$HWMON_ROOT"/hwmon*; do
        [ -d "$d" ] || continue
        name="$(cat "$d/name" 2>/dev/null || echo "")"
        if [[ "$name" =~ $fan_chip_pattern ]]; then
            printf '%s\n' "$d"
        fi
    done
}

# Resolve a user-typed channel ('pwm1') to its absolute sysfs path.
# Prints the path on stdout; returns non-zero if not found / ambiguous.
resolve_pwm() {
    local key="$1" matches=() chip
    while read -r chip; do
        [ -z "$chip" ] && continue
        if [ -f "$chip/$key" ]; then
            matches+=("$chip/$key")
        fi
    done < <(fan_chips)
    case "${#matches[@]}" in
        0) return 1 ;;
        1) printf '%s\n' "${matches[0]}" ;;
        *) printf 'ambiguous: %s\n' "${matches[@]}" >&2; return 2 ;;
    esac
}
```

Replace the `cmd_list` stub:

```bash
cmd_list() {
    local chip name pwm pwm_name label_file label
    local found=0
    while read -r chip; do
        [ -z "$chip" ] && continue
        name="$(cat "$chip/name")"
        for pwm in "$chip"/pwm[0-9]*; do
            [ -f "$pwm" ] || continue
            # Skip the *_enable / *_mode / *_freq pseudo-files
            case "$pwm" in
                *_enable|*_mode|*_freq) continue ;;
            esac
            pwm_name="$(basename "$pwm")"
            # Try fanN_label where N matches the trailing digit of pwmN
            label="-"
            label_file="$chip/fan${pwm_name#pwm}_label"
            [ -f "$label_file" ] && label="$(cat "$label_file")"
            printf '%-6s  %s  (%s, %s)\n' "$pwm_name" "$pwm" "$name" "$label"
            found=1
        done
    done < <(fan_chips)
    if [ "$found" -eq 0 ]; then
        echo "error: no controllable fans detected. Did you run sensors-detect and reboot? See docs/guides/fans.md." >&2
        exit 1
    fi
}
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan list|FAIL"`
Expected: 3 PASS lines for `fan list ...`, 0 FAIL lines for `fan list`.

- [ ] **Step 4: Commit**

```bash
git add .local/bin/fan
git commit -m "feat(fan): implement 'fan list' subcommand

Enumerates pwm channels under HWMON_ROOT, filters to fan-controller chips
(nct6*/it87/f71*), shows path + chip + fan label."
```

---

## Task 4: `fan status`

**Files:**
- Modify: `.local/bin/fan` (replace `cmd_status` stub)

- [ ] **Step 1: Confirm `fan status` tests still fail**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan status|FAIL"`
Expected: FAIL for `fan status exits 0`, RPM, temp, PWM percent, mode lines, and the empty-tree non-zero-exit assertion.

- [ ] **Step 2: Implement `cmd_status`**

Replace the `cmd_status` stub in `.local/bin/fan`:

```bash
cmd_status() {
    local chip name f label rpm n temp_milli temp_label pwm pwm_n raw_pct mode mode_label
    local found=0

    while read -r chip; do
        [ -z "$chip" ] && continue
        name="$(cat "$chip/name")"
        echo "=== $name  ($chip) ==="
        # Fans
        for f in "$chip"/fan[0-9]*_input; do
            [ -f "$f" ] || continue
            n="$(basename "$f")"; n="${n#fan}"; n="${n%_input}"
            rpm="$(cat "$f")"
            label="fan${n}"
            [ -f "$chip/fan${n}_label" ] && label="$(cat "$chip/fan${n}_label")"
            printf '  %-12s  %5s RPM\n' "$label" "$rpm"
            found=1
        done
        # Temps
        for f in "$chip"/temp[0-9]*_input; do
            [ -f "$f" ] || continue
            n="$(basename "$f")"; n="${n#temp}"; n="${n%_input}"
            temp_milli="$(cat "$f")"
            temp_label="temp${n}"
            [ -f "$chip/temp${n}_label" ] && temp_label="$(cat "$chip/temp${n}_label")"
            printf '  %-12s  %5d C\n' "$temp_label" $((temp_milli / 1000))
        done
        # PWMs
        for pwm in "$chip"/pwm[0-9]*; do
            [ -f "$pwm" ] || continue
            case "$pwm" in *_enable|*_mode|*_freq) continue ;; esac
            pwm_n="$(basename "$pwm")"
            raw_pct=$(( ($(cat "$pwm") * 100 + 127) / 255 ))
            mode_label="auto"
            if [ -f "${pwm}_enable" ]; then
                mode="$(cat "${pwm}_enable")"
                case "$mode" in
                    0) mode_label="off" ;;
                    1) mode_label="manual" ;;
                    2|3|4|5) mode_label="auto" ;;
                    *) mode_label="mode=$mode" ;;
                esac
            fi
            printf '  %-12s  %4d%%   (%s)\n' "$pwm_n" "$raw_pct" "$mode_label"
        done
    done < <(fan_chips)

    if [ "$found" -eq 0 ]; then
        echo "error: no controllable fans detected. Did you run sensors-detect and reboot? See docs/guides/fans.md." >&2
        exit 1
    fi

    echo ""
    if [ "$FAN_DRY_RUN" = "1" ]; then
        echo "fancontrol service: (dry-run; not queried)"
    else
        local svc
        svc="$(systemctl is-active fancontrol 2>/dev/null || echo not-installed)"
        echo "fancontrol service: $svc"
    fi
}
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan status|FAIL"`
Expected: 5 PASS lines for `fan status ...` plus the empty-tree assertion. The `set` and `manual`/`auto` tests are still FAIL — that's expected.

- [ ] **Step 4: Commit**

```bash
git add .local/bin/fan
git commit -m "feat(fan): implement 'fan status' subcommand

Tabular view of fans (RPM), temps (°C), PWM (%) and pwm_enable mode
per chip, plus current fancontrol service state."
```

---

## Task 5: `fan set` — validation

**Files:**
- Modify: `.local/bin/fan` (replace `cmd_set` stub with validation only; writes come in Task 6)

- [ ] **Step 1: Confirm `fan set` validation tests fail**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan set: validation|FAIL"`
Expected: 6 FAILs (>100, negative, non-integer, 0-without-force, unknown channel, unknown-channel-mentions-pwm1).

- [ ] **Step 2: Implement `cmd_set` validation half**

Replace the `cmd_set` stub in `.local/bin/fan`:

```bash
cmd_set() {
    local key="${1:-}" pct="${2:-}" flag="${3:-}"
    if [ -z "$key" ] || [ -z "$pct" ]; then
        echo "usage: fan set <pwmN> <0-100> [--force]" >&2
        exit 1
    fi
    if ! [[ "$pct" =~ ^-?[0-9]+$ ]]; then
        echo "error: percentage must be an integer (got: $pct)" >&2
        exit 1
    fi
    if [ "$pct" -lt 0 ] || [ "$pct" -gt 100 ]; then
        echo "error: percentage must be between 0 and 100 (got: $pct)" >&2
        exit 1
    fi
    if [ "$pct" -eq 0 ] && [ "$flag" != "--force" ]; then
        echo "error: refusing to set fan to 0%. Use --force if you really mean it." >&2
        exit 1
    fi

    local pwm_path
    if ! pwm_path="$(resolve_pwm "$key")"; then
        echo "error: unknown channel '$key'. Available channels:" >&2
        cmd_list >&2 || true
        exit 1
    fi

    # Writes land in Task 6. For now, validate-only path exits 0 so tests
    # for the invalid-input branches go green; the "writes pwm and pwm_enable"
    # block in test_fan_cli.sh is still expected to FAIL until Task 6.
    echo "validated: $pwm_path = $pct%"
}
```

- [ ] **Step 3: Run validation tests to verify they pass**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan set: validation|FAIL"`
Expected: 6 PASS lines for the validation block. The "writes pwm and pwm_enable" block still FAILs (`pwm1_enable was set to 1`, `pwm1 was set to 153`, `pwm1 was set to 0 with --force`).

- [ ] **Step 4: Commit**

```bash
git add .local/bin/fan
git commit -m "feat(fan): validate 'fan set' arguments

Range/integer/zero/--force/unknown-channel checks, with the unknown-channel
error printing the available channel list."
```

---

## Task 6: `fan set` — writes

**Files:**
- Modify: `.local/bin/fan` (extend `cmd_set` to actually write pwm + pwm_enable)

- [ ] **Step 1: Confirm the write tests fail**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "writes pwm|153|--force|FAIL"`
Expected: FAILs for `pwm1_enable was set to 1`, `pwm1 was set to 153`, `pwm1 was set to 0 with --force`.

- [ ] **Step 2: Add a writer helper + extend `cmd_set`**

Add this helper next to `resolve_pwm` in `.local/bin/fan`:

```bash
# Write a value to a sysfs file. Goes through sudo unless we are already
# root or this is a writable test path under HWMON_ROOT.
fan_write() {
    local target="$1" value="$2"
    if [ -w "$target" ]; then
        printf '%s\n' "$value" > "$target"
    else
        printf '%s\n' "$value" | sudo tee "$target" >/dev/null
    fi
}
```

Replace the final `echo "validated: ..."` line in `cmd_set` with:

```bash
    local raw=$(( pct * 255 / 100 ))
    # Warn (but don't refuse) if fancontrol will overwrite us in seconds.
    if [ "$FAN_DRY_RUN" != "1" ]; then
        if systemctl is-active --quiet fancontrol 2>/dev/null; then
            echo "warning: fancontrol is running; it will overwrite this on its next tick (~10s). Run 'fan manual' first to hold the value." >&2
        fi
    fi
    fan_write "${pwm_path}_enable" 1
    fan_write "$pwm_path" "$raw"
    echo "set $key = ${pct}% (raw=${raw}, manual mode)"
```

- [ ] **Step 3: Run write tests to verify they pass**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "writes pwm|153|--force|FAIL"`
Expected: 3 PASS lines for the write assertions. Validation block still passes (regression check).

- [ ] **Step 4: Commit**

```bash
git add .local/bin/fan
git commit -m "feat(fan): 'fan set' writes pwm + pwm_enable=1

60% → 153/255. Warns if fancontrol is active so the user knows the value
will be overwritten on the next daemon tick."
```

---

## Task 7: `fan manual` and `fan auto`

**Files:**
- Modify: `.local/bin/fan` (replace `cmd_manual` and `cmd_auto` stubs)

- [ ] **Step 1: Confirm dry-run tests fail**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan manual|fan auto|FAIL"`
Expected: 4 FAILs for `fan manual exits 0 (dry run)`, `fan manual would stop ...`, `fan auto exits 0 (dry run)`, `fan auto would start ...`.

- [ ] **Step 2: Add a service helper + replace stubs**

Add this helper next to `fan_write` in `.local/bin/fan`:

```bash
fan_systemctl() {
    local action="$1"
    if [ "$FAN_DRY_RUN" = "1" ]; then
        echo "(dry-run) would: systemctl $action fancontrol"
        return 0
    fi
    if ! systemctl list-unit-files fancontrol.service >/dev/null 2>&1 \
       || ! systemctl cat fancontrol >/dev/null 2>&1; then
        echo "error: fancontrol is not configured yet. Run 'sudo pwmconfig' first; see docs/guides/fans.md." >&2
        exit 1
    fi
    sudo systemctl "$action" fancontrol
}
```

Replace the two stubs:

```bash
cmd_manual() { fan_systemctl stop;  echo "fancontrol stopped — manual fan values will hold."; }
cmd_auto()   { fan_systemctl start; echo "fancontrol started — temperature curve is active."; }
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `bash scripts/test_fan_cli.sh 2>&1 | grep -E "fan manual|fan auto|FAIL"`
Expected: 4 PASS lines, no FAILs.

- [ ] **Step 4: Run the full test suite end-to-end**

Run: `bash scripts/test_programs.sh`
Expected: all assertions PASS, including the `fan_control.sh` and `fan CLI suite` blocks. Final line `Test Results: <N> passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .local/bin/fan
git commit -m "feat(fan): 'fan manual' and 'fan auto' toggle fancontrol service

Refuses to act if fancontrol.service isn't configured yet; FAN_DRY_RUN=1
prints the systemctl invocation instead of running it."
```

---

## Task 8: User guide

**Files:**
- Create: `docs/guides/fans.md`

- [ ] **Step 1: Write `docs/guides/fans.md`**

```markdown
# Fan control

This guide covers controlling motherboard / CPU / case fans on the desktop. **GPU fans are out of scope** — see `nvidia-settings`, `nvfancontrol`, or GreenWithEnvy for the RTX side.

## What gets installed

`scripts/programs/fan_control.sh` apt-installs `lm-sensors` and `fancontrol`, loads the `nct6775` kernel module, and persists it via `/etc/modules-load.d/nct6775.conf`. After install, the rest is one-time interactive setup that this guide walks you through.

The `.local/bin/fan` CLI (stowed to `~/.local/bin/fan`) wraps the daily-use operations.

## One-time setup

### 1. Detect sensors

```bash
sudo sensors-detect
```

Defaults are safe. The important question is **"Probe for Super-I/O sensors?"** — answer **YES**. When done, accept its offer to write `/etc/modules-load.d/...`. Reboot.

After reboot, verify PWM channels appeared:

```bash
fan list
```

If nothing is listed, see "Troubleshooting" below.

### 2. Map fans to PWM channels

```bash
sudo pwmconfig
```

This is interactive. It will:

1. Spin every fan down to 0 RPM, one at a time.
2. Ask you which fan stopped — that's how it identifies which `pwmN` controls which physical fan.
3. Write `/etc/fancontrol` with your chosen curve.

**Safety:** while `pwmconfig` runs, fans really do go to 0%. Watch your CPU temperature in another shell (`watch -n1 sensors`). If a fan refuses to start back up, write `2` (or `5`) to its `pwm*_enable` to return control to the BIOS, or just reboot.

### 3. Enable the daemon at boot

```bash
sudo systemctl enable --now fancontrol
fan status     # should show 'fancontrol service: active'
```

## The fan curve (`/etc/fancontrol`)

`/etc/fancontrol` is plain text; restart the service after editing. Key fields:

```
INTERVAL=10
DEVPATH=hwmon4=devices/platform/nct6775.656
DEVNAME=hwmon4=nct6798
FCTEMPS=hwmon4/pwm2=hwmon4/temp1_input
MINTEMP=hwmon4/pwm2=40
MAXTEMP=hwmon4/pwm2=75
MINSTART=hwmon4/pwm2=80
MINSTOP=hwmon4/pwm2=60
```

| Field | Meaning |
|---|---|
| `INTERVAL` | Seconds between recalculations. 10 is sane. |
| `FCTEMPS` | Which temperature drives this PWM. |
| `MINTEMP` / `MAXTEMP` | Curve endpoints, in °C. |
| `MINSTART` | PWM (raw 0–255) used to *spin up* a stopped fan. |
| `MINSTOP` | PWM below which the fan is allowed to stop. Set this above your fan's actual stall PWM or it will buzz. |

After editing:

```bash
sudo systemctl restart fancontrol
journalctl -u fancontrol -n 50
```

Back this file up — the `pwmconfig` walkthrough is annoying to redo from scratch.

## Daily use

```bash
fan status                  # what's running and how fast
fan list                    # available pwm channels
fan set pwm2 60             # 60% on pwm2 (manual mode)
fan set pwm2 0 --force      # really turn it off
fan manual                  # stop fancontrol so manual values stick
fan auto                    # resume the temperature curve
```

`fan set` writes `1` to `pwm*_enable` (manual mode) and the corresponding raw 0-255 value. If `fancontrol` is running, it will overwrite your value within ~10 seconds — `fan set` warns when this is the case; run `fan manual` first if you want the value to hold.

## Safety notes

- **Never leave the CPU fan at 0%.** The CLI refuses 0 by default; only override with `--force` when you have a thermometer on the temperatures.
- **Verify after every curve change.** `watch -n1 sensors` in one pane, run a CPU-bound workload in another, watch temps level off.
- **Panic button:** if anything spikes, `fan set <cpu_pwm> 100` immediately, then `fan auto`, then investigate.

## Troubleshooting

**`fan list` shows nothing after `sensors-detect` and reboot.**
The Super-I/O driver isn't binding. Some boards reserve the I/O ports for ACPI; tell the kernel to share them by adding `acpi_enforce_resources=lax` to the kernel cmdline (edit `/etc/default/grub`, append to `GRUB_CMDLINE_LINUX_DEFAULT`, then `sudo update-grub` and reboot).

**`fancontrol` fails to start.**
```bash
sudo systemctl status fancontrol
journalctl -u fancontrol -n 100
```
The most common cause is a stale `DEVPATH=hwmon4=...` after a kernel upgrade re-numbered hwmon devices. Re-run `sudo pwmconfig` to regenerate.

**`fan set` succeeds but the fan returns to its old speed.**
`fancontrol` is overwriting the value. Run `fan manual` first.

**ITE or Fintek board (not Nuvoton).**
Replace `nct6775` with `it87` or `f71808e_wdt` (driver names vary by chip family) in `/etc/modules-load.d/`. The `fan` CLI auto-discovers any `nct6*`/`it87`/`f71*` chip, no further changes needed.

## See also

- `man fancontrol` — config file reference
- `man pwmconfig` — what the interactive walkthrough does
- `man sensors-detect` — what to answer at each prompt
- `~/.dotfiles/scripts/programs/fan_control.sh` — installer source
- `~/.local/bin/fan` — CLI source
```

- [ ] **Step 2: Render-check the guide**

Run: `glow docs/guides/fans.md | head -40`
Expected: well-formatted markdown with no rendering errors. (If `glow` isn't installed yet on this machine, fall back to `less docs/guides/fans.md`.)

- [ ] **Step 3: Commit**

```bash
git add docs/guides/fans.md
git commit -m "docs(fans): user guide for fan control

Covers sensors-detect / pwmconfig setup, /etc/fancontrol curve format,
'fan' CLI usage, safety notes, troubleshooting (acpi_enforce_resources=lax,
hwmon renumbering, ITE/Fintek boards)."
```

---

## Task 9: README updates

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add fan control to "What gets installed"**

Edit `README.md` table at lines 7-19. Add a new row immediately after the Multiplexer row (line 14):

```markdown
| Fan control | lm-sensors, fancontrol (with `fan` CLI wrapper at `~/.local/bin/fan`) |
```

- [ ] **Step 2: Add fan guide to "User guides"**

Edit `README.md` table at lines 78-82. Add a new row after the `cli-readers.md` row:

```markdown
| [`docs/guides/fans.md`](docs/guides/fans.md) | Motherboard/CPU/case fan control via `fan` CLI; `sensors-detect`/`pwmconfig` setup, fan curves, troubleshooting |
```

- [ ] **Step 3: Add `fans.md` to the repository-structure tree**

Edit `README.md` at lines 127-131 (the `docs/guides/` listing inside the structure block). Add `fans.md` after `cli-readers.md`:

```
│   │   ├── nvim.md
│   │   ├── tmux.md
│   │   ├── cli-readers.md
│   │   └── fans.md
```

(Re-flow the box-drawing characters so the entry above `fans.md` uses `├──` and `fans.md` itself uses `└──`.)

- [ ] **Step 4: Add `fan_control.sh` to the scripts/programs listing**

Edit `README.md` at lines 138-147 (the `scripts/programs/` listing). Insert after `docker.sh`:

```
        ├── fan_control.sh      # lm-sensors + fancontrol + nct6775 module
```

- [ ] **Step 5: Verify the file renders sanely**

Run: `glow README.md | head -120`
Expected: tables and the structure tree render correctly; no broken markdown.

- [ ] **Step 6: Run the full test suite one more time**

Run: `bash scripts/test_programs.sh && bash scripts/test_orchestrator.sh`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs(readme): list fan control in installed-tools, guides, and tree"
```

---

## Final verification

- [ ] `bash scripts/test_programs.sh` — all PASS, includes new fan_control + fan CLI suite
- [ ] `bash scripts/test_orchestrator.sh` — all PASS (no regressions)
- [ ] `bash -n scripts/programs/fan_control.sh` and `bash -n .local/bin/fan` — clean syntax
- [ ] `git log --oneline | head -10` shows one focused commit per task
- [ ] On the actual machine (separate from the test harness): run `bash scripts/programs/fan_control.sh`, then walk through `sensors-detect` and `pwmconfig`, then verify `fan status` shows real RPMs and `fan set pwmN 70` measurably changes a fan
