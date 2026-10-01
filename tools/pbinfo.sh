#!/bin/sh
# Read-only diagnostics for the PocketBook lock-screen investigation.
# Run it from KOReader's file browser (long-press > Execute shell script).
# It changes nothing; it writes what it finds to /mnt/ext1/pbinfo.txt.

OUT=/mnt/ext1/pbinfo.txt
{
    echo "== date"; date
    echo "== ps"; ps w 2>&1 || ps 2>&1
    echo "== /ebrmain/bin"; ls -la /ebrmain/bin 2>&1
    echo "== /ebrmain/themes"; ls -la /ebrmain/themes 2>&1
    echo "== /mnt/ext1/system/resources/Line"; ls -la /mnt/ext1/system/resources/Line 2>&1
    echo "== mount"; mount 2>&1
    echo "== koreader SSH dir"; ls -la /mnt/ext1/applications/koreader/settings/SSH 2>&1
} > "$OUT" 2>&1
