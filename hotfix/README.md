# Experimental VolksPC desktop compatibility patch

The first Kali image retained the vendor graphics libraries, but used Kali's
standard `xfdesktop`, desktop settings, and logout tool. The original image
contains modified copies of these programs. This patch restores those copies
and their small vendor helpers, together with the matching DMZ-Black cursor theme.
It is a compatibility correction, not a confirmed
fix for touchscreen or trackpad input. Full-screen operation is required by VolksPC.

1. Download `volkspc-input-compat-v1.zip` and extract it into Android's Download
   folder. The resulting folder should be `volkspc-input-compat`.
2. Start the existing Kali desktop so its filesystem is mounted.
3. Open Termux and run these lines separately:

```sh
su -mm
sh /sdcard/Download/volkspc-input-compat/install.sh
```

4. Photograph the printed backup/undo path, then reboot Android and start VolksPC.
5. Test input with the actual VolksPC Desktop app in full-screen mode.

The installer backs up every replaced file under Kali's
`/var/backups/volkspc-input-compat-*`. It prints the exact command to undo the
change. It does not replace the image, change credentials, remove user files,
modify the Android APK/kernel module, or bypass the evaluation limits.

CI checks the restored programs' dynamic dependencies and relocations against
the previously built Kali ARM64 image. Pointer behavior still needs a tablet test.
