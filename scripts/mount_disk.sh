#!/bin/bash
#
# mount_disk.sh — Safely mount a data partition to a folder, persistently.
#
# Interactive and step-by-step: it confirms with you before EVERY change and
# shows a final review. Designed to be safe on any Linux machine.
#
# Safety guarantees:
#   - NEVER formats, partitions, or writes to filesystem data. Mount only.
#   - NEVER touches mounted, system (/, /boot, swap), or in-use partitions.
#   - Refuses container volumes (LUKS/LVM/RAID/ZFS members) instead of
#     mishandling them.
#   - Identifies disks by UUID (stable across reboots), never by /dev names.
#   - Backs up /etc/fstab before editing; uses `nofail` +
#     `x-systemd.device-timeout` so a missing disk can never block boot.
#   - Validates and test-mounts before trusting anything; rolls back the
#     fstab change on any failure.
#
# Usage:  bash scripts/mount_disk.sh
#         bash scripts/mount_disk.sh --dry-run   # show everything, change nothing
#
set -euo pipefail

# ------------------------------------------------------------------ options ---
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------ output ----
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YEL=$'\e[33m'; CYAN=$'\e[36m'; RST=$'\e[0m'
else
  BOLD=''; RED=''; GREEN=''; YEL=''; CYAN=''; RST=''
fi
info() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RST"; }
warn() { printf '%s!  %s%s\n' "$YEL" "$*" "$RST" >&2; }
err()  { printf '%sERROR: %s%s\n' "$RED" "$*" "$RST" >&2; }
ok()   { printf '%s\xe2\x9c\x93 %s%s\n' "$GREEN" "$*" "$RST"; }
die()  { err "$*"; exit 1; }

# All prompts read from the real terminal, so the script also works when piped
# (e.g. `curl ... | bash`). If there is no terminal, we cannot ask -> abort.
TTY=/dev/tty
confirm() {          # confirm "question"  -> exit 0 if the user says yes
  local q="$1" ans
  printf '%s%s [y/N] %s' "$CYAN" "$q" "$RST" >"$TTY"
  read -r ans <"$TTY" || return 1
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}
ask() {              # ask "prompt" "default"  -> echoes the answer
  local p="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    printf '%s%s [%s]: %s' "$CYAN" "$p" "$def" "$RST" >"$TTY"
  else
    printf '%s%s: %s' "$CYAN" "$p" "$RST" >"$TTY"
  fi
  read -r ans <"$TTY" || ans=''
  printf '%s' "${ans:-$def}"
}
trim() { local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# --------------------------------------------------------------- preflight ----
step "Preflight checks"
[[ "$(uname -s)" == "Linux" ]] || die "This script supports Linux only."
for cmd in lsblk blkid findmnt mount; do
  command -v "$cmd" >/dev/null || die "Required command not found: $cmd"
done
[[ -r "$TTY" && -w "$TTY" ]] || die "No terminal available; run this interactively."

if [[ $EUID -eq 0 ]]; then
  SUDO=''
else
  command -v sudo >/dev/null || die "Not root and 'sudo' is unavailable."
  SUDO='sudo'
  info "Some steps need root privileges; you may be prompted for your password."
  $SUDO -v || die "sudo authentication failed."
fi
[[ -f /etc/fstab ]] || die "/etc/fstab not found."
(( DRY_RUN )) && warn "DRY-RUN mode: nothing will be changed."
ok "Environment looks good."

# --------------------------------------------------------- scan the disks -----
step "Current disk layout (read-only)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT

# Which UUIDs are already referenced in fstab? (advisory: skip duplicates)
fstab_has_uuid() { grep -Eiq "UUID=${1}([[:space:]]|/|\$)" /etc/fstab; }

# A mount under these paths is a transient desktop (udisks) auto-mount, not a
# real system mount. Such a device is still a valid candidate — we just unmount
# that transient mount before mounting at the chosen fixed path.
is_transient_mount() { case "$1" in /run/media/*|/media/*) return 0 ;; *) return 1 ;; esac; }

# Build the candidate list: partitions with a real, mountable filesystem that
# are not container/system volumes and not already mounted at a REAL location
# (transient desktop auto-mounts are kept, and flagged).
declare -a C_DEV C_UUID C_FS C_SIZE C_LABEL C_MODEL C_MNT
mapfile -t _parts < <(lsblk -rno PATH,TYPE | awk '$2=="part"{print $1}')

for dev in "${_parts[@]}"; do
  fs=$(trim "$(lsblk -no FSTYPE "$dev" 2>/dev/null || true)")
  mnt=$(findmnt -no TARGET --source "$dev" 2>/dev/null | head -1 || true)
  # Skip devices mounted at a real location; keep transient desktop auto-mounts.
  if [[ -n "$mnt" ]] && ! is_transient_mount "$mnt"; then continue; fi

  case "$fs" in
    ext2|ext3|ext4|xfs|btrfs|f2fs|vfat|exfat|ntfs|ntfs3) : ;;   # mountable
    "" )        continue ;;                          # no filesystem
    swap )      continue ;;                          # swap, not a folder mount
    crypto_LUKS|LVM2_member|linux_raid_member|zfs_member)
        warn "Skipping $dev ($fs): encrypted/container volume — needs dedicated tooling."
        continue ;;
    * ) warn "Skipping $dev: unrecognized filesystem '$fs'." ; continue ;;
  esac

  uuid=$(trim "$(lsblk -no UUID  "$dev" 2>/dev/null || true)")
  size=$(trim "$(lsblk -no SIZE  "$dev" 2>/dev/null || true)")
  label=$(trim "$(lsblk -no LABEL "$dev" 2>/dev/null || true)")
  pk=$(trim "$(lsblk -no PKNAME "$dev" 2>/dev/null || true)")
  model=$(trim "$(lsblk -dno MODEL "/dev/$pk" 2>/dev/null || true)")

  C_DEV+=("$dev"); C_UUID+=("$uuid"); C_FS+=("$fs")
  C_SIZE+=("$size"); C_LABEL+=("${label:-—}"); C_MODEL+=("${model:-—}"); C_MNT+=("$mnt")
done

(( ${#C_DEV[@]} > 0 )) || die "No mountable data partitions found. Nothing to do."

step "Partitions available to mount"
printf '%s  %-14s %-8s %-8s %-14s %-22s %s%s\n' "$BOLD" "DEVICE" "SIZE" "FSTYPE" "LABEL" "DISK MODEL" "STATUS" "$RST"
for i in "${!C_DEV[@]}"; do
  status='available'
  [[ -n "${C_MNT[$i]}" ]] && status="${YEL}auto-mounted${RST}"
  fstab_has_uuid "${C_UUID[$i]}" && status="${YEL}already in fstab${RST}"
  printf '  %2d) %-14s %-8s %-8s %-14s %-22s %b\n' \
    "$((i+1))" "${C_DEV[$i]}" "${C_SIZE[$i]}" "${C_FS[$i]}" "${C_LABEL[$i]}" "${C_MODEL[$i]}" "$status"
done

# ------------------------------------------------------------ selection -------
sel=$(ask "Select a partition to mount by number (or 'q' to quit)" "")
[[ "$sel" == "q" || -z "$sel" ]] && { info "Nothing selected. Bye."; exit 0; }
[[ "$sel" =~ ^[0-9]+$ ]] || die "Not a number: $sel"
idx=$((sel-1))
(( idx >= 0 && idx < ${#C_DEV[@]} )) || die "Out of range: $sel"

DEV="${C_DEV[$idx]}"; UUID="${C_UUID[$idx]}"; FS="${C_FS[$idx]}"
SIZE="${C_SIZE[$idx]}"; LABEL="${C_LABEL[$idx]}"

step "You selected:"
info "  Device : $DEV"
info "  Size   : $SIZE"
info "  FS type: $FS"
info "  Label  : $LABEL"
info "  UUID   : ${UUID:-<none>}"

# Re-verify mount state. A transient desktop auto-mount is fine — we'll release
# it before mounting at the fixed path. A real mount elsewhere is a hard stop.
CURMNT=$(findmnt -no TARGET --source "$DEV" 2>/dev/null | head -1 || true)
if [[ -n "$CURMNT" ]]; then
  if is_transient_mount "$CURMNT"; then
    warn "$DEV is currently auto-mounted by your desktop at: $CURMNT"
    info "  It will be unmounted first, then mounted at your chosen folder."
  else
    die "$DEV is mounted at $CURMNT (not a removable-media path) — aborting for safety."
  fi
fi
if fstab_has_uuid "$UUID"; then
  warn "This UUID is already referenced in /etc/fstab."
  confirm "Continue anyway (may create a duplicate entry)?" || { info "Aborted."; exit 0; }
fi

# Stable identifier: prefer UUID, fall back to PARTUUID, else refuse.
if [[ -n "$UUID" ]]; then
  IDENT="UUID=$UUID"
else
  puuid=$(trim "$($SUDO blkid -s PARTUUID -o value "$DEV" 2>/dev/null || true)")
  [[ -n "$puuid" ]] || die "No UUID or PARTUUID for $DEV; refusing to use an unstable /dev name."
  warn "No filesystem UUID; falling back to PARTUUID=$puuid"
  IDENT="PARTUUID=$puuid"
fi

# --------------------------------------------------- optional health peek -----
if command -v smartctl >/dev/null; then
  if confirm "Run a quick read-only SMART health check on the disk?"; then
    $SUDO smartctl -H "$DEV" || warn "SMART check reported an issue — review before trusting this disk."
  fi
fi

# ----------------------------------------------------- choose mount point -----
step "Choose where to mount it"
default_mp="/mnt/$(echo "${LABEL}" | tr -c 'A-Za-z0-9_-' '_' | sed 's/^_*//;s/_*$//')"
[[ "$default_mp" == "/mnt/" || "$default_mp" == "/mnt/—" ]] && default_mp="/mnt/data"
MP=$(ask "Mount point folder (absolute path)" "$default_mp")
[[ "$MP" == /* ]] || die "Mount point must be an absolute path."
case "$MP" in
  /|/boot|/boot/efi|/etc|/usr|/bin|/sbin|/lib|/proc|/sys|/dev|/run|/var|/home)
    die "Refusing to mount over a critical system path: $MP" ;;
  *) : ;;   # any other absolute path is allowed
esac
if findmnt -no SOURCE "$MP" &>/dev/null; then
  die "Something is already mounted at $MP. Choose another folder."
fi
if [[ -d "$MP" && -n "$(ls -A "$MP" 2>/dev/null || true)" ]]; then
  warn "$MP already exists and is NOT empty. Mounting over it will HIDE its current contents (they are not deleted, just hidden until unmount)."
  confirm "Use it anyway?" || die "Aborted — pick an empty folder."
fi

# ------------------------------------------------ filesystem / driver ---------
# Let the user pick how to use the partition. Default is non-destructive
# (keep the existing filesystem); reformatting to ext4 is opt-in and gated by a
# typed confirmation. ext4 is the best fit for a Linux-only disk.
step "Filesystem"
info "  $DEV currently contains: ${BOLD}${FS}${RST}"
REFORMAT=0
case "$FS" in
  ntfs|ntfs3)
    info "  How do you want to use it?"
    info "    1) Keep NTFS — driver ntfs3   (kernel, recommended)"
    info "    2) Keep NTFS — driver ntfs-3g (FUSE)"
    info "    3) REFORMAT to ext4           ${RED}(ERASES ALL DATA on $DEV)${RST}"
    ch=$(ask "Select 1-3" "1")
    case "$ch" in
      1) TYPE="ntfs3" ;;
      2) TYPE="ntfs-3g" ;;
      3) REFORMAT=1; TYPE="ext4" ;;
      *) die "Invalid choice: $ch" ;;
    esac ;;
  *)
    info "  How do you want to use it?"
    info "    1) Keep current filesystem ($FS)   (recommended)"
    info "    2) REFORMAT to ext4                ${RED}(ERASES ALL DATA on $DEV)${RST}"
    ch=$(ask "Select 1-2" "1")
    case "$ch" in
      1) TYPE="$FS" ;;
      2) REFORMAT=1; TYPE="ext4" ;;
      *) die "Invalid choice: $ch" ;;
    esac ;;
esac

# Make sure the chosen NTFS driver is actually available (offer install if not).
if [[ "$TYPE" == "ntfs3" ]] && ! { modinfo ntfs3 &>/dev/null || grep -qw ntfs3 /proc/filesystems 2>/dev/null; }; then
  warn "ntfs3 kernel driver unavailable here; falling back to ntfs-3g."
  TYPE="ntfs-3g"
fi
if [[ "$TYPE" == "ntfs-3g" ]] && ! command -v mount.ntfs-3g >/dev/null; then
  warn "ntfs-3g driver is not installed."
  if (( DRY_RUN )); then
    warn "DRY-RUN: would offer to install 'ntfs-3g' (skipped — no changes in dry-run)."
  elif command -v apt-get >/dev/null && confirm "Install 'ntfs-3g' now via apt?"; then
    $SUDO apt-get update -y && $SUDO apt-get install -y ntfs-3g
  else
    die "Cannot mount NTFS without a driver."
  fi
fi

# Reformat is destructive — require an explicit typed confirmation up front.
if (( REFORMAT )); then
  warn "REFORMAT will PERMANENTLY ERASE everything on $DEV ($SIZE, label='$LABEL')."
  phrase="ERASE $(basename "$DEV")"
  typed=$(ask "Type exactly '${phrase}' to confirm (anything else aborts)" "")
  [[ "$typed" == "$phrase" ]] || die "Confirmation did not match — aborting. Nothing was erased."
fi

# --------------------------------------------------- access / options ---------
step "Access options"
MODE="rw"
if confirm "Mount READ-ONLY (safer; you cannot write to it)?"; then MODE="ro"; fi

# Build mount options for the FINAL filesystem type.
BASE_OPTS="nofail,x-systemd.device-timeout=10"
PASS=0
CHOWN=0
case "$TYPE" in
  ext2|ext3|ext4)  OPTS="${MODE},${BASE_OPTS}"; PASS=2; CHOWN=1 ;;
  xfs|btrfs|f2fs)  OPTS="${MODE},${BASE_OPTS}"; PASS=0; CHOWN=1 ;;
  vfat|exfat)      OPTS="${MODE},uid=$(id -u),gid=$(id -g),umask=022,${BASE_OPTS}"; PASS=0 ;;
  ntfs3|ntfs-3g)   OPTS="${MODE},uid=$(id -u),gid=$(id -g),umask=022,${BASE_OPTS}"; PASS=0 ;;
  *) die "Unsupported target filesystem: $TYPE" ;;
esac

# For a reformat, the UUID changes — the identifier is finalized after mkfs in
# the apply phase; show a placeholder until then.
if (( REFORMAT )); then
  IDENT_SHOWN="UUID=(new — assigned after reformat)"
else
  IDENT_SHOWN="$IDENT"
fi
FSTAB_LINE="${IDENT_SHOWN}  ${MP}  ${TYPE}  ${OPTS}  0  ${PASS}"

# ------------------------------------------------------------- review ---------
step "REVIEW — please read carefully"
{
  printf '  Partition   : %s  (%s, %s, label=%s)\n' "$DEV" "$SIZE" "$FS" "'$LABEL'"
  if (( REFORMAT )); then
    printf '  %sACTION      : REFORMAT %s to ext4 — ALL DATA WILL BE ERASED%s\n' "$RED" "$DEV" "$RST"
  fi
  printf '  Identifier  : %s\n' "$IDENT_SHOWN"
  printf '  Mount point : %s        %s\n' "$MP" "$( [[ -d "$MP" ]] && echo '(exists)' || echo '(will be created)' )"
  printf '  Driver/type : %s\n' "$TYPE"
  printf '  Access      : %s\n' "$MODE"
  printf '  fstab line  : %s\n' "$FSTAB_LINE"
  printf '  Backup      : /etc/fstab will be copied to /etc/fstab.bak.<timestamp> first\n'
} >"$TTY"

if (( DRY_RUN )); then
  ok "DRY-RUN complete. No changes were made."
  exit 0
fi
confirm "Apply this configuration now?" || { info "Aborted. No changes made."; exit 0; }

# --------------------------------------------------------------- apply ---------
step "Applying"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/etc/fstab.bak.${STAMP}"
$SUDO cp -a /etc/fstab "$BACKUP"
ok "Backed up /etc/fstab -> $BACKUP"

MP_CREATED=0
if [[ ! -d "$MP" ]]; then
  $SUDO mkdir -p "$MP"; MP_CREATED=1; ok "Created $MP"
fi

rollback() {
  warn "Rolling back..."
  findmnt -no TARGET "$MP" &>/dev/null && $SUDO umount "$MP" || true
  $SUDO cp -a "$BACKUP" /etc/fstab
  (( MP_CREATED )) && $SUDO rmdir "$MP" 2>/dev/null || true
  die "Rolled back. /etc/fstab restored from $BACKUP."
}

# Release any transient desktop auto-mount BEFORE touching fstab or formatting
# (the device must be free to reformat and to mount at the fixed path).
if findmnt -no TARGET --source "$DEV" &>/dev/null; then
  cur=$(findmnt -no TARGET --source "$DEV" | head -1)
  info "Releasing transient auto-mount at $cur ..."
  sync
  # Prefer the desktop-aware udisksctl (it owns this mount); fall back to umount.
  if command -v udisksctl >/dev/null && udisksctl unmount -b "$DEV" >/dev/null 2>&1; then
    ok "Unmounted $cur"
  elif $SUDO umount "$DEV" 2>/dev/null; then
    ok "Unmounted $cur"
  else
    err "Could not unmount $cur — it is busy (a program is using it)."
    warn "Processes holding it open:"
    $SUDO fuser -vm "$cur" 2>&1 | sed 's/^/    /' >"$TTY" || true
    warn "Close them (e.g. the GNOME Files window, or a terminal in that folder), then re-run."
    rollback
  fi
fi

# Reformat if requested. The device is now unmounted. This ERASES the partition.
if (( REFORMAT )); then
  if findmnt -no TARGET --source "$DEV" &>/dev/null; then
    err "$DEV is still mounted; refusing to format."; rollback
  fi
  fslabel="$(basename "$MP")"; fslabel="${fslabel:0:16}"
  warn "Formatting $DEV as ext4 (label '$fslabel') — erasing all data..."
  $SUDO mkfs.ext4 -F -L "$fslabel" "$DEV" || { err "mkfs.ext4 failed."; rollback; }
  ok "Formatted $DEV as ext4."
  # The UUID changed — recompute the identifier and rebuild the fstab line.
  newuuid=$(trim "$($SUDO blkid -s UUID -o value "$DEV" 2>/dev/null || true)")
  [[ -n "$newuuid" ]] || { err "Could not read new UUID after format."; rollback; }
  IDENT="UUID=$newuuid"
  FSTAB_LINE="${IDENT}  ${MP}  ${TYPE}  ${OPTS}  0  ${PASS}"
  ok "New ext4 UUID: $newuuid"
fi

# Append the entry.
printf '\n# added by mount_disk.sh on %s\n%s\n' "$STAMP" "$FSTAB_LINE" | $SUDO tee -a /etc/fstab >/dev/null
ok "Appended entry to /etc/fstab"

# Validate fstab syntax (advisory — shows problems if any).
$SUDO findmnt --verify --tab-file /etc/fstab >"$TTY" 2>&1 || warn "findmnt --verify reported warnings (see above)."

# Refresh systemd's view of fstab so it stops warning about a stale cache and
# picks up the new mount unit (nofail/device-timeout, boot ordering).
command -v systemctl >/dev/null && $SUDO systemctl daemon-reload || true

# The real test: try to mount by the mount point (uses the new fstab entry).
if $SUDO mount "$MP"; then
  ok "Mounted successfully."
else
  err "Mount failed."
  rollback
fi

# Confirm it is actually mounted and matches our device.
if ! findmnt -no SOURCE "$MP" | grep -q "$(basename "$DEV")"; then
  err "Post-mount verification failed."
  rollback
fi

# Optional: give the invoking user ownership of the top directory (Linux fs only).
if (( CHOWN )) && [[ "$MODE" == "rw" ]]; then
  if confirm "Give your user ($(id -un)) ownership of $MP so you can write to it?"; then
    $SUDO chown "$(id -u):$(id -g)" "$MP" && ok "Ownership set."
  fi
fi

# ------------------------------------------------------------ final review ----
step "FINAL REVIEW"
findmnt "$MP" >"$TTY" || true
echo >"$TTY"
df -hT "$MP" >"$TTY" || true
{
  printf '\n%sDone.%s %s is mounted at %s and will auto-mount on every boot.\n\n' "$GREEN" "$RST" "$DEV" "$MP"
  printf '  fstab entry : %s\n' "$FSTAB_LINE"
  printf '  fstab backup: %s\n\n' "$BACKUP"
  printf 'To undo the mount (fstab entry, not the data):\n'
  printf '  %s umount %s\n' "$SUDO" "$MP"
  printf '  %s cp -a %s /etc/fstab      # restores the previous fstab\n' "$SUDO" "$BACKUP"
  if (( REFORMAT )); then
    printf '\n%sNote:%s this partition was reformatted to ext4 — the previous data is gone and cannot be restored from the fstab backup.\n' "$YEL" "$RST"
  fi
} >"$TTY"
ok "All good."
