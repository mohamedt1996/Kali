#!/system/bin/sh
set -eu
ROOT=/data/local/tmp/mxwin
HERE=$(dirname "$(readlink -f "$0")")
[ "$(id -u)" = 0 ] || { echo 'Run this from a su -mm shell.'; exit 1; }
[ -f "$ROOT/etc/os-release" ] || { echo 'Start Kali first so its filesystem is mounted.'; exit 1; }
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if grep -Fxq "$rel" "$HERE/present.txt"; then
        cp -Pp "$HERE/$rel" "$ROOT/$rel.volkspc-restore-$$"
        mv -f "$ROOT/$rel.volkspc-restore-$$" "$ROOT/$rel"
    else
        rm -f "$ROOT/$rel"
    fi
done < "$HERE/files.txt"
sync
echo 'Original files restored. Reboot Android, then start VolksPC again.'
