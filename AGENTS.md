# All-In-Gentle — Coding Standards

Native macOS SwiftUI app (macOS 15+) that gives a readable interface to the local Gentle ecosystem: Engram (HTTP API), CodeGraph (CLI), gentle-ai (CLI), OpenCode.

## Commands

- Build: `swift build`
- Test: `swift test`
- Lint (strict): `swift format lint -r --strict --configuration .swift-format Sources Tests`
- Format: `swift format format -i -r --configuration .swift-format Sources Tests`
- Package app bundle: `scripts/build-app.sh`

## Rules

- Swift 6, SwiftUI, no webview. Local-first: never open `~/.engram/engram.db` directly, never kill `engram serve`, never invoke a nonexistent `gentle-ai mcp`.
- Follow the project's `.swift-format` configuration (4-space indent, 120 columns). The lint gate is strict: zero findings.
- Tests must be hermetic: no live OpenCode DB, no live Engram server. Use `MockURLProtocol` for HTTP clients.
- Conventional commits only: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `style:`, `ci:`, `refactor:`.
- Stage by explicit path. Never `git add -A` when untracked files (`.gga`, `elcome1p`, `elcome2p`) are present.
- Do not add AI attribution ("Co-Authored-By") to commits.
