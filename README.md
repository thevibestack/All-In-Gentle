# All-In-Gentle

Native macOS viewer for the local Gentle ecosystem: Engram (HTTP API), CodeGraph (CLI), and gentle-ai (CLI).

## Prerequisites

- macOS 15+
- Swift 6

## Build

```sh
swift build
```

## Test

```sh
swift test
```

## Lint

```sh
swift format lint -r --strict --configuration .swift-format Sources Tests
```

## Package

```sh
scripts/build-app.sh
```

Builds the release bundle at `.build/release/All-In-Gentle.app`. Run with tests first (`swift test`), then `swift build -c release`, then codesign (skip with `ALL_IN_GENTLE_SKIP_SIGN=1`).

## Run

```sh
open .build/release/All-In-Gentle.app
```
