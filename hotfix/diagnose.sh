#!/system/bin/sh
# Collects input diagnostics while the Kali desktop is running.
# Run from Termux:  su -mm   then   sh /sdcard/Download/volkspc-input-compat/diagnose.sh
ROOT=/data/local/tmp/mxwin
OUT=/sdcard/Download/volkspc-diagnose.txt
[ "$(id -u)" = 0 ] || { echo 'Run this from a su -mm shell.'; exit 1; }
{
    echo "== date"; date
    echo "== android kernel"; uname -a
    echo "== x11dev"; ls -l /dev/x11dev "$ROOT/dev/x11dev" 2>&1
    echo "== kernel modules"; grep -i -E 'x11|volks|microx' /proc/modules 2>&1
    echo "== x11info"; chroot "$ROOT" /usr/bin/x11info 2>&1
    echo "== processes"; ps -A -o USER,PID,ARGS 2>/dev/null || ps -A
    echo "== user autostart overrides"; ls -l "$ROOT/home/desktop/.config/autostart" 2>&1
    echo "== waylandx11.log"; tail -n 60 "$ROOT/tmp/waylandx11.log" 2>&1
    echo "== session snapshot"; cat "$ROOT/tmp/volkspc-session.txt" 2>&1
    echo "== xsession errors"; tail -n 80 "$ROOT/home/desktop/.xsession-errors" 2>&1
    echo "== kernel log (x11/volkspc)"; dmesg 2>/dev/null | grep -i -E 'x11|volks|microx' | tail -n 60
} > "$OUT" 2>&1
echo "Diagnostics written to $OUT"
