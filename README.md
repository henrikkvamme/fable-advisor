# Codex Fable Advisor

`codex-fable-advisor` adds a lightweight Claude Fable advisor workflow to Codex.

It ships two pieces:

- `ccf`: a small POSIX `sh` CLI that calls the Claude CLI in stateless advisor mode.
- `fable-advisor`: a Codex skill that tells Codex when and how to ask for a skeptical second opinion.

This is intentionally not an MCP server. The advisor is a one-shot command: pass a plan, diff, failure log, or transcript excerpt; read the advice; then decide what to change.

## Requirements

- `claude` CLI on `PATH`
- `ANTHROPIC_API_KEY` in the environment, or a fish secrets file containing `set -gx ANTHROPIC_API_KEY ...`
- Codex skills enabled if you want the packaged skill

## Install

```sh
git clone https://github.com/henrikkvamme/codex-fable-advisor.git
cd codex-fable-advisor
sh install.sh
```

The installer copies:

- `bin/ccf` to `${PREFIX:-$HOME/.local}/bin/ccf`
- `skills/fable-advisor` to `${SKILLS_DIR:-$HOME/.agents/skills}/fable-advisor`

For custom locations:

```sh
PREFIX="$HOME/.local" SKILLS_DIR="$HOME/.agents/skills" sh install.sh
```

Add this to `AGENTS.md` if you want a persistent reminder:

```md
Use `$fable-advisor` for high-stakes plans, repeated failures, risky diffs, or final completion checks where a Claude Fable 5 second opinion would reduce risk.
```

## Usage

Ask for plan advice:

```sh
ccf "Stress-test this plan. Focus on hidden assumptions, missing verification, and simpler alternatives: ..."
```

Review a diff:

```sh
git diff | ccf "Review this diff for correctness risks, security/privacy issues, and missing tests."
```

Include an explicit transcript file:

```sh
ccf --transcript /path/to/session.jsonl "Check for contradictions, dropped requirements, and unverified claims."
```

Override model or effort:

```sh
ccf --model claude-fable-5 --effort xhigh "Challenge this completion claim."
```

Environment overrides:

```sh
CC_ADVISOR_MODEL=claude-fable-5 CC_ADVISOR_EFFORT=xhigh ccf "Review this."
CCF_SECRETS_FILE="$HOME/.config/fish/conf.d/secrets.fish" ccf "Review this."
```

## Secret Handling

Do not commit API keys.

Recommended options:

- Export `ANTHROPIC_API_KEY` in your shell/session.
- Use your existing secret manager to inject `ANTHROPIC_API_KEY`.
- Store a local, untracked fish file such as `~/.config/fish/conf.d/secrets.fish`:

```fish
set -gx ANTHROPIC_API_KEY sk-ant-...
```

`ccf` reads the environment first. If the key is missing, it checks `CCF_SECRETS_FILE`, then `~/.config/fish/conf.d/secrets.fish`.

## Testing

The test suite uses a fake `claude` executable, so it does not spend API credits.

```sh
sh -n bin/ccf install.sh test/run.sh
sh test/run.sh
```

If ShellCheck is installed:

```sh
shellcheck bin/ccf install.sh test/run.sh
```

## License

MIT
