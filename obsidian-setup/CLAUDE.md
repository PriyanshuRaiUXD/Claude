# Vault Memory — C:\Claude_stuff

This is an Obsidian vault used as a persistent memory layer for Claude Code.
When you start a session with this vault as the working directory, this file
is auto-loaded as context.

## Vault layout

- `daily/` — one note per day. Running scratchpad + session log.
- `projects/` — long-lived project notes. Each file is a single topic.
- `inbox/` — unsorted captures (web clips via defuddle, quick notes).
- `references/` — reusable context (style guides, API keys names, prompts).
- `templates/` — note templates.

## Session protocol

At the start of each session:
1. Read `daily/YYYY-MM-DD.md` for today. If it doesn't exist, create it from `templates/daily-note.md`.
2. Read the previous day's note (most recent file in `daily/`) for carryover context.
3. If the task touches a named project, read the matching `projects/<name>.md`.

At the end of each session (or when the user says "log this"):
1. Append a dated section to today's daily note with: what was worked on, decisions made, open questions, next steps.
2. If a durable fact emerged (a preference, a convention, a non-obvious gotcha), add it to `projects/<name>.md` or `references/`.

## Writing rules

- Use Obsidian Flavored Markdown: `[[wikilinks]]` for cross-note references, `![[embed]]` for inlining, YAML frontmatter for metadata, `> [!note]` callouts.
- Prefer atomic notes: one concept per file. Link liberally.
- Use frontmatter `tags:`, `status:`, `updated:` for queryability via Bases.
- Don't edit notes the user is actively writing without asking.

## Karpathy guidelines (code work)

When writing or editing code in this vault or on projects referenced here:
- **Think before coding**: state assumptions, surface ambiguity, don't guess silently.
- **Simplicity first**: minimum code that solves the problem. No speculative abstractions.
- **Surgical changes**: touch only what the task requires. Don't drive-by refactor.
- **Goal-driven**: define success criteria up front ("what test passes when this works").

## Available skills

This setup expects these skills installed at `%USERPROFILE%\.claude\skills\`:
- `obsidian-markdown` — OFM syntax (wikilinks, callouts, properties)
- `obsidian-bases` — .base files (database views)
- `obsidian-cli` — vault operations from the CLI
- `json-canvas` — .canvas files
- `defuddle` — clean markdown extraction from URLs
- `karpathy-guidelines` — coding behavioral guidelines

Invoke with `/skill-name` or let them auto-trigger based on context.
