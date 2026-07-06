#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir="${TMPDIR:-/tmp}/ccf-test-$$"

pass_count=0
fail_count=0

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

fail() {
  printf "not ok - %s\n" "$1" >&2
  fail_count=$((fail_count + 1))
}

pass() {
  printf "ok - %s\n" "$1"
  pass_count=$((pass_count + 1))
}

assert_eq() {
  label=$1
  expected=$2
  actual=$3
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label"
    printf "expected: %s\nactual:   %s\n" "$expected" "$actual" >&2
  fi
}

assert_file_contains() {
  label=$1
  file=$2
  needle=$3
  if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
    printf "missing %s in %s\n" "$needle" "$file" >&2
  fi
}

assert_contains() {
  label=$1
  haystack=$2
  needle=$3
  case $haystack in
    *"$needle"*) pass "$label" ;;
    *)
      fail "$label"
      printf "missing %s\n" "$needle" >&2
      ;;
  esac
}

assert_arg_value() {
  label=$1
  file=$2
  flag=$3
  expected=$4
  actual=$(awk -v flag="$flag" '$0 == flag { getline; print; exit }' "$file")
  assert_eq "$label" "$expected" "$actual"
}

reset_fake_claude() {
  : > "$tmp_dir/claude-args"
  : > "$tmp_dir/claude-stdin"
  : > "$tmp_dir/claude-key"
}

cat > "$tmp_dir/bin/claude" <<'FAKE_CLAUDE'
#!/bin/sh
printf '%s\n' "$@" > "$CCF_TEST_ARGS"
printf '%s' "${ANTHROPIC_API_KEY:-}" > "$CCF_TEST_KEY"
cat > "$CCF_TEST_STDIN"
printf "fake-advice\n"
FAKE_CLAUDE
chmod +x "$tmp_dir/bin/claude"

PATH="$tmp_dir/bin:$PATH"
HOME="$tmp_dir/home"
CCF_TEST_ARGS="$tmp_dir/claude-args"
CCF_TEST_STDIN="$tmp_dir/claude-stdin"
CCF_TEST_KEY="$tmp_dir/claude-key"
export PATH HOME CCF_TEST_ARGS CCF_TEST_STDIN CCF_TEST_KEY

test_plain_prompt_uses_stateless_advisor_defaults() {
  reset_fake_claude
  output=$("$repo_dir/bin/ccf" "Review this plan")
  assert_eq "plain prompt returns claude output" "fake-advice" "$output"
  assert_file_contains "plain prompt uses bare mode" "$CCF_TEST_ARGS" "--bare"
  assert_file_contains "plain prompt ignores user settings" "$CCF_TEST_ARGS" "--setting-sources"
  assert_arg_value "plain prompt uses fable model" "$CCF_TEST_ARGS" "--model" "claude-fable-5"
  assert_arg_value "plain prompt uses xhigh effort" "$CCF_TEST_ARGS" "--effort" "xhigh"
  assert_file_contains "plain prompt disables tools" "$CCF_TEST_ARGS" "--tools"
  assert_file_contains "plain prompt is printed directly" "$CCF_TEST_ARGS" "Review this plan"
}

test_piped_context_is_sent_with_prompt() {
  reset_fake_claude
  output=$(printf "diff --git a/app b/app\n+fixed bug\n" | "$repo_dir/bin/ccf" "Review this diff")
  assert_eq "piped context returns claude output" "fake-advice" "$output"
  assert_file_contains "piped context includes prompt" "$CCF_TEST_STDIN" "Review this diff"
  assert_file_contains "piped context has context heading" "$CCF_TEST_STDIN" "## Context"
  assert_file_contains "piped context includes stdin" "$CCF_TEST_STDIN" "+fixed bug"
}

test_transcript_file_is_included_explicitly() {
  reset_fake_claude
  transcript="$tmp_dir/session.jsonl"
  printf '{"role":"user","content":"original requirement"}\n' > "$transcript"
  output=$("$repo_dir/bin/ccf" --transcript "$transcript" "Check dropped requirements")
  assert_eq "transcript returns claude output" "fake-advice" "$output"
  assert_file_contains "transcript includes prompt" "$CCF_TEST_STDIN" "Check dropped requirements"
  assert_file_contains "transcript has heading" "$CCF_TEST_STDIN" "## Transcript"
  assert_file_contains "transcript includes file content" "$CCF_TEST_STDIN" "original requirement"
}

test_model_and_effort_flags_override_defaults() {
  reset_fake_claude
  output=$("$repo_dir/bin/ccf" --model claude-fable-5 --effort high "Check cost")
  assert_eq "flag overrides return claude output" "fake-advice" "$output"
  assert_arg_value "model flag is passed" "$CCF_TEST_ARGS" "--model" "claude-fable-5"
  assert_arg_value "effort flag is passed" "$CCF_TEST_ARGS" "--effort" "high"
}

test_model_and_effort_env_override_defaults() {
  reset_fake_claude
  CC_ADVISOR_MODEL=test-model CC_ADVISOR_EFFORT=low "$repo_dir/bin/ccf" "Check env" >/dev/null
  assert_arg_value "model env is passed" "$CCF_TEST_ARGS" "--model" "test-model"
  assert_arg_value "effort env is passed" "$CCF_TEST_ARGS" "--effort" "low"
}

test_fish_secret_file_supplies_anthropic_api_key() {
  reset_fake_claude
  mkdir -p "$HOME/.config/fish/conf.d"
  printf 'set -gx ANTHROPIC_API_KEY fake_test_key\n' > "$HOME/.config/fish/conf.d/secrets.fish"
  env -u ANTHROPIC_API_KEY "$repo_dir/bin/ccf" "Check key" >/dev/null
  assert_eq "fish secret supplies api key" "fake_test_key" "$(cat "$CCF_TEST_KEY")"
}

test_custom_secret_file_supplies_anthropic_api_key() {
  reset_fake_claude
  custom_secret="$tmp_dir/custom-secrets.fish"
  printf 'set -gx ANTHROPIC_API_KEY custom_test_key\n' > "$custom_secret"
  env -u ANTHROPIC_API_KEY CCF_SECRETS_FILE="$custom_secret" "$repo_dir/bin/ccf" "Check custom key" >/dev/null
  assert_eq "custom secret file supplies api key" "custom_test_key" "$(cat "$CCF_TEST_KEY")"
}

test_empty_request_exits_before_calling_claude() {
  reset_fake_claude
  if "$repo_dir/bin/ccf" > "$tmp_dir/empty-out" 2> "$tmp_dir/empty-err"; then
    fail "empty request exits nonzero"
  else
    status=$?
    assert_eq "empty request exits with usage status" "2" "$status"
  fi
  assert_file_contains "empty request prints usage" "$tmp_dir/empty-err" "Usage: ccf"
  assert_eq "empty request does not call claude" "" "$(cat "$CCF_TEST_ARGS")"
}

test_missing_transcript_exits_before_calling_claude() {
  reset_fake_claude
  missing="$tmp_dir/missing-session.jsonl"
  if "$repo_dir/bin/ccf" --transcript "$missing" "Check transcript" > "$tmp_dir/missing-transcript-out" 2> "$tmp_dir/missing-transcript-err"; then
    fail "missing transcript exits nonzero"
  else
    status=$?
    assert_eq "missing transcript exits with usage status" "2" "$status"
  fi
  assert_file_contains "missing transcript prints readable error" "$tmp_dir/missing-transcript-err" "cannot read transcript"
  assert_eq "missing transcript does not call claude" "" "$(cat "$CCF_TEST_ARGS")"
}

test_help_prints_usage_without_calling_claude() {
  reset_fake_claude
  output=$("$repo_dir/bin/ccf" --help 2>&1)
  assert_contains "help includes usage" "$output" "Usage: ccf"
  assert_eq "help does not call claude" "" "$(cat "$CCF_TEST_ARGS")"
}

test_installer_copies_cli_and_skill_to_configurable_locations() {
  install_prefix="$tmp_dir/install-prefix"
  skills_dir="$tmp_dir/skills"
  PREFIX="$install_prefix" SKILLS_DIR="$skills_dir" sh "$repo_dir/install.sh" > "$tmp_dir/install-out"
  assert_eq "installer copies ccf" "yes" "$(test -x "$install_prefix/bin/ccf" && printf yes || printf no)"
  assert_eq "installer copies skill" "yes" "$(test -f "$skills_dir/fable-advisor/SKILL.md" && printf yes || printf no)"
  assert_eq "installer copies openai metadata" "yes" "$(test -f "$skills_dir/fable-advisor/agents/openai.yaml" && printf yes || printf no)"
  assert_file_contains "installer prints agents hint" "$tmp_dir/install-out" '$fable-advisor'
}

test_plain_prompt_uses_stateless_advisor_defaults
test_piped_context_is_sent_with_prompt
test_transcript_file_is_included_explicitly
test_model_and_effort_flags_override_defaults
test_model_and_effort_env_override_defaults
test_fish_secret_file_supplies_anthropic_api_key
test_custom_secret_file_supplies_anthropic_api_key
test_empty_request_exits_before_calling_claude
test_missing_transcript_exits_before_calling_claude
test_help_prints_usage_without_calling_claude
test_installer_copies_cli_and_skill_to_configurable_locations

if [ "$fail_count" -gt 0 ]; then
  printf "%s passed, %s failed\n" "$pass_count" "$fail_count" >&2
  exit 1
fi

printf "%s passed\n" "$pass_count"
