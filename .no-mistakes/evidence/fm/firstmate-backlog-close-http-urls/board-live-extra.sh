# Additional rendered-board evidence using the repository's isolated board fixture.
test_http_board_build_with_evidence() {
  local home data board out rc before after transcript
  home=$(make_home http-pr-urls-evidence)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  transcript="$EVIDENCE/board-build-transcript.txt"
  write_valid_payload "$data"
  jq '.captains_call[1].pr_url = "http://pi4:3001/o/r/pulls/7"
    | .landed = [{
      "id":"http-landed",
      "repo":"sample",
      "what":"Landed through plain-http Forgejo",
      "owner":"firstmate",
      "pr_url":"http://pi4:3001/o/r/pulls/8"
    }]' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  out=$(run_board "$home" build "$data") || fail "plain-http board build failed: $out"
  cp "$board" "$EVIDENCE/bearings-http-board.html"
  extract_payload "$board" | jq . > "$EVIDENCE/bearings-http-board-payload.json"
  printf '$ fm-bearings-board.sh build payload.json\n%s\n' "$out" > "$transcript"

  before=$(shasum -a 256 "$board")
  jq '.captains_call[1].pr_url = "javascript:alert(1)"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e
  out=$(run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "board accepted a javascript PR URL"
  after=$(shasum -a 256 "$board")
  [ "$before" = "$after" ] || fail "unsafe board payload changed the published board"
  printf '%s\n' '--- unsafe URL must still refuse ---' "$out" "exit=$rc; published-board-unchanged=yes" >> "$transcript"
  pass "board renders plain-http Forgejo PR links and still rejects unsafe schemes"
}
