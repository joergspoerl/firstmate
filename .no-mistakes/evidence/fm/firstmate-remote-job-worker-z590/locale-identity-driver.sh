#!/bin/bash
# Live driver for d2fce3a2: locale-invariance of remote-job process identity.
# Reproduces the z590 incident mechanism (de_DE-recorded owner declared dead by a
# C-locale checker) with the pre-fix lib, and proves the pinned lib fixes it.
# The lock owner record lives at $FM_REMOTE_JOB_STATE/worker.lock/{pid,start,command}.
set -u
ROOT=/Users/jorgsporl/.no-mistakes/worktrees/a915877290ea/01M52EYBZM4S75ZQ6CAQN1J1M6

LAB_RAW=$(mktemp -d "${TMPDIR:-/tmp}/fm-rj-lab.XXXXXX") || exit 1
[ -n "$LAB_RAW" ] || exit 1
LAB=$(CDPATH='' cd -- "$LAB_RAW" && pwd -P) || exit 1
case "$LAB" in
  /private/var/folders/*|/var/folders/*|/tmp/*) ;;
  *) echo "unexpected lab path: $LAB" >&2; exit 1 ;;
esac
mkdir -p "$LAB/account"
ACCOUNT="$LAB/account"

# Extract the BASE (pre-fix) lib to reproduce the incident mechanism.
git -C "$ROOT" show 5f2b81bc:bin/fm-remote-job-lib.sh > "$LAB/fm-remote-job-lib.base.sh"

# A real, live, disposable process that stands in for the remote worker.
sleep 600 & LIVE_PID=$!
cleanup() {
  kill "$LIVE_PID" 2>/dev/null || true
  case "$LAB" in
    /private/var/folders/*|/var/folders/*|/tmp/*) rm -rf -- "$LAB" ;;
  esac
}
trap cleanup EXIT

# record_worker_lock <lib> <locale> <state-root> <account> <pid>
record_worker_lock() {
  env LC_ALL="$2" FM_REMOTE_JOB_STATE_ROOT="$3" bash -c '
    . "$1"; shift
    fm_remote_job_prepare_state "$1" || { echo "prepare_state rc=$? err=${FM_REMOTE_JOB_ERROR:-}" >&2; exit 9; }
    lock=$(fm_remote_job_worker_lock_path)
    mkdir -p "$lock"
    printf "%s\n" "$2" > "$lock/pid"
    fm_remote_job_process_start "$2" > "$lock/start" || exit 9
    fm_remote_job_process_command "$2" > "$lock/command" || exit 9
    printf "lock record at %s\n" "$lock" >&2
  ' _ "$1" "$4" "$5"
}

# check_worker_lock <lib> <locale> <state-root> <account>
check_worker_lock() {
  env LC_ALL="$2" FM_REMOTE_JOB_STATE_ROOT="$3" bash -c '
    . "$1"
    fm_remote_job_prepare_state "$2" || { echo "prepare_state rc=$? err=${FM_REMOTE_JOB_ERROR:-}" >&2; exit 9; }
    fm_remote_job_lock_owner_matches_process "$2"
    rc=$?
    printf "checker-locale=%s rc=%s owner_pid=%s\n" "$3" "$rc" "${FM_REMOTE_JOB_OWNER_PID:-}"
    exit "$rc"
  ' _ "$1" "$4" "$2"
}

printf 'live process pid: %s (command: %s)\n' "$LIVE_PID" "$(LC_ALL=C /bin/ps -p "$LIVE_PID" -o command=)"
printf 'lstart under de_DE.UTF-8 : %s\n' "$(LC_ALL=de_DE.UTF-8 /bin/ps -p "$LIVE_PID" -o lstart=)"
printf 'lstart under C           : %s\n' "$(LC_ALL=C /bin/ps -p "$LIVE_PID" -o lstart=)"

echo
echo "== incident reproduction with BASE (pre-fix) lib =="
record_worker_lock "$LAB/fm-remote-job-lib.base.sh" de_DE.UTF-8 "$LAB/state-base" "$ACCOUNT" "$LIVE_PID"
printf 'recorded start: %s\n' "$(cat "$LAB/state-base/worker.lock/start")"
if check_worker_lock "$LAB/fm-remote-job-lib.base.sh" C "$LAB/state-base" "$ACCOUNT" 2>/dev/null; then
  echo "BASE: live owner verified (unexpected — incident not reproduced)"
else
  echo "BASE: C-locale checker declared the de_DE-recorded live owner DEAD (rc=$?) — incident mechanism reproduced"
fi

echo
echo "== same scenario with TARGET (fixed) lib =="
record_worker_lock "$ROOT/bin/fm-remote-job-lib.sh" de_DE.UTF-8 "$LAB/state-target" "$ACCOUNT" "$LIVE_PID"
printf 'recorded start: %s\n' "$(cat "$LAB/state-target/worker.lock/start")"
if check_worker_lock "$ROOT/bin/fm-remote-job-lib.sh" C "$LAB/state-target" "$ACCOUNT" 2>/dev/null; then
  echo "TARGET: de_DE-recorded live owner verified ALIVE by C-locale checker — fix works"
else
  echo "TARGET: FAIL — live owner declared dead (rc=$?)"
fi

echo
echo "== adversarial reverse: recorded under C, checked under de_DE (fixed lib) =="
record_worker_lock "$ROOT/bin/fm-remote-job-lib.sh" C "$LAB/state-rev" "$ACCOUNT" "$LIVE_PID"
if check_worker_lock "$ROOT/bin/fm-remote-job-lib.sh" de_DE.UTF-8 "$LAB/state-rev" "$ACCOUNT" 2>/dev/null; then
  echo "reverse check: alive — pinning is bidirectional"
else
  echo "reverse check: FAIL (rc=$?)"
fi

echo
echo "== guard: a genuinely dead owner must stay dead under the fix =="
( sleep 0.1 ) & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null
mkdir -p "$LAB/state-dead/worker.lock"
printf '%s\n' "$DEAD_PID" > "$LAB/state-dead/worker.lock/pid"
if env LC_ALL=C FM_REMOTE_JOB_STATE_ROOT="$LAB/state-dead" bash -c '
  . "$1"; fm_remote_job_prepare_state "$2" >/dev/null
  fm_remote_job_process_start "$3" > "$FM_REMOTE_JOB_STATE/worker.lock/start"
' _ "$ROOT/bin/fm-remote-job-lib.sh" "$ACCOUNT" "$DEAD_PID" 2>/dev/null; then
  echo "UNEXPECTED: dead pid produced a start record: $(cat "$LAB/state-dead/worker.lock/start")"
else
  echo "guard: recording a dead pid fails as expected (rc=$?) — pinning masks no real deaths"
fi

echo
echo "== stale-record guard: pid alive but start mismatched must stay dead =="
mkdir -p "$LAB/state-stale/worker.lock"
printf '%s\n' "$LIVE_PID" > "$LAB/state-stale/worker.lock/pid"
printf '%s\n' "Mon 01 Jan 00:00:00 2001" > "$LAB/state-stale/worker.lock/start"
LC_ALL=C /bin/ps -p "$LIVE_PID" -o command= > "$LAB/state-stale/worker.lock/command"
if check_worker_lock "$ROOT/bin/fm-remote-job-lib.sh" C "$LAB/state-stale" "$ACCOUNT" 2>/dev/null; then
  echo "guard: FAIL — stale start record verified as alive"
else
  echo "guard: stale start record correctly declared dead (rc=$?)"
fi

kill "$LIVE_PID" 2>/dev/null
wait "$LIVE_PID" 2>/dev/null
echo "live pid $LIVE_PID terminated; lab removed on exit"
