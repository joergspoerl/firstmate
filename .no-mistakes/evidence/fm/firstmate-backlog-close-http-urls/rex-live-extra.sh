# Additional Rex plan transcript for a plain-http PR done note.
test_http_pr_done_mark_with_evidence() {
  local out
  mark_case marks-http-pr-evidence
  printf 'on\n' > "$MARK_DIR/home/config/rex-status-marks"
  printf '%s\n' "window=$MARK_T" "backend=rex" "kind=ship" > "$MARK_DIR/home/state/t1.meta"
  mark_task_status 'done [at=1700000350]: PR http://pi4:3001/o/r/pulls/9 merged'
  out=$(marks_run plan t1)
  assert_contains "$out" $'done\t\tPR ready: PR http://pi4:3001/o/r/pulls/9 merged' "plain-http PR note was not labelled PR ready"
  printf '$ fm-rex-marks.sh plan t1\n%s\n' "$out" > "$EVIDENCE/rex-http-pr-mark.txt"
  pass "a done note with a plain-http PR produces a PR-ready Rex mark"
}
