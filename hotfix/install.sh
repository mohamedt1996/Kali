#!/system/bin/sh
set -eu
ROOT=/data/local/tmp/mxwin
HERE=$(dirname "$(readlink -f "$0")")
[ "$(id -u)" = 0 ] || { echo 'Run this from a su -mm shell.'; exit 1; }
[ -f "$ROOT/etc/os-release" ] || { echo 'Start Kali through VolksPC first; its filesystem is not mounted here.'; exit 1; }
grep -q 'ID=kali\|ID="kali"' "$ROOT/etc/os-release" || { echo 'This patch is intended for the Kali image.'; exit 1; }
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
    cp "$STAGE/$rel" "$target.volkspc-new-$$"
    case "$rel" in *.glade) chmod 644 "$target.volkspc-new-$$" ;; *) chmod 755 "$target.volkspc-new-$$" ;; esac
    chown 0:0 "$target.volkspc-new-$$"
    mv -f "$target.volkspc-new-$$" "$target"
done < "$HERE/files.txt"
sync
echo 'Compatibility patch installed. Reboot Android, then start VolksPC again.'
echo 'The patch does not change your home directory or password.'
echo "To undo from a su -mm shell while Kali is mounted: sh $BACKUP/restore.sh"
