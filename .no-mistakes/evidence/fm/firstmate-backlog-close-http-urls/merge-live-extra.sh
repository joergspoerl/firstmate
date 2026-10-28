# Additional live merge proof, loaded into the repository's merge test fixtures.
test_http_forgejo_merge_exact_port_with_evidence() {
  local case_dir host url rc transcript
  host=git.self-hosted.example:3000
  url="http://$host/$FJ_OWNER/$FJ_REPO/pulls/12"
  transcript="$EVIDENCE/forgejo-http-merge-transcript.txt"
  : > "$transcript"

  case_dir=$(make_forgejo_case forgejo-http-exact-port-evidence)
  write_tea_logins_json "$case_dir/tea-logins.json" \
    other-3001 "http://git.self-hosted.example:3001" \
    "$FJ_LOGIN" "http://$host"
  set +e
  run_pr_merge "$case_dir" task-x1 "$url" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "plain-http exact-port Forgejo merge failed: $(cat "$case_dir/stderr")"
  assert_grep "pr=$url" "$case_dir/state/task-x1.meta" "plain-http merge did not record its PR"
  assert_grep "--login $FJ_LOGIN --repo $FJ_OWNER/$FJ_REPO /repos/{owner}/{repo}/pulls/12" \
    "$case_dir/tea.log" "plain-http merge did not use the exact :3000 login"
  [ -n "$(tea_merge_line "$case_dir/tea.log")" ] || fail "plain-http merge made no merge call"
  printf '$ fm-pr-merge.sh task-x1 %s\n' "$url" >> "$transcript"
  cat "$case_dir/stdout" "$case_dir/stderr" >> "$transcript"
  printf 'exit=%s\n' "$rc" >> "$transcript"
  printf '%s\n' '--- recorded PR ---' >> "$transcript"
  grep '^pr=' "$case_dir/state/task-x1.meta" >> "$transcript"
  printf '%s\n' '--- tea invocations ---' >> "$transcript"
  cat "$case_dir/tea.log" >> "$transcript"

  case_dir=$(make_forgejo_case forgejo-http-wrong-port-evidence)
  write_tea_logins_json "$case_dir/tea-logins.json" other-3001 "http://git.self-hosted.example:3001"
  set +e
  run_pr_merge "$case_dir" task-x1 "$url" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "merge used the only login on another port"
  [ -z "$(tea_merge_line "$case_dir/tea.log")" ] || fail "wrong-port case attempted a merge"
  printf '%s\n' '--- only :3001 login; merging :3000 must refuse ---' >> "$transcript"
  cat "$case_dir/stdout" "$case_dir/stderr" >> "$transcript"
  printf 'exit=%s; merge-attempted=no\n' "$rc" >> "$transcript"
  pass "plain-http Forgejo merge uses the exact ported login and refuses another port"
}
