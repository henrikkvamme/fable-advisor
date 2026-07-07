#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir="${TMPDIR:-/tmp}/fable-advisor-test-$$"

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
  : > "$tmp_dir/op-args"
  rm -rf "$HOME/.config/fable-advisor" "$HOME/.config/fish"
}

cat > "$tmp_dir/bin/claude" <<'FAKE_CLAUDE'
#!/bin/sh
printf '%s\n' "$@" > "$FABLE_ADVISOR_TEST_ARGS"
printf '%s' "${ANTHROPIC_API_KEY:-}" > "$FABLE_ADVISOR_TEST_KEY"
cat > "$FABLE_ADVISOR_TEST_STDIN"
printf "fake-advice\n"
FAKE_CLAUDE
chmod +x "$tmp_dir/bin/claude"

cat > "$tmp_dir/bin/op" <<'FAKE_OP'
#!/bin/sh
printf '%s\n' "$@" > "$FABLE_ADVISOR_TEST_OP_ARGS"
if [ "$1" = "read" ]; then
  printf "op_test_key\n"
  exit 0
fi
exit 1
FAKE_OP
chmod +x "$tmp_dir/bin/op"

PATH="$tmp_dir/bin:$PATH"
HOME="$tmp_dir/home"
FABLE_ADVISOR_TEST_ARGS="$tmp_dir/claude-args"
FABLE_ADVISOR_TEST_STDIN="$tmp_dir/claude-stdin"
FABLE_ADVISOR_TEST_KEY="$tmp_dir/claude-key"
FABLE_ADVISOR_TEST_OP_ARGS="$tmp_dir/op-args"
export PATH HOME FABLE_ADVISOR_TEST_ARGS FABLE_ADVISOR_TEST_STDIN FABLE_ADVISOR_TEST_KEY FABLE_ADVISOR_TEST_OP_ARGS

test_plain_prompt_uses_stateless_advisor_defaults() {
  reset_fake_claude
  output=$("$repo_dir/bin/fable-advisor" "Review this plan")
  assert_eq "plain prompt returns claude output" "fake-advice" "$output"
  assert_file_contains "plain prompt uses bare mode" "$FABLE_ADVISOR_TEST_ARGS" "--bare"
  assert_file_contains "plain prompt ignores user settings" "$FABLE_ADVISOR_TEST_ARGS" "--setting-sources"
  assert_arg_value "plain prompt uses fable model" "$FABLE_ADVISOR_TEST_ARGS" "--model" "claude-fable-5"
  assert_arg_value "plain prompt uses xhigh effort" "$FABLE_ADVISOR_TEST_ARGS" "--effort" "xhigh"
  assert_file_contains "plain prompt disables tools" "$FABLE_ADVISOR_TEST_ARGS" "--tools"
  assert_file_contains "plain prompt is printed directly" "$FABLE_ADVISOR_TEST_ARGS" "Review this plan"
}

test_piped_context_is_sent_with_prompt() {
  reset_fake_claude
  output=$(printf "diff --git a/app b/app\n+fixed bug\n" | "$repo_dir/bin/fable-advisor" --stdin "Review this diff")
  assert_eq "piped context returns claude output" "fake-advice" "$output"
  assert_file_contains "piped context includes prompt" "$FABLE_ADVISOR_TEST_STDIN" "Review this diff"
  assert_file_contains "piped context has context heading" "$FABLE_ADVISOR_TEST_STDIN" "## Context"
  assert_file_contains "piped context includes stdin" "$FABLE_ADVISOR_TEST_STDIN" "+fixed bug"
}

test_piped_context_requires_stdin_flag() {
  reset_fake_claude
  output=$(printf "this should be ignored\n" | "$repo_dir/bin/fable-advisor" "Review default stdin behavior")
  assert_eq "default stdin behavior returns claude output" "fake-advice" "$output"
  assert_file_contains "default stdin behavior passes prompt as argument" "$FABLE_ADVISOR_TEST_ARGS" "Review default stdin behavior"
  assert_eq "default stdin behavior leaves claude stdin empty" "" "$(cat "$FABLE_ADVISOR_TEST_STDIN")"
}

test_no_stdin_ignores_available_stdin() {
  reset_fake_claude
  output=$(printf "this should be ignored\n" | "$repo_dir/bin/fable-advisor" --no-stdin "Review without pipe")
  assert_eq "no stdin returns claude output" "fake-advice" "$output"
  assert_file_contains "no stdin passes prompt as argument" "$FABLE_ADVISOR_TEST_ARGS" "Review without pipe"
  assert_eq "no stdin leaves claude stdin empty" "" "$(cat "$FABLE_ADVISOR_TEST_STDIN")"
}

test_stdin_flag_conflict_exits_before_calling_claude() {
  reset_fake_claude
  if "$repo_dir/bin/fable-advisor" --stdin --no-stdin "Check conflict" > "$tmp_dir/conflict-out" 2> "$tmp_dir/conflict-err"; then
    fail "stdin flag conflict exits nonzero"
  else
    status=$?
    assert_eq "stdin flag conflict exits with usage status" "2" "$status"
  fi
  assert_file_contains "stdin flag conflict prints readable error" "$tmp_dir/conflict-err" "cannot be combined"
  assert_eq "stdin flag conflict does not call claude" "" "$(cat "$FABLE_ADVISOR_TEST_ARGS")"
}

test_transcript_file_is_included_explicitly() {
  reset_fake_claude
  transcript="$tmp_dir/session.jsonl"
  printf '{"role":"user","content":"original requirement"}\n' > "$transcript"
  output=$("$repo_dir/bin/fable-advisor" --transcript "$transcript" "Check dropped requirements")
  assert_eq "transcript returns claude output" "fake-advice" "$output"
  assert_file_contains "transcript includes prompt" "$FABLE_ADVISOR_TEST_STDIN" "Check dropped requirements"
  assert_file_contains "transcript has heading" "$FABLE_ADVISOR_TEST_STDIN" "## Transcript"
  assert_file_contains "transcript includes file content" "$FABLE_ADVISOR_TEST_STDIN" "original requirement"
}

test_model_and_effort_flags_override_defaults() {
  reset_fake_claude
  output=$("$repo_dir/bin/fable-advisor" --model claude-fable-5 --effort high "Check cost")
  assert_eq "flag overrides return claude output" "fake-advice" "$output"
  assert_arg_value "model flag is passed" "$FABLE_ADVISOR_TEST_ARGS" "--model" "claude-fable-5"
  assert_arg_value "effort flag is passed" "$FABLE_ADVISOR_TEST_ARGS" "--effort" "high"
}

test_model_and_effort_env_override_defaults() {
  reset_fake_claude
  FABLE_ADVISOR_MODEL=test-model FABLE_ADVISOR_EFFORT=low "$repo_dir/bin/fable-advisor" "Check env" >/dev/null
  assert_arg_value "model env is passed" "$FABLE_ADVISOR_TEST_ARGS" "--model" "test-model"
  assert_arg_value "effort env is passed" "$FABLE_ADVISOR_TEST_ARGS" "--effort" "low"
}

test_default_env_file_supplies_anthropic_api_key() {
  reset_fake_claude
  mkdir -p "$HOME/.config/fable-advisor"
  printf 'ANTHROPIC_API_KEY=env_file_test_key\n' > "$HOME/.config/fable-advisor/secrets.env"
  env -u ANTHROPIC_API_KEY FABLE_ADVISOR_SECRETS_FILE="$tmp_dir/missing-secrets.fish" "$repo_dir/bin/fable-advisor" "Check env file key" >/dev/null
  assert_eq "default env file supplies api key" "env_file_test_key" "$(cat "$FABLE_ADVISOR_TEST_KEY")"
  assert_eq "default env file avoids op" "" "$(cat "$FABLE_ADVISOR_TEST_OP_ARGS")"
}

test_fish_secret_file_supplies_anthropic_api_key() {
  reset_fake_claude
  mkdir -p "$HOME/.config/fish/conf.d"
  printf 'set -gx ANTHROPIC_API_KEY fake_test_key\n' > "$HOME/.config/fish/conf.d/secrets.fish"
  env -u ANTHROPIC_API_KEY "$repo_dir/bin/fable-advisor" "Check key" >/dev/null
  assert_eq "fish secret supplies api key" "fake_test_key" "$(cat "$FABLE_ADVISOR_TEST_KEY")"
}

test_custom_secret_file_supplies_anthropic_api_key() {
  reset_fake_claude
  custom_secret="$tmp_dir/custom-secrets.fish"
  printf 'set -gx ANTHROPIC_API_KEY custom_test_key\n' > "$custom_secret"
  env -u ANTHROPIC_API_KEY FABLE_ADVISOR_SECRETS_FILE="$custom_secret" "$repo_dir/bin/fable-advisor" "Check custom key" >/dev/null
  assert_eq "custom secret file supplies api key" "custom_test_key" "$(cat "$FABLE_ADVISOR_TEST_KEY")"
}

test_onepassword_supplies_anthropic_api_key() {
  reset_fake_claude
  env -u ANTHROPIC_API_KEY FABLE_ADVISOR_SECRETS_FILE="$tmp_dir/missing-secrets.fish" "$repo_dir/bin/fable-advisor" "Check op key" >/dev/null
  assert_eq "1password supplies api key" "op_test_key" "$(cat "$FABLE_ADVISOR_TEST_KEY")"
  assert_arg_value "1password default reference is used" "$FABLE_ADVISOR_TEST_OP_ARGS" "read" "op://Agent Access/Anthropic API Key/credential"
}

test_empty_request_exits_before_calling_claude() {
  reset_fake_claude
  if "$repo_dir/bin/fable-advisor" > "$tmp_dir/empty-out" 2> "$tmp_dir/empty-err"; then
    fail "empty request exits nonzero"
  else
    status=$?
    assert_eq "empty request exits with usage status" "2" "$status"
  fi
  assert_file_contains "empty request prints usage" "$tmp_dir/empty-err" "Usage: fable-advisor"
  assert_eq "empty request does not call claude" "" "$(cat "$FABLE_ADVISOR_TEST_ARGS")"
}

test_missing_transcript_exits_before_calling_claude() {
  reset_fake_claude
  missing="$tmp_dir/missing-session.jsonl"
  if "$repo_dir/bin/fable-advisor" --transcript "$missing" "Check transcript" > "$tmp_dir/missing-transcript-out" 2> "$tmp_dir/missing-transcript-err"; then
    fail "missing transcript exits nonzero"
  else
    status=$?
    assert_eq "missing transcript exits with usage status" "2" "$status"
  fi
  assert_file_contains "missing transcript prints readable error" "$tmp_dir/missing-transcript-err" "cannot read transcript"
  assert_eq "missing transcript does not call claude" "" "$(cat "$FABLE_ADVISOR_TEST_ARGS")"
}

test_help_prints_usage_without_calling_claude() {
  reset_fake_claude
  output=$("$repo_dir/bin/fable-advisor" --help 2>&1)
  assert_contains "help includes usage" "$output" "Usage: fable-advisor"
  assert_eq "help does not call claude" "" "$(cat "$FABLE_ADVISOR_TEST_ARGS")"
}

test_help_works_without_claude_on_path() {
  reset_fake_claude
  set +e
  output=$(PATH="/usr/bin:/bin" "$repo_dir/bin/fable-advisor" --help 2>&1)
  status=$?
  set -e
  assert_eq "help without claude exits success" "0" "$status"
  assert_contains "help without claude includes usage" "$output" "Usage: fable-advisor"
}

test_installer_copies_cli_and_skill_to_configurable_locations() {
  install_prefix="$tmp_dir/install-prefix"
  skills_dir="$tmp_dir/skills"
  PREFIX="$install_prefix" SKILLS_DIR="$skills_dir" sh "$repo_dir/install.sh" > "$tmp_dir/install-out"
  assert_eq "installer copies fable-advisor" "yes" "$(test -x "$install_prefix/bin/fable-advisor" && printf yes || printf no)"
  assert_eq "installer copies skill" "yes" "$(test -f "$skills_dir/fable-advisor/SKILL.md" && printf yes || printf no)"
  assert_eq "installer copies openai metadata" "yes" "$(test -f "$skills_dir/fable-advisor/agents/openai.yaml" && printf yes || printf no)"
  assert_file_contains "installer prints agents hint" "$tmp_dir/install-out" '$fable-advisor'
}

test_plain_prompt_uses_stateless_advisor_defaults
test_piped_context_is_sent_with_prompt
test_piped_context_requires_stdin_flag
test_no_stdin_ignores_available_stdin
test_stdin_flag_conflict_exits_before_calling_claude
test_transcript_file_is_included_explicitly
test_model_and_effort_flags_override_defaults
test_model_and_effort_env_override_defaults
test_default_env_file_supplies_anthropic_api_key
test_fish_secret_file_supplies_anthropic_api_key
test_custom_secret_file_supplies_anthropic_api_key
test_onepassword_supplies_anthropic_api_key
test_empty_request_exits_before_calling_claude
test_missing_transcript_exits_before_calling_claude
test_help_prints_usage_without_calling_claude
test_help_works_without_claude_on_path
test_installer_copies_cli_and_skill_to_configurable_locations

if [ "$fail_count" -gt 0 ]; then
  printf "%s passed, %s failed\n" "$pass_count" "$fail_count" >&2
  exit 1
fi

printf "%s passed\n" "$pass_count"
