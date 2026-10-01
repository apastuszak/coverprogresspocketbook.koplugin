#!/bin/sh
# Read-only probe for the PocketBook lock-screen investigation.
# Run it from KOReader's file browser (long-press > Execute shell script).
# It changes nothing; it writes what it finds to /mnt/ext1/pbprobe.txt.
#
# 1. Which firmware files mention the lock image, to see which program draws it.
# 2. The task ID iv2sh reports for each candidate program (FindTaskByAppName
#    only looks the ID up), needed before any SendEventTo test.

OUT=/mnt/ext1/pbprobe.txt
{
    echo "== date"; date

    echo "== files mentioning taskmgr_lock_background"
    for f in /ebrmain/cramfs/bin/* /ebrmain/bin/sreader/* /ebrmain/bin/root/* \
             /ebrmain/bin/reader/* /ebrmain/lib/* /ebrmain/cramfs/lib/*; do
        [ -f "$f" ] || continue
        if grep -q taskmgr_lock_background "$f" 2>/dev/null; then
            echo "$f"
        fi
    done

    echo "== task IDs"
    for app in taskmgr_visualizer.app taskmgr.app bookshelf.app eink-reader.app \
               eink-cache-reader.app reader_controller.app koreader.app; do
        echo "-- $app"
        /ebrmain/bin/iv2sh FindTaskByAppName "$app" 2>&1 | grep -i -e return -e error -e "not found"
    done
} > "$OUT" 2>&1
