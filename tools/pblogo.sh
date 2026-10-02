#!/bin/sh
# Read-only probe for the PocketBook power-off screen.
# Run it from KOReader's file browser (long-press > Execute shell script).
# It changes nothing; it writes what it finds to /mnt/ext1/pblogo.txt.
#
# 1. Text inside power_off_logo.app that mentions logos, covers or BMPs:
#    the paths and setting names it uses.
# 2. The logo-related settings in the firmware's configuration.
# 3. What is in the logo folders, with sizes and dates.
# 4. Image files, and any file over 1 MB, in the writable system areas and in
#    RAM-backed /var and /tmp, to find where the firmware keeps its copy of a
#    custom power-off image.

OUT=/mnt/ext1/pblogo.txt
{
    echo "== date"; date

    echo "== power_off_logo.app strings"
    for f in /ebrmain/cramfs/bin/power_off_logo.app /ebrmain/bin/power_off_logo.app; do
        [ -f "$f" ] || continue
        echo "-- $f"
        # -a may not exist in the device's busybox grep; fall back without it.
        { grep -a -o '[[:print:]]*[Ll]ogo[[:print:]]*' "$f" 2>/dev/null ||
          grep -o '[[:print:]]*[Ll]ogo[[:print:]]*' "$f" 2>/dev/null; } | sort -u | head -n 80
        { grep -a -o '[[:print:]]*\(cover\|\.bmp\|offlogo\)[[:print:]]*' "$f" 2>/dev/null ||
          grep -o '[[:print:]]*\(cover\|\.bmp\|offlogo\)[[:print:]]*' "$f" 2>/dev/null; } | sort -u | head -n 40
        break
    done

    echo "== logo settings"
    for cfg in /mnt/ext1/system/config/global.cfg /mnt/secure/global.cfg /ebrmain/config/global.cfg; do
        [ -f "$cfg" ] || continue
        echo "-- $cfg"
        grep -i -e logo -e cover -e poweroff -e power_off "$cfg" 2>/dev/null
    done

    echo "== /mnt/ext1/system/logo"
    ls -la /mnt/ext1/system/logo 2>&1
    echo "== /mnt/ext1/system/logo/offlogo"
    ls -la /mnt/ext1/system/logo/offlogo 2>&1
    echo "== /ebrmain/logo (built-in logos)"
    ls -la /ebrmain/logo 2>&1 | head -n 30

    # Where the firmware may keep its own copy of the chosen power-off image.
    # It is loaded at boot, so it may be in RAM-backed /var or /tmp as well as
    # on storage. Lists files only (never their contents): image-like names,
    # and any file over 1 MB. "<-- same size as the lock image" marks files
    # exactly the size of the Line lock image, which a straight copy would be.
    LINE=/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp
    LINE_SIZE=$(ls -l "$LINE" 2>/dev/null | awk '{print $5}')
    echo "== candidate copies (Line image is ${LINE_SIZE:-?} bytes)"
    for dir in /mnt/ext1/system /mnt/secure /var /tmp; do
        find "$dir" -type f 2>/dev/null | while read -r f; do
            size=$(ls -l "$f" 2>/dev/null | awk '{print $5}')
            [ -n "$size" ] || continue
            case "${f##*/}" in
                *.bmp|*.BMP|*.png|*.jpg|*.raw|*logo*|*Logo*|*cover*) show=1 ;;
                *) show=0 ;;
            esac
            [ "$size" -gt 1000000 ] 2>/dev/null && show=1
            [ "$show" = 1 ] || continue
            mark=""
            [ "$size" = "$LINE_SIZE" ] && mark="  <-- same size as the lock image"
            echo "$(ls -la "$f" 2>/dev/null)$mark"
        done
    done
} > "$OUT" 2>&1
