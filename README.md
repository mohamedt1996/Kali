# Kali ARM64 image for VolksPC — experimental

Build a fresh Kali userspace using the original VolksPC image's Android graphics
integration. **A successful CI run does not establish that the desktop works on
a tablet.** Android kernel-module, display, input and audio tests require the device.

The GitHub Actions workflow fetches the original filesystem from the supplied
VolksPC MEGA link, checks its image byte count, exports the official Kali ARM64
container, installs Kali core and XFCE, integrates the vendor libraries, and
packages `linuxfs.img` plus `linuxfs.size` as `volkspcimgarm64.zip`.

Source downloads are hashed for traceability. The Kali container digest is recorded
for every run; the rolling tag and apt package versions can change between builds.
The image ZIP is retained as an Actions artifact for seven days, together with a
randomly generated desktop/sudo password. No root password login is enabled.

## Build checks

- Native ARM64 userspace and UID 1000 for the `desktop` login.
- Kali core/XFCE packages, nmap and tcpdump.
- Dynamic dependencies and relocations for waylandx11, xfce4-session and xfdesktop.
- ext4 consistency using `e2fsck -fn`.
- ZIP integrity, expected filenames and exact uncompressed image size.

The builder stops on failed checks. More vendor changes may be required: the
original image holds modified desktop/audio packages in addition to the graphics
libraries inspected so far. This is an experimental integration, not an official
Kali or VolksPC release.

## Test on the tablet

1. Determine Android's actual kernel with `uname -r` and install the matching
   official VolksPC APK. The supplied Android16-6.12 APK will not become compatible
   with a 6.1 kernel by changing the Linux image.
2. Confirm the original VolksPC Debian image works first.
3. Preserve existing Linux user data and the original ZIP.
4. Download the successful run's `volkspc-kali-arm64-experimental` artifact,
   extract its outer Actions ZIP, and verify the inner image ZIP checksum.
5. Follow VolksPC's supported installer workflow for `volkspcimgarm64.zip`.
   The generated password is in `credentials.txt` in the artifact.

The repository contains build code and inspection metadata. Proprietary binaries
are fetched from the user's source image at build time, not committed to git.
The workflow preserves the official APK and evaluation behavior, and does not
flash Android, replace its kernel, or enable unsupported Wi-Fi capabilities.

## Local build

Use Linux with root/loop-mount support and Python 3.12+. On x86_64, also configure
ARM64 binfmt/QEMU. Allow approximately 30 GB of free storage and access to Kali's
official package servers. Supply a verified official Kali ARM64 rootfs tar archive
with its repository keyring, or export the official Kali ARM64 container as in CI.

```sh
sudo bash scripts/build-volkspc-kali.sh \
  /path/to/original/linuxfs.img \
  /path/to/kali-arm64.tar \
  /path/to/new-output-directory
```

Default filesystem size is 12 GiB. The original image is mounted read-only.
The retained `.build-*` directory contains diagnostic files after success or
failure. Do not delete a build tree while any filesystems remain mounted.
