#!/usr/bin/env bash
# Experimental local builder. Does not flash Android or alter the source image.
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || die 'Run with sudo on a Linux machine (WSL2 can be used).'
[[ $# == 3 ]] || die "Usage: $0 ORIGINAL-linuxfs.img VERIFIED-kali-arm64-rootfs.tar.xz NEW-output-directory"
for cmd in python3 mount umount mountpoint chroot mkfs.ext4 truncate zip readelf realpath cp; do
    command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
SOURCE=$(realpath "$1")
ROOTFS=$(realpath "$2")
[[ -f $SOURCE && -f $ROOTFS ]] || die 'Both input files must exist.'
[[ ! -e $3 ]] || die 'Choose an output directory that does not already exist.'
mkdir -p "$3"
OUT=$(realpath "$3")
BUILD=$(mktemp -d "$OUT/.build-XXXXXX")
SRC="$BUILD/source"
ROOT="$BUILD/kali"
mkdir "$SRC" "$ROOT"
cleanup() {
    local result=$?
    trap - EXIT
    for path in "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/proc" "$SRC"; do
        if mountpoint -q "$path"; then umount "$path" || result=1; fi
    done
    # Retain the build tree for diagnosis; never remove a potentially mounted tree.
    printf 'Build workspace retained at: %s\n' "$BUILD" >&2
    exit "$result"
}
trap cleanup EXIT
mount -t ext4 -o loop,ro,noload "$SOURCE" "$SRC"
[[ -f $SRC/etc/rc.chroot && -d $SRC/home/desktop ]] || die 'Source does not look like the inspected VolksPC image.'

# Python 3.12+ data filtering rejects escaping archive entries and unsafe links.
# Both a plain rootfs and a NetHunter-style kali-arm64/ wrapper are accepted.
python3 - "$ROOTFS" "$ROOT" <<'PY'
import copy, posixpath, sys, tarfile
if not hasattr(tarfile, 'data_filter'):
    raise SystemExit('Python with tarfile.data_filter support is required (Python 3.12+ recommended).')
with tarfile.open(sys.argv[1], 'r:*') as archive:
    def rootfs_filter(member, destination):
        # Device nodes come from the host bind mount during setup, and from
        # VolksPC's Android startup script at runtime.
        parts = member.name.removeprefix('./').split('/')
        if parts[0] == 'kali-arm64':
            parts = parts[1:]
        if parts and parts[0] == 'dev' and len(parts) > 1:
            return None
        # A Linux rootfs legitimately has absolute symlinks (e.g. /etc/mtab).
        # Rebase those inside the extraction root before applying data_filter.
        if member.issym() and member.linkname.startswith('/'):
            member = copy.copy(member)
            wrapper = 'kali-arm64/' if member.name.removeprefix('./').startswith('kali-arm64/') else ''
            target = wrapper + member.linkname.lstrip('/')
            member.linkname = posixpath.relpath(target, posixpath.dirname(member.name))
        return tarfile.data_filter(member, destination)
    archive.extractall(sys.argv[2], filter=rootfs_filter)
PY
if [[ ! -f $ROOT/etc/os-release && -d $ROOT/kali-arm64/etc ]]; then
    mv "$ROOT" "$BUILD/wrapped"
    mv "$BUILD/wrapped/kali-arm64" "$ROOT"
fi
[[ -f $ROOT/etc/os-release ]] || die 'Cannot locate rootfs /etc/os-release.'
grep -Eq '^ID=("kali"|kali)$' "$ROOT/etc/os-release" || die 'Input must be a Kali root filesystem.'
readelf -h "$ROOT/usr/bin/dpkg" | grep -q AArch64 || die 'Root filesystem must be ARM64.'
chroot "$ROOT" /bin/true || die 'ARM64 execution unavailable. Configure qemu-user-static/binfmt on x86_64 first.'
[[ $(chroot "$ROOT" dpkg --print-architecture) == arm64 ]] || die 'Wrong rootfs architecture.'

mkdir -p "$ROOT"/{dev/pts,proc,tmp,sys}
chmod 1777 "$ROOT/tmp"
mount --bind /dev "$ROOT/dev"
mount --make-private "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
rm -f "$ROOT/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
if [[ -e $ROOT/usr/sbin/policy-rc.d || -L $ROOT/usr/sbin/policy-rc.d ]]; then
    mv "$ROOT/usr/sbin/policy-rc.d" "$BUILD/original-policy-rc.d"
fi
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
chmod 755 "$ROOT/usr/sbin/policy-rc.d"
# Keep the rootfs's official Kali repositories and keyring. Never mix in Debian repositories.
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -ec '
    apt-get update
    apt-get install -y kali-linux-core kali-desktop-xfce dbus dbus-x11 pulseaudio \
        util-linux sudo locales tzdata x11-xserver-utils fonts-dejavu-core dmz-cursor-theme nmap tcpdump
    apt-get clean
    if ! id desktop >/dev/null 2>&1; then
        if getent passwd 1000 >/dev/null; then
            echo "UID 1000 is already occupied; use a rootfs without a pre-created user." >&2
            exit 1
        fi
        useradd -m -u 1000 -s /bin/bash -G sudo,audio,video desktop
    fi
    test "$(id -u desktop)" = 1000
    usermod -s /bin/bash -a -G sudo,audio,video desktop
    passwd -l root
'
rm "$ROOT/usr/sbin/policy-rc.d"
if [[ -e $BUILD/original-policy-rc.d || -L $BUILD/original-policy-rc.d ]]; then
    mv "$BUILD/original-policy-rc.d" "$ROOT/usr/sbin/policy-rc.d"
fi
# The host resolver is only for package installation. It may point to a local
# systemd stub unavailable on Android, so restore the vendor's runtime DNS.
if [[ -f $SRC/etc/resolv.conf ]]; then
    cp -L "$SRC/etc/resolv.conf" "$ROOT/etc/resolv.conf"
else
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$ROOT/etc/resolv.conf"
fi
if [[ -d $SRC/etc/pulse ]]; then
    # VolksPC routes desktop audio to the Android helper through a FIFO.
    # A stock Kali PulseAudio configuration would not retain that routing.
    cp -a "$SRC/etc/pulse/." "$ROOT/etc/pulse/"
fi

# Copy the user's own vendor files into a private directory, preserving symlinks.
# The package records show these libraries were held in the source installation.
mkdir -p "$ROOT/opt/volkspc/lib"
python3 - "$SRC" "$ROOT" <<'PY'
from pathlib import Path
import shutil, sys
src, dst = map(Path, sys.argv[1:])
lib = src/'usr/lib/aarch64-linux-gnu'
prefixes = ['libX11.so.', 'libX11-xcb.so.', 'libxcb.so.', 'libxcb-shm.so.',
            'libXext.so.', 'libXrender.so.', 'libXcursor.so.', 'libcairo.so.',
            'libgdk-3.so.', 'libgtk-3.so.', 'libgtk-4.so.',
            'libstartup-notification-1.so.']
for prefix in prefixes:
    files = list(lib.glob(prefix+'*'))
    if not files or not any(p.is_file() and p.stat().st_size for p in files):
        raise SystemExit('Missing vendor library: '+prefix)
    for p in files:
        shutil.copy2(p, dst/'opt/volkspc/lib'/p.name, follow_symlinks=False)
for name in ['waylandx11', 'changetz', 'changelocale', 'xfdesktop', 'xfdesktop-settings',
             'xfce4-session-logout', 'volkspcpower', 'logout.glade', 'androidhome',
             'androidview', 'x11info', 'x11setaccel', 'setcursor']:
    p = next((p for p in [src/'usr/bin'/name, src/'bin'/name] if p.is_file()), None)
    if p is None:
        raise SystemExit('Missing vendor helper: '+name)
    shutil.copy2(p, dst/'usr/bin'/name)
    (dst/'usr/bin'/name).chmod(0o644 if name.endswith('.glade') else 0o755)
if (src/'usr/fonts').is_dir():
    shutil.copytree(src/'usr/fonts', dst/'usr/fonts', symlinks=True, dirs_exist_ok=True)
PY
chroot "$ROOT" apt-mark hold xfdesktop4 xfce4-session

# Preserve the source login configuration, but use a minimal desktop startup.
cp -a "$SRC/home/desktop/." "$ROOT/home/desktop/"
cat > "$ROOT/home/desktop/.bash_profile" <<'PROFILE'
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export DISPLAY=:0.0 MICROXWINDPI=96
export XDG_RUNTIME_DIR=/tmp/runtime-desktop
export LD_LIBRARY_PATH=/opt/volkspc/lib
export GDK3_BACKEND=x11 GSK_RENDERER=cairo
export QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
[ ! -f "$HOME/myxmodmap" ] || xmodmap "$HOME/myxmodmap"
pulseaudio --start
/bin/waylandx11 > /tmp/waylandx11.log 2>&1 &
wayland_pid=$!
/usr/bin/startxfce4
kill "$wayland_pid" 2>/dev/null || true
pulseaudio -k
logout
PROFILE
cat > "$ROOT/etc/rc.chroot" <<'STARTUP'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export DISPLAY=:0.0
chmod 1777 /dev/shm
ln -sf /proc/mounts /etc/mtab
/etc/init.d/dbus start
if [ -c /dev/ttynull ]; then
    /sbin/getty -a desktop ttynull
else
    /sbin/getty -a desktop console
fi
/etc/init.d/dbus stop
/bin/sync
mount -o remount,ro /
STARTUP
chmod 755 "$ROOT/etc/rc.chroot"
chroot "$ROOT" chown -R desktop:desktop /home/desktop
PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(15))')
printf 'desktop:%s\n' "$PASSWORD" | chroot "$ROOT" chpasswd
(umask 077; printf 'User: desktop\nPassword: %s\nRoot password login is locked; use sudo.\n' "$PASSWORD" > "$OUT/credentials.txt")
unset PASSWORD

# Dependency resolution checks. These cannot test /dev/x11dev without the tablet.
for target in /usr/bin/waylandx11 /usr/bin/xfce4-session /usr/bin/xfdesktop; do
    chroot "$ROOT" /usr/bin/env LD_LIBRARY_PATH=/opt/volkspc/lib \
        /lib/ld-linux-aarch64.so.1 --list "$target"
done
chroot "$ROOT" /usr/bin/env LD_LIBRARY_PATH=/opt/volkspc/lib \
    /bin/bash -ec '
        for program in /usr/bin/waylandx11 /usr/bin/xfce4-session /usr/bin/xfdesktop; do
            result=$(ldd -r "$program" 2>&1)
            printf "%s\n%s\n" "$program" "$result"
            if printf "%s\n" "$result" | grep -E "not found|undefined symbol"; then
                exit 1
            fi
        done
    '
chroot "$ROOT" /bin/bash -ec '
    test "$(dpkg --print-architecture)" = arm64
    test "$(id -u desktop)" = 1000
    test -x /etc/rc.chroot
    dpkg-query -W kali-linux-core kali-desktop-xfce
    nmap --version
    tcpdump --version
    dpkg --audit
'
umount "$ROOT/dev/pts"
umount "$ROOT/dev"
umount "$ROOT/proc"
umount "$SRC"

# Restrict features for compatibility with Android's ext4 implementation.
truncate -s "${SIZE_GIB:-12}G" "$OUT/linuxfs.img"
mkfs.ext4 -F -L kali-volkspc -O '^64bit,^metadata_csum,^orphan_file' \
    -d "$ROOT" "$OUT/linuxfs.img"
stat -c '%s' "$OUT/linuxfs.img" > "$OUT/linuxfs.size"
e2fsck -fn "$OUT/linuxfs.img"
(cd "$OUT"; zip -6 volkspcimgarm64.zip linuxfs.img linuxfs.size)
unzip -t "$OUT/volkspcimgarm64.zip"
printf 'Experimental image: %s/volkspcimgarm64.zip\nCredentials: %s/credentials.txt\n' "$OUT" "$OUT"
