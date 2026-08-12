# All-In-Gentle — Project Context & Handoff

> Swiss Army Knife for the Gentle ecosystem: a native macOS app that gives a visual,
> readable interface to everything already running on this machine (Engram, CodeGraph,
> gentle-ai) plus two new features (Wiki + Diagrams), with an optional documented chat.

## 1. Vision

Build **All-In-Gentle**, a native macOS app (SwiftUI, no webview) that:

- **Projects tab**: lists every project known to Engram AND every CodeGraph-initialized repo.
- **Wiki tab**: for a selected project, merges Engram notes + CodeGraph symbols into
  human-readable sections (Architecture Overview, Key Modules, Decisions...) generated
  by the LLM model configured in the UI.
- **Diagrams tab**: renders the real CodeGraph structure (callers, callees, dependencies)
  natively; the LLM only organizes/narrates, the app draws.
- **Chat tab**: select files + a diagram, ask a documented question to the configured
  model API. Research/consult only — coding stays in OpenCode.
- **Readability first**: tabs, adjustable font size, zoom. This is the #1 feature.

Everything runs **locally on this machine first**. No wifi/sync/server/auth in the MVP.

## 2. Architecture Decision (MANDATORY RULES)

The app is a **CONSUMER of Engram**, never the owner:

1. **NEVER open `~/.engram/engram.db` directly** (SQLite WAL mode — corruption risk while
   `engram serve` runs). Use the HTTP API only.
2. **NEVER kill/restart `engram serve`** (port 7437). It is owned by OpenCode's ecosystem
   via LaunchAgent `com.gentleman.engram.serve`.
3. Talk to Engram over HTTP `localhost:7437` exactly like any other client.
4. CodeGraph is consumed via **CLI subprocess** (`codegraph query/explore/callers/callees/
   impact/files`) or by reading per-repo `.codegraph/codegraph.db` (read-only, repo is not
   the live writer of that DB — index daemon is; prefer CLI to be safe).
5. gentle-ai is **CLI/TUI only — there is NO `gentle-ai mcp` command** (verified).
   `gentle-ai` is invoked as subprocess for status/orchestration surfaces.
6. Diagrams: **no webview, no Mermaid** (user explicitly wants "nothing browser-like").
   Render natively from CodeGraph data (SwiftUI Canvas/Graph layout). LLM provides
   narration/grouping only.

## 3. Verified Infrastructure (paths on this machine)

### Engram — persistent memory
- Binary: `/opt/homebrew/bin/engram` — version `1.20.0`
- HTTP API server: `http://localhost:7437` (running, health verified)
  - `GET /health` → `{"service":"engram","status":"ok","version":"0.1.0"}`
  - `GET /observations` → 200 (read list)
  - `POST /observations` → write-capable. Requires `session_id`, `title`, `content`
    (verified live: returns field-required error, NOT 404). Write from app = supported.
  - `GET /search?q=...` → 200 JSON results
- Database: `~/.engram/engram.db` — 166 MB, tables: `observations`, `sessions`,
  `memory_relations`, `user_prompts`, sync tables. **DO NOT open directly while serving.**
- LaunchAgent: `~/Library/LaunchAgents/com.gentleman.engram.serve.plist`
  (starts `engram serve` at login, KeepAlive, logs `/tmp/engram.serve.{out,err}.log`)
- Scale (real): **564 sessions, 10,581 observations, 1,976 prompts, 38 projects**
- Bigger projects: `metallink` (3141 obs), `trazo-suite` (3033), `fletto-mvp` (1466),
  `nudsport` (498), `helmo 2026` (367)...

### CodeGraph — code intelligence graph
- Binary: `/opt/homebrew/bin/codegraph` — version `1.1.6`
- Per-repo index at `<repo>/.codegraph/codegraph.db` (node:sqlite built-in, full WAL)
- Indexed repos on this machine (verified via `find`):
  - `/Users/jesuslizarragapena/Documents/TRAZO-SOFTWARE/Gentle-Project/gentle-ai`
    → 947 files, 20,427 nodes, 75,217 edges, 67.35 MB
  - `trazolab-suite`, `PatitoPolitico.com`, `Mini-Tibia`, `Marros`,
    `ICR-Card-Grading`, `nudsport`, `FLETTO/fletto-mvp`, `HELMO-Project`
- CLI intelligence surface (read-only): `query`, `explore`, `node`, `files`,
  `callers`, `callees`, `impact`, `affected`, `status`
- NOTE: parent dir `Gentle-Project/` root is **NOT** CodeGraph-initialized; index lives
  in the child repo `gentle-ai`. App must define "project" per indexed repo or initialize
  what it needs.

### gentle-ai — ecosystem orchestrator
- Binary: `/opt/homebrew/bin/gentle-ai` — version `2.3.0`
- NO `mcp` subcommand. Commands: `sdd-status`, `sdd-continue`, `review ...`,
  `sdd-attempt`, `doctor`, `skill-registry refresh`, etc. (CLI/TUI only)
- `gentle-ai doctor` → healthy: gentle-ai, gga, engram, opencode, kimi all found;
  engram MCP handshake OK; disk fine (327 GB free)
- Agent config managed for: **opencode**, **kimi**

### OpenCode — the coding IDE (unchanged by this app)
- Config: `~/.config/opencode/opencode.json`
- Registered MCP servers: `chrome-devtools`, `context7`, `engram`
- Models resolved through provider config (no `models` key; runtime default models)
- Engram MCP used by agents via `engram mcp --tools=agent` (stdio, spawned on demand)

### Workspace
- App project folder: `/Users/jesuslizarragapena/Documents/TRAZO-SOFTWARE/All-In-Gentle/`
  (exists; currently only `.atl/` skill registry)
- User's main repo: `/Users/jesuslizarragapena/Documents/TRAZO-SOFTWARE/Gentle-Project/gentle-ai`
- The gentle-ai repo is the upstream project being worked on with OpenCode + Gentle.

## 4. What is NOT needed (verified / decided)

- **No DeepWiki, no Zread**: both are cloud services requiring public repos or paid
  accounts. Rejected for local/private-first requirement.
- **No RepoMapper**: it's a text-only repo-map CLI/MCP. CodeGraph already supersedes its
  value locally (real graph vs PageRank text). Rejected.
- **No webview / Electron / Tauri**: user explicitly wants native macOS, no browser tech.
  SwiftUI only.
- **Chat is not a coding replacement**: research/consult/wiki chat. Coding stays in
  OpenCode. The chat may call the same LLM API the user already pays for.

## 5. MVP Scope (recommended order)

1. **App shell (SwiftUI, macOS)** — TabView with: Projects, Wiki, Chat. Adjustable font
   size + zoom in a settings/read view. Native window.
2. **Projects tab** — list Engram projects (via HTTP `GET /observations`/CLI `projects
   list`) + CodeGraph-indexed repos (detect `.codegraph/`). Select one.
3. **Wiki tab** — for selected project: read Engram notes (HTTP search/filter) + CodeGraph
   symbols (CLI `query`/`files`); ask configured LLM to organize into wiki sections.
4. **Chat tab (v2)** — pick files + diagram context, ask model, show documented answer.
5. **Diagrams (v3)** — native render of CodeGraph callers/callees for a symbol.

Phase 2+: write memories to Engram from the app (POST supported), diagram tab, wifi mode
(app as localhost server + client apps — same pattern Engram already uses).

## 6. LLM API decision (open)

- User OK with using an API key for chat. Choose provider in the UI at runtime
  (DeepSeek/Claude/whatever). API key stored locally (Keychain recommended).
- Wiki + diagrams also use this model for generation/organization.

## 7. First technical steps when starting work

1. `cd /Users/jesuslizarragapena/Documents/TRAZO-SOFTWARE/All-In-Gentle`
2. Initialize SwiftUI macOS app (Xcode project or Swift Package + xcodegen). Native target
   macOS 14+ (modern SwiftUI: TabView, NavigationSplitView, ScrollView zoom).
3. Create a tiny `EngramClient` (URLSession → `localhost:7437`): health, list observations
   by project, search, POST new observation (later).
4. Create a `CodeGraphClient` (Process → `codegraph` CLI): status, files, query, callers,
   callees, impact. Parse JSON output.
5. Create `ProjectRegistry`: merge Engram projects + `.codegraph/`-detected repos.
6. Create `WikiGenerator` + `DiagramRenderer` + `ChatService` (LLM API abstraction).
7. Follow the Mandatory Rules in section 2 for every Engram/CodeGraph touchpoint.

## 8. Contacts & memory

- Engram topic for this project: `all-in-gentle-app/vision` (observation #10575,
  project `gentle-ai`) — holds the validated vision + learned gotchas.
- Session language: Spanish (Rioplatense). Technical artifacts default to English.
