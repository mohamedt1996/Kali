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
for candidate in "$HERE" "$HERE/volkspc-input-compat" "$HERE/volkspc-input-compat-v2/volkspc-input-compat" "$HERE/volkspc-input-compat-v2" "$HERE/volkspc-input-compat-v1/volkspc-input-compat" "$HERE/volkspc-input-compat-v1"; do
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
# Start only the session services the original VolksPC image starts. Kali's
# extras (xfce4-screensaver, xfce4-power-manager, xcape, xiccd, ...) are not
# needed on VolksPC, and a screensaver pointer grab leaves touch input dead.
KEEP='at-spi-dbus-bus.desktop pulseaudio.desktop xdg-user-dirs.desktop xdg-user-dirs-kde.desktop xfce4-notifyd.desktop xfsettingsd.desktop'
AUTOSTART="$ROOT/home/desktop/.config/autostart"
mkdir -p "$AUTOSTART"
chown 1000:1000 "$ROOT/home/desktop/.config" "$AUTOSTART"
: > "$BACKUP/autostart-created.txt"
for entry in "$ROOT"/etc/xdg/autostart/*.desktop; do
    [ -f "$entry" ] || continue
    name=${entry##*/}
    case " $KEEP " in *" $name "*) continue ;; esac
    [ -e "$AUTOSTART/$name" ] && continue
    printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\nX-VolksPC-Disabled=true\n' "${name%.desktop}" > "$AUTOSTART/$name"
    chown 1000:1000 "$AUTOSTART/$name"
    chmod 644 "$AUTOSTART/$name"
    echo "$name" >> "$BACKUP/autostart-created.txt"
    echo "Disabled Kali-only autostart: $name"
done
sync
echo 'Compatibility patch installed. Reboot Android, then start VolksPC again.'
echo 'Your files and password are unchanged; Kali-only autostart entries were disabled in ~/.config/autostart.'
echo "To undo from a su -mm shell while Kali is mounted: sh $BACKUP/restore.sh"
