# Additional close-recovery transcript using the repository's real backlog fixtures.
test_http_forgejo_close_replay_with_evidence() {
  local case_dir id out real_tasks_axi pr_url transcript
  transcript="$EVIDENCE/backlog-close-transcript.txt"
  : > "$transcript"
  pr_url=http://pi4:3001/joergspoerl/Scan2Excel/pulls/7
  id=atomic-heal-http-forgejo-evidence
  case_dir=$(make_home heal-pending-http-forgejo-close-evidence)
  add_item "$case_dir" "$id"
  start_item "$case_dir" "$id"
  printf 'id=%s\ndata=%s\nspawn_gen=spawn-heal-http-forgejo\narg=--pr\narg=%s\n' \
    "$id" "$(home_of "$case_dir")/data" "$pr_url" \
    > "$(home_of "$case_dir")/state/$id.backlog-close"
  real_tasks_axi=$(command -v tasks-axi)
  cat > "$case_dir/fakebin/tasks-axi" <<SH
#!/usr/bin/env bash
previous=
for arg in "\$@"; do
  if [ "\$previous" = --pr ] \
    && ! [[ "\$arg" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+\$ ]] \
    && ! [[ "\$arg" =~ ^https://[^/:]+/[^/]+/[^/]+/pulls/[0-9]+\$ ]]; then
    echo "error: \"Task pr link must be a canonical pull request URL\""
    exit 1
  fi
  previous=\$arg
done
exec "$real_tasks_axi" "\$@"
SH
  chmod +x "$case_dir/fakebin/tasks-axi"
  out=$(run_bootstrap "$case_dir") || fail "plain-http close replay failed: $out"
  [ "$(row_state "$case_dir" "$id")" = done ] || fail "plain-http close did not land"
  printf '$ fm-bootstrap.sh  # replay plain-http Forgejo close\n%s\n' "$out" >> "$transcript"
  printf '%s\n' '--- persisted task after close ---' >> "$transcript"
  tasks-axi show "$id" --file "$(backlog_of "$case_dir")" --full >> "$transcript" \
    || fail "could not read the closed plain-http task"
  assert_absent "$(home_of "$case_dir")/state/$id.backlog-close" "plain-http close marker survived replay"

  pr_url=https://git.example.com/joergspoerl/Scan2Excel/pulls/8
  id=atomic-heal-https-forgejo-evidence
  case_dir=$(make_home heal-pending-https-forgejo-close-evidence)
  add_item "$case_dir" "$id"
  start_item "$case_dir" "$id"
  printf 'id=%s\ndata=%s\nspawn_gen=spawn-heal-https-forgejo\narg=--pr\narg=%s\n' \
    "$id" "$(home_of "$case_dir")/data" "$pr_url" \
    > "$(home_of "$case_dir")/state/$id.backlog-close"
  out=$(run_bootstrap "$case_dir") || fail "https Forgejo close replay failed: $out"
  [ "$(row_state "$case_dir" "$id")" = done ] || fail "https Forgejo close did not land"
  printf '%s\n' '--- https Forgejo close keeps its PR link ---' >> "$transcript"
  tasks-axi show "$id" --file "$(backlog_of "$case_dir")" --full >> "$transcript" \
    || fail "could not read the closed https task"
  pass "close recovery stores a plain-http Forgejo PR as a note and keeps an https Forgejo PR link"
}
