# Experimental VolksPC desktop compatibility patch

The first Kali image retained the vendor graphics libraries, but used Kali's
standard `xfdesktop`, desktop settings, and logout tool. The original image
contains modified copies of these programs. This patch restores those copies
and their small vendor helpers, together with the matching DMZ-Black cursor theme.
Version 3 also disables xfce4-screensaver, and only that; every other Kali
session service still starts. VolksPC's X server is a kernel module, and the
screensaver's lock grab can leave touch input dead if its lock screen does not
appear. Android already locks the tablet. Installing v3 re-enables anything v2
disabled. This is the leading suspect for the touch failure, not yet confirmed
on a tablet.
Full-screen operation is required by VolksPC.

1. Download `volkspc-input-compat-v3.zip` and extract it into Android's Download
   folder. The resulting folder should be `volkspc-input-compat`.
2. Start the existing Kali desktop so its filesystem is mounted.
3. Open Termux and run these lines separately:

```sh
su -mm
sh /sdcard/Download/volkspc-input-compat/install.sh
```

4. Photograph the printed backup/undo path, then reboot Android and start VolksPC.
5. Test input with the actual VolksPC Desktop app in full-screen mode.
6. If touch still fails, leave the desktop running, open Termux and run
   `su -mm` then `sh /sdcard/Download/volkspc-input-compat/diagnose.sh`.
   Share the resulting `/sdcard/Download/volkspc-diagnose.txt`.

The installer backs up every replaced file under Kali's
`/var/backups/volkspc-input-compat-*`. It prints the exact command to undo the
change. Autostart overrides are written to `~/.config/autostart` and removed again by
the undo command. It does not replace the image, change credentials, remove user files,
modify the Android APK/kernel module, or bypass the evaluation limits.

CI checks the restored programs' dynamic dependencies and relocations against
the previously built Kali ARM64 image. Pointer behavior still needs a tablet test.
