# All-In-Gentle

Native macOS viewer for the local Gentle ecosystem — one readable window into everything already running on this machine: **Engram** (persistent memory), **CodeGraph** (code intelligence), **OpenCode** (sessions & token usage), and **gentle-ai** (orchestration).

Local-first by design: no webview, no cloud, no sync. The app is a **consumer** — it talks to services already running on your machine over HTTP and CLI, and never owns them.

## Features

| Tab | What it gives you |
| --- | --- |
| **Projects** | Unified list of every project known to Engram, CodeGraph, OpenCode, and OpenSpec — with source badges and per-project detail. |
| **Wiki** | For a selected project: Engram memories + OpenSpec documents in one place, with a Markdown preview. |
| **Services** | Live health dashboard: Engram, CodeGraph, gentle-ai, OpenCode — status, PID, port, uptime, and surfaced errors. |
| **Tokens** | Token usage and estimated cost per project/session, paginated, searchable. |
| **Chat** | Consult your configured LLM with project context; session management with rename/delete/stop. |
| **Session Cleaner** | OpenCode sessions grouped by project with token/cost totals. |

Plus: first-launch onboarding, provider settings (Keychain-backed API key), cross-tab project context, and global search.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘6` | Switch tabs |
| `⌘K` | Focus global search |
| `⌘B` | Toggle sidebar |
| `⌘⇧B` (menu) | Show/hide sidebar via View menu |

## How it connects

| Service | How the app consumes it | Port |
| --- | --- | --- |
| Engram | HTTP API (`localhost:7437`) | 7437 |
| CodeGraph | CLI subprocess (`query`, `explore`, `callers`, `callees`, `impact`) | — |
| OpenCode | SQLite DB read-only (`~/.local/share/opencode/opencode.db`) | — |
| gentle-ai | CLI subprocess | — |

## Safety rules (non-negotiable)

The app is a **consumer of Engram, never the owner**:

- **Never open `~/.engram/engram.db` directly** — SQLite WAL mode; corruption risk while `engram serve` runs. Use the HTTP API only.
- **Never kill or restart `engram serve`** — it is owned by OpenCode's ecosystem via LaunchAgent `com.gentleman.engram.serve`.
- **No webview** — native SwiftUI only (no Mermaid, no browser-like rendering).
- **OpenCode database is read-only** for this app.

## Requirements

- macOS 15+
- Swift 6
- Running local services: `engram serve` (port 7437), `codegraph` CLI, `gentle-ai` CLI

## Build & Run

```sh
swift build
open .build/release/All-In-Gentle.app
```

For a full release bundle (tests → release build → packaging → signing):

```sh
scripts/build-app.sh
open .build/release/All-In-Gentle.app
```

Set `ALL_IN_GENTLE_SKIP_SIGN=1` to skip code signing for local use.

## Test & Lint

```sh
swift test
swift format lint -r --strict --configuration .swift-format Sources Tests
```

The lint gate is strict: zero findings. Tests are hermetic (no live OpenCode DB, no live Engram server — `MockURLProtocol` for HTTP clients).

## CI

GitHub Actions on a `macos-15` runner (see `.github/workflows/ci.yml`):

1. `swift build`
2. `swift test`
3. `swift format lint` (strict)
4. `scripts/build-app.sh` → uploads `All-In-Gentle.app` as a build artifact

## Project structure

```
Sources/
├── AllInGentle/
│   ├── App/            # App shell, RootView, onboarding, Launcher
│   ├── Clients/        # EngramClient (HTTP actor), CodeGraphClient,
│   │                   # OpenCodeClient, OpenSpecScanner, ProcessMonitor
│   ├── DesignSystem/   # AG* components: colors, typography, spacing, buttons, states
│   ├── Features/       # One folder per tab: Projects, Wiki, Chat, Services,
│   │                   # Tokens, SessionCleaner + Settings + Onboarding
│   ├── LLM/            # Provider abstraction: DeepSeek, provider switcher
│   ├── Models/         # Project, TokenUsage, ChatMessage, SessionSummary...
│   ├── Persistence/    # Preferences, Keychain, migrations
│   └── State/          # AppState — cross-tab context (selected project, global search)
└── AllInGentleApp/     # @main entry point
```

Architecture: each feature owns a `ViewModel` (`@Observable`), views are passive, and `AppState` carries the shared context (selected project path + global search query) across every tab.

## Contributing

Conventional commits only (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `style:`, `ci:`, `refactor:`). Stage by explicit path — never `git add -A` when untracked tooling files are present. No AI attribution in commits.
