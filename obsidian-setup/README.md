# Obsidian + Claude Code setup for `C:\Claude_stuff`

This folder contains a ready-to-apply setup kit. Follow the steps below on your
Windows machine — I can't reach your local filesystem from the web sandbox.

## Prerequisites

- **Claude Code installed locally** (the CLI or desktop app). The web app you're
  using now runs in a sandbox; for the vault integration you want the local
  client so it can read/write `C:\Claude_stuff`.
  Install: https://claude.ai/download or `npm install -g @anthropic-ai/claude-code`
- **Node.js 20+** (for the Obsidian MCP server). https://nodejs.org

## Step 1 — Drop the memory file into your vault

Copy `CLAUDE.md` from this folder to `C:\Claude_stuff\CLAUDE.md`.

```powershell
Copy-Item .\obsidian-setup\CLAUDE.md C:\Claude_stuff\CLAUDE.md
```

Claude Code auto-loads `CLAUDE.md` from the working directory at session start.
This is your persistent memory — edit it over time as conventions emerge.

## Step 2 — Create the vault folders

```powershell
cd C:\Claude_stuff
mkdir daily, projects, inbox, references, templates -ErrorAction SilentlyContinue
Copy-Item ..\obsidian-setup\templates\daily-note.md .\templates\daily-note.md
```

Tell Obsidian where templates live: **Settings → Core plugins → Templates →
Template folder location → `templates`**.

## Step 3 — Install skills locally

The skills you installed in this web session live in the sandbox, not on your
Windows machine. Install them locally too:

```powershell
cd $env:USERPROFILE\.claude
mkdir skills -ErrorAction SilentlyContinue
cd skills
git clone https://github.com/kepano/obsidian-skills.git obsidian-skills-tmp
Copy-Item -Recurse .\obsidian-skills-tmp\skills\* .\
Remove-Item -Recurse -Force .\obsidian-skills-tmp
git clone https://github.com/forrestchang/andrej-karpathy-skills.git karpathy-tmp
Copy-Item -Recurse .\karpathy-tmp\skills\karpathy-guidelines .\
Remove-Item -Recurse -Force .\karpathy-tmp
```

Result: `%USERPROFILE%\.claude\skills\` contains `obsidian-markdown`,
`obsidian-bases`, `obsidian-cli`, `json-canvas`, `defuddle`, `karpathy-guidelines`.

## Step 4 — Wire up the Obsidian MCP server

Copy `.mcp.json` into the vault root:

```powershell
Copy-Item .\obsidian-setup\.mcp.json C:\Claude_stuff\.mcp.json
```

This tells Claude Code to start the [obsidian-mcp](https://github.com/StevenStavrakis/obsidian-mcp)
server pointed at your vault. It adds tools for searching, reading, and writing
notes directly — useful once the vault has more than ~100 files.

First run, Claude Code will prompt you to approve the MCP server. Approve it.

## Step 5 — Launch Claude Code in the vault

```powershell
cd C:\Claude_stuff
claude
```

Verify at the prompt:
- `/mcp` — should list `obsidian` as connected.
- `/` — should list the skills (`obsidian-markdown`, etc.).
- Ask "what's in CLAUDE.md?" — Claude should summarize the vault protocol.

## Step 6 — Start the daily-note habit

At the start of a session, say: **"Start the daily note for today and load yesterday's."**
At the end: **"Log this session to today's note."**

After a week or two, CLAUDE.md + the daily notes + your project notes become
genuine persistent memory across sessions.

## Optional: auto-capture on session end

If you want session summaries written automatically (without asking), add a
Stop hook to `%USERPROFILE%\.claude\settings.json` that appends to the daily
note. Skip for now — it's easy to add later once the manual workflow feels
right.

## Caveats

- **Obsidian Sync / iCloud**: if the vault is synced, avoid having Claude and
  Obsidian write the same file simultaneously. Close the daily note in
  Obsidian before asking Claude to edit it.
- **Frontmatter**: let the `obsidian-markdown` skill handle YAML — don't mix
  manual and Claude edits on the same property block.
- **Scale**: for vaults > ~500 notes, the MCP server's semantic search matters
  more. Under that, filesystem reads are fine.
