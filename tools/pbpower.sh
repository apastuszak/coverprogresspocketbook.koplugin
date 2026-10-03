#!/bin/sh
# Maps PocketBook auto-lock and power-off settings to their stored values.
# Run it from KOReader's file browser (long-press > Execute shell script).
#
# Use: run it once, change ONE setting in the PocketBook menu (for example
# Auto-lock), run it again, and so on. Each run:
#   - saves a copy of the settings folder on the device, in /mnt/ext1/pbpower/
#     (this copy stays on the device; it is not meant to be shared)
#   - appends to /mnt/ext1/pbpower.txt only the lines that changed since the
#     previous run, plus the current lines whose names mention lock, sleep,
#     power, off, standby or timeout
# It never changes a setting. Delete /mnt/ext1/pbpower/ and pbpower.txt when
# done. The paths can be overridden for testing with the variables below.

CONFIG_DIR=${CONFIG_DIR:-/mnt/ext1/system/config}
SNAP_DIR=${SNAP_DIR:-/mnt/ext1/pbpower}
OUT=${OUT:-/mnt/ext1/pbpower.txt}

mkdir -p "$SNAP_DIR" || exit 1

# Number this run after the highest existing run.
last=0
for d in "$SNAP_DIR"/run.*; do
    [ -d "$d" ] || continue
    n=${d##*.}
    [ "$n" -gt "$last" ] 2>/dev/null && last=$n
done
run=$((last + 1))
new="$SNAP_DIR/run.$run"
old="$SNAP_DIR/run.$last"

# Copy text-sized files from the settings folder (not over 1 MB).
mkdir -p "$new"
( cd "$CONFIG_DIR" 2>/dev/null && find . -type f 2>/dev/null ) | while read -r rel; do
    size=$(ls -l "$CONFIG_DIR/$rel" 2>/dev/null | awk '{print $5}')
    [ -n "$size" ] && [ "$size" -le 1048576 ] 2>/dev/null || continue
    mkdir -p "$new/$(dirname "$rel")"
    cp "$CONFIG_DIR/$rel" "$new/$rel" 2>/dev/null
done

{
    echo "==================== run $run  $(date)"

    if [ "$last" -eq 0 ]; then
        echo "(first run: nothing to compare yet)"
    else
        echo "== changes since run $last"
        ( cd "$new" && find . -type f ) | sort | while read -r rel; do
            if [ ! -f "$old/$rel" ]; then
                echo "-- new file: $rel"
            elif ! cmp -s "$old/$rel" "$new/$rel"; then
                echo "-- $rel"
                grep -F -x -v -f "$old/$rel" "$new/$rel" 2>/dev/null | sed 's/^/   now: /'
                grep -F -x -v -f "$new/$rel" "$old/$rel" 2>/dev/null | sed 's/^/   was: /'
            fi
        done
        ( cd "$old" && find . -type f ) | sort | while read -r rel; do
            [ -f "$new/$rel" ] || echo "-- removed file: $rel"
        done
    fi

    echo "== current lock/sleep/power lines in global.cfg"
    grep -i -e lock -e sleep -e power -e off -e standby -e timeout \
        "$new/global.cfg" 2>/dev/null
} >> "$OUT" 2>&1
