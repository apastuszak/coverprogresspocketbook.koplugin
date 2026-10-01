#!/bin/sh
# Experiment: ask PocketBook's taskmgr.app to reload its settings, in the hope
# that it also reloads the cached lock-screen image (taskmgr_lock_background).
# Run it from KOReader's file browser (long-press > Execute shell script).
#
# What it does:
#   - finds taskmgr.app's process ID and asks iv2sh for its task ID (read-only)
#   - sends event 154 (EVT_CONFIGCHANGED, "settings changed") with parameter 0
#     to taskmgr.app, by process ID and, if different, by task ID
# It writes nothing except /mnt/ext1/pbtest.txt. Each iv2sh call is stopped
# after 5 seconds so nothing can hang. If the device misbehaves, restart it.

OUT=/mnt/ext1/pbtest.txt
IV2SH=/ebrmain/bin/iv2sh
EVT_CONFIGCHANGED=154

# Runs iv2sh with the given arguments, stopping it after 5 seconds.
run_iv2sh() {
    "$IV2SH" "$@" > /tmp/pbtest_iv2sh.txt 2>&1 &
    pid=$!
    i=0
    while [ $i -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        i=$((i + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "(stopped after 5 s)"
    fi
    grep -i -e return -e error -e "not found" -e usage /tmp/pbtest_iv2sh.txt
}

{
    echo "== date"; date

    echo "== taskmgr.app process"
    ps | grep '[t]askmgr.app'
    TM_PID=$(ps | grep '[t]askmgr\.app' | grep -v visualizer | awk '{print $1}' | head -n 1)
    echo "process ID: $TM_PID"

    echo "== task ID lookup"
    LOOKUP=$(run_iv2sh FindTaskByAppName taskmgr.app)
    echo "$LOOKUP"
    TM_TASK=$(echo "$LOOKUP" | sed -n 's/.*Return[^0-9-]*\(-\{0,1\}[0-9][0-9]*\).*/\1/p' | head -n 1)
    echo "task ID: $TM_TASK"

    if [ -n "$TM_PID" ]; then
        echo "== SendEventTo process ID $TM_PID"
        run_iv2sh SendEventTo "$TM_PID" "$EVT_CONFIGCHANGED" 0
    fi
    if [ -n "$TM_TASK" ] && [ "$TM_TASK" != "$TM_PID" ] && [ "$TM_TASK" -gt 0 ] 2>/dev/null; then
        echo "== SendEventTo task ID $TM_TASK"
        run_iv2sh SendEventTo "$TM_TASK" "$EVT_CONFIGCHANGED" 0
    fi
    echo "== done"
} > "$OUT" 2>&1
