# Additional live CLI proofs, loaded into the repository's PR test fixtures.
test_http_forgejo_arming_end_to_end_with_evidence() {
  local dir url out rc transcript
  dir=$(make_case http-forgejo-arming-evidence)
  url=http://pi4:3001/o/r/pulls/7
  transcript="$EVIDENCE/pr-http-live-transcript.txt"
  cat > "$dir/fakebin/tea" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_TEA_LOG"
if [ "${1:-} ${2:-}" = "login list" ]; then
  if [ -n "${FM_TEST_TEA_WRONG_PORT_ONLY:-}" ]; then
    printf '[{"name":"other-3002","url":"http://pi4:3002"}]\n'
  else
    printf '[{"name":"main-3001","url":"http://pi4:3001"},{"name":"other-3002","url":"http://pi4:3002"}]\n'
  fi
  exit 0
fi
[ "${1:-}" = api ] || exit 0
case "${FM_TEST_TEA_PULL:-open}" in
  merged) printf '{"state":"closed","merged":true,"head":{"sha":"abc"}}\n' ;;
  *) printf '{"state":"open","merged":false,"head":{"sha":"abc"}}\n' ;;
esac
SH
  chmod +x "$dir/fakebin/tea"
  ln -sf "$(command -v jq)" "$dir/fakebin/jq"
  : > "$dir/tea.log"
  : > "$transcript"

  write_task_meta "$dir" task-a
  printf '$ fm-pr-check.sh task-a %s\n' "$url" >> "$transcript"
  FM_TEST_TEA_LOG="$dir/tea.log" run_check_entry "$dir" task-a "$url" \
    > "$dir/arm.out" 2> "$dir/arm.err" \
    || fail "plain-http Forgejo arming failed: $(cat "$dir/arm.err")"
  cat "$dir/arm.out" "$dir/arm.err" >> "$transcript"
  grep -qxF "pr=$url" "$dir/home/state/task-a.meta" \
    || fail "plain-http Forgejo PR was not recorded in task metadata"
  fm_pr_poll_artifacts_valid "$dir/home/state" task-a "$POLL" \
    || fail "plain-http Forgejo arming did not publish an authenticated poll"
  printf '%s\n' '--- recorded PR ---' >> "$transcript"
  grep '^pr=' "$dir/home/state/task-a.meta" >> "$transcript"
  printf '%s\n' '--- poll sidecar ---' >> "$transcript"
  cat "$dir/home/state/task-a.pr-poll" >> "$transcript"

  out=$(FM_TEST_TEA_LOG="$dir/tea.log" FM_TEST_TEA_PULL=open run_poll "$dir")
  [ -z "$out" ] || fail "open plain-http Forgejo poll emitted a merge"
  printf '%s\n' '--- open poll output (expected empty) ---' "$out" >> "$transcript"
  out=$(FM_TEST_TEA_LOG="$dir/tea.log" FM_TEST_TEA_PULL=merged run_poll "$dir")
  [ "$out" = merged ] || fail "merged plain-http Forgejo poll did not wake"
  printf '%s\n' '--- merged poll output ---' "$out" >> "$transcript"
  grep -qF -- 'api --login main-3001 --repo o/r /repos/{owner}/{repo}/pulls/7' "$dir/tea.log" \
    || fail "the exact :3001 login was not used with :3002 also registered"

  write_task_meta "$dir" task-wrong-port
  : > "$dir/tea.log"
  set +e
  FM_TEST_TEA_LOG="$dir/tea.log" FM_TEST_TEA_WRONG_PORT_ONLY=1 \
    run_check_entry "$dir" task-wrong-port "$url" \
    > "$dir/wrong.out" 2> "$dir/wrong.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "arming used the only login on the wrong port"
  printf '%s\n' '--- only :3002 login; arming :3001 must refuse ---' >> "$transcript"
  cat "$dir/wrong.out" "$dir/wrong.err" >> "$transcript"
  printf 'exit=%s\n' "$rc" >> "$transcript"
  [ ! -e "$dir/home/state/task-wrong-port.check.sh" ] \
    || fail "wrong-port refusal left an armed poll"
  ! grep -q '^pr=' "$dir/home/state/task-wrong-port.meta" \
    || fail "wrong-port refusal recorded the PR"
  ! grep -qF -- 'api --login' "$dir/tea.log" \
    || fail "wrong-port arming read a PR through the other instance"
  pass "plain-http Forgejo arming and polling use only the exact host-and-port login"
}

test_http_non_forgejo_entrypoints_refuse_with_evidence() {
  local dir url id rc transcript
  dir=$(make_case http-non-forgejo-refusals)
  transcript="$EVIDENCE/non-forgejo-http-refusals.txt"
  : > "$transcript"
  for url in \
    http://github.com/o/r/pull/1 \
    http://gitlab.com/g/p/-/merge_requests/1 \
    http://gerrit.example/c/proj/+/1
  do
    id="task-$RANDOM"
    write_task_meta "$dir" "$id"
    set +e
    run_check_entry "$dir" "$id" "$url" > "$dir/refusal.out" 2> "$dir/refusal.err"
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || fail "non-Forgejo http URL was not rejected at the PR-check entrypoint: $url"
    [ ! -e "$dir/home/state/$id.check.sh" ] || fail "rejected non-Forgejo URL armed a poll: $url"
    ! grep -q '^pr=' "$dir/home/state/$id.meta" || fail "rejected non-Forgejo URL was recorded: $url"
    printf '$ fm-pr-check.sh %s %s\n' "$id" "$url" >> "$transcript"
    cat "$dir/refusal.out" "$dir/refusal.err" >> "$transcript"
    printf 'exit=%s; poll-armed=no; pr-recorded=no\n\n' "$rc" >> "$transcript"
  done
  pass "GitHub, GitLab, and Gerrit entrypoints still reject plain-http URLs without side effects"
}
