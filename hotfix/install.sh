#!/system/bin/sh
set -eu
ROOT=/data/local/tmp/mxwin
HERE=$(dirname "$(readlink -f "$0")")
[ "$(id -u)" = 0 ] || { echo 'Run this from a su -mm shell.'; exit 1; }
[ -f "$ROOT/etc/os-release" ] || { echo 'Start Kali through VolksPC first; its filesystem is not mounted here.'; exit 1; }
KALI_ID=
while IFS='=' read -r key value; do
    [ "$key" = ID ] || continue
    case "$value" in kali|'"kali"'|"'kali'") KALI_ID=kali ;; esac
done < "$ROOT/etc/os-release"
[ "$KALI_ID" = kali ] || { echo 'This patch is intended for the Kali image.'; exit 1; }
FOUND=
for candidate in "$HERE" "$HERE/volkspc-input-compat" "$HERE/volkspc-input-compat-v1/volkspc-input-compat" "$HERE/volkspc-input-compat-v1"; do
    if [ -r "$candidate/payload.tar.gz" ] && [ -r "$candidate/files.txt" ] && [ -r "$candidate/restore.sh" ]; then
        HERE=$candidate
        FOUND=yes
        break
    fi
done
[ "$FOUND" = yes ] || { echo 'Cannot find payload.tar.gz, files.txt and restore.sh. Keep the extracted patch files together in one folder.'; exit 1; }
BACKUP="$ROOT/var/backups/volkspc-input-compat-$(date +%Y%m%d-%H%M%S)-$$"
STAGE="/data/local/tmp/volkspc-input-compat-$$"
mkdir -p "$BACKUP" "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
tar -xzf "$HERE/payload.tar.gz" -C "$STAGE"
cp "$HERE/files.txt" "$BACKUP/files.txt"
: > "$BACKUP/present.txt"
cp "$HERE/restore.sh" "$BACKUP/restore.sh"
chmod 700 "$BACKUP/restore.sh"
# Back up all targets before modifying any installed files.
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$STAGE/$rel" ] || { echo "Missing patch file: $rel"; exit 1; }
    if [ -e "$ROOT/$rel" ] || [ -L "$ROOT/$rel" ]; then
        mkdir -p "$BACKUP/$(dirname "$rel")"
        cp -Pp "$ROOT/$rel" "$BACKUP/$rel"
        echo "$rel" >> "$BACKUP/present.txt"
    fi
done < "$HERE/files.txt"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    target="$ROOT/$rel"
    mkdir -p "$(dirname "$target")"
    cp "$STAGE/$rel" "$target.volkspc-new-$$"
    case "$rel" in usr/bin/*.glade) chmod 644 "$target.volkspc-new-$$" ;; usr/bin/*) chmod 755 "$target.volkspc-new-$$" ;; *) chmod 644 "$target.volkspc-new-$$" ;; esac
    chown 0:0 "$target.volkspc-new-$$"
    mv -f "$target.volkspc-new-$$" "$target"
done < "$HERE/files.txt"
sync
echo 'Compatibility patch installed. Reboot Android, then start VolksPC again.'
echo 'The patch does not change your home directory or password.'
echo "To undo from a su -mm shell while Kali is mounted: sh $BACKUP/restore.sh"
