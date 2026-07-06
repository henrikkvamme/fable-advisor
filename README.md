<h1 align="center">fable-advisor</h1>

<h3 align="center">Claude Fable as a second opinion for coding agents.</h3>

<p align="center">
  A tiny CLI plus a reusable skill for Codex, OpenCode, and other agent workflows.
</p>

---

`fable-advisor` asks Claude Fable for skeptical, stateless advice on plans, diffs, failures, and completion claims. It is not an MCP server and it does not read agent sessions automatically. Send the context you want reviewed.

## Quick Start

Requires the `claude` CLI and `ANTHROPIC_API_KEY`.

```sh
git clone https://github.com/henrikkvamme/fable-advisor.git
cd fable-advisor
sh install.sh
```

Make sure `~/.local/bin` is on `PATH`, then test:

```sh
fable-advisor "Reply with exactly: ok"
```

The installer copies the CLI to `~/.local/bin/fable-advisor` and the skill to `~/.agents/skills/fable-advisor`.

If `ANTHROPIC_API_KEY` is not set, `fable-advisor` tries 1Password:

```sh
op://Agent Access/Anthropic API Key/credential
```

For OpenCode's config directory:

```sh
SKILLS_DIR="$HOME/.config/opencode/skills" sh install.sh
```

## Usage

```sh
fable-advisor "Stress-test this plan."
git diff | fable-advisor "Review this diff for correctness risks."
fable-advisor --transcript session.jsonl "Check for dropped requirements."
```

Useful overrides:

```sh
FABLE_ADVISOR_MODEL=claude-fable-5 FABLE_ADVISOR_EFFORT=xhigh fable-advisor "Review this."
FABLE_ADVISOR_ANTHROPIC_REF="op://Personal/Anthropic API Key/credential" fable-advisor "Review this."
FABLE_ADVISOR_SECRETS_FILE="$HOME/.config/fish/conf.d/secrets.fish" fable-advisor "Review this."
```

Add this to `AGENTS.md` if you want agents to remember it:

```md
Use `$fable-advisor` for high-stakes plans, repeated failures, risky diffs, or final completion checks where a Claude Fable 5 second opinion would reduce risk.
```

## Development

Tests use a fake `claude` executable, so they do not spend API credits.

```sh
sh -n bin/fable-advisor install.sh test/run.sh
sh test/run.sh
```

## License

[MIT](./LICENSE)
