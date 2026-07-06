#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prefix=${PREFIX:-"$HOME/.local"}
skills_dir=${SKILLS_DIR:-"$HOME/.agents/skills"}

mkdir -p "$prefix/bin" "$skills_dir/fable-advisor"

cp "$repo_dir/bin/fable-advisor" "$prefix/bin/fable-advisor"
chmod 755 "$prefix/bin/fable-advisor"

cp -R "$repo_dir/skills/fable-advisor/." "$skills_dir/fable-advisor/"

cat <<'MSG'
Installed fable-advisor and the fable-advisor skill.

Add this to AGENTS.md if you want a persistent reminder:
Use `$fable-advisor` for high-stakes plans, repeated failures, risky diffs, or final completion checks where a Claude Fable 5 second opinion would reduce risk.
MSG
