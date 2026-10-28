# Additional teardown ledger transcript using the repository's isolated teardown fixture.
test_http_pr_ledger_abort_with_evidence() {
  local case_dir rc advanced_short anchor_short transcript
  transcript="$EVIDENCE/teardown-http-ledger-transcript.txt"
  case_dir=$(make_case parked-run-pipeline-advanced-unfetched-http-pr-evidence)
  write_meta "$case_dir" no-mistakes ship
  land_shippable_commit "$case_dir"
  anchor_short=$(git -C "$case_dir/wt" rev-parse --short=7 HEAD)
  advanced_short=$(make_unfetched_pipeline_heads "$case_dir")
  assert_head_absent_from_worktree "$case_dir/wt" "$advanced_short" "http-pr-ledger-evidence"
  rc=0
  FM_FAKE_AXI_STATUS="$(parked_axi_status_toon fm/task-x1 "$advanced_short")" \
  FM_FAKE_NM_RUNS_LIST="$(cat <<EOF
$(ledger_row running fm/task-x1 "$advanced_short" 2026-09-03 07:55 http://pi4:3001/joergspoerl/Scan2Excel/pulls/7)
$(ledger_row failed fm/task-x1 "$anchor_short" 2026-09-02 06:36)
EOF
)" \
  FM_FAKE_NM_ABORT_LOG="$case_dir/nm-abort.log" \
    run_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr" || rc=$?
  [ "$rc" -eq 0 ] || fail "teardown rejected the plain-http PR ledger row: $(cat "$case_dir/stderr")"
  assert_grep 'abort --run 01RUN' "$case_dir/nm-abort.log" "plain-http PR ledger row did not authorize its own run abort"
  printf '$ fm-teardown.sh task-x1  # parked run ledger contains plain-http PR\n' > "$transcript"
  cat "$case_dir/stdout" "$case_dir/stderr" >> "$transcript"
  printf 'exit=%s\n%s\n' "$rc" '--- no-mistakes invocation ---' >> "$transcript"
  cat "$case_dir/nm-abort.log" >> "$transcript"
  pass "teardown recognizes a plain-http PR row as the task's parked continuation"
}
