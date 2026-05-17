# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

鸵鸟 OstrichApp v2 — an iOS SwiftUI client + Convex (TypeScript) backend for an AI-mediated stranger-social app. The 鸵鸟 ("ostrich") is a 24/7 backend agent driven by Claude Sonnet 4.7; the iOS app is purely a renderer + input layer. All "ostrich life" logic (wandering, encounters, memory, reflection) runs as Convex scheduled jobs whether or not the iOS app is open. Current phase: investor demo (Phase 1).

The architectural source of truth is `docs/`, not the code — `docs/BLUEPRINT.md` covers product + system design, `docs/INTERFACES.md` is the wire contract between iOS and Convex (and is frozen via RFC PR), and `docs/DECISIONS.md` has ADRs explaining non-obvious choices. Read these before designing or refactoring.

## Top-level layout

- `ios/` — Swift 5.10 + SwiftUI (iOS 17+). XcodeGen-driven; `.xcodeproj` is **not** in git (see ADR-005).
- `convex/` — Convex backend (`*.ts`). HTTP router in `http.ts`; LLM wrapper + tool schema in `claude.ts`; DB schema in `schema.ts`; cron registry in `crons.ts`.
- `shared/` — non-code shared assets: 16 egg personality prompts under `shared/eggs/NN_archetype.md`, system prompt templates under `shared/prompts/`, reference HTML/JSX prototypes under `shared/reference/` (read-only).
- `tests/convex/` — vitest unit tests for the Convex backend (env: `edge-runtime`).
- `scripts/check-dto-alignment.sh` — warns when `convex/schema.ts` ↔ `ios/.../DTO.swift` drift (exit 0, advisory only).

## Common commands

Root install: `pnpm install` (pnpm 10.20.0 is pinned via `packageManager`).

### Convex (TypeScript)

```bash
pnpm lint                # ESLint over convex/ + tests/
pnpm format              # Prettier write
pnpm format:check        # Prettier check (CI runs this)
pnpm typecheck           # tsc --noEmit
pnpm test                # vitest run
pnpm test:watch          # vitest watch
pnpm vitest run tests/convex/chat.test.ts          # single test file
pnpm vitest run -t "sends message"                 # single test by name

npx convex dev           # live dev deployment + watch
npx convex env set KEY VALUE     # set deployment env var
npx convex run <function>        # manually invoke a function
```

### iOS (Swift)

```bash
brew install xcodegen swiftlint   # one-time

cd ios && xcodegen generate       # MUST run after clone and after editing project.yml
open OstrichApp.xcodeproj         # or use xcodebuild below

# Build (CI uses this; no code signing in CI)
xcodebuild build \
  -project ios/OstrichApp.xcodeproj \
  -scheme OstrichApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

swiftlint --strict                # what CI enforces
swiftlint --fix                   # auto-fix subset
```

### DTO contract

```bash
./scripts/check-dto-alignment.sh  # warns on schema.ts ↔ DTO.swift field-name drift
```

## Architecture you must internalize

**iOS↔Convex transport.** No Convex Swift SDK — iOS hits Convex's auto-exposed HTTP endpoints (`POST /api/run/<fn>`) via `URLSession` + polling, with cadence specified in `docs/INTERFACES.md §8` (chat: 3s, wander local: 2s, etc.). Rationale + reevaluation timing in ADR-001. Do not introduce WebSocket/SSE without revisiting that ADR.

**The wire contract is frozen.** `docs/INTERFACES.md` defines HTTP routes, DTO shapes, error codes, polling cadence, the 6 LLM tool schemas, and the 5-layer system prompt assembly order. Once frozen, modifying it requires an RFC PR labeled `lock/shared-file` that merges before any implementation PR follows. Swift `Codable` structs in `ios/OstrichApp/Networking/DTO.swift` are hand-mirrored from `convex/schema.ts`; field names are strictly camelCase and timestamps are ISO-8601 strings.

**LLM provider abstraction (ADR-007).** `convex/claude.ts` reads `LLM_PROVIDER`:
- `anthropic` (default) → Anthropic SDK, model `claude-sonnet-4-7`
- `deepseek` → OpenAI SDK with `baseURL=https://api.deepseek.com/v1`, model `deepseek-chat`, requires `DEEPSEEK_API_KEY`

The `ostrichTools` array in `claude.ts` is Anthropic-shape and is **the source of truth**. The DeepSeek path converts to OpenAI function-calling format inline; downstream consumers (e.g. `chat.ts`) see a unified `{ toolName, args }` shape. When editing tools, edit `ostrichTools` and keep both paths' parse logic in sync.

**Five-layer system prompt** (assembled in `convex/lib/prompts.ts::buildSystemPrompt`): world (`shared/prompts/world.md`) → egg personality (`shared/eggs/NN_*.md`, keyed by `ostrich.eggType` 1..16) → user basics (name/MBTI/zodiac/days together) → relationship graph summary (top 8 active people) → memory recall (recency/importance/relevance weighted, top 15). See `docs/INTERFACES.md §5`.

**Cron schedule** lives in `convex/crons.ts` and is specified in `docs/INTERFACES.md §6`. Demo mode runs `tickAllOstriches` at 10s; production should be 1min — do not commit demo cadence as the default.

## Build/test gotchas

- **Run `xcodegen generate` after pulling** if `ios/project.yml` changed. `.xcodeproj` is gitignored (ADR-005) so multiple workstreams don't fight over `project.pbxproj`.
- The iOS app's `PRODUCT_NAME` is the Chinese string `鸵鸟`, but `PRODUCT_MODULE_NAME` is explicitly forced to `OstrichApp` (ASCII) so `@testable import OstrichApp` works. Don't "fix" this. The test target's `TEST_HOST` correspondingly hard-codes `$(BUILT_PRODUCTS_DIR)/鸵鸟.app/鸵鸟`.
- Bundle id is `com.ostrich.v2`; the app declares the WeatherKit entitlement (`OstrichApp.entitlements`).
- `convex/schema.ts` is in `.prettierignore` on purpose — its hand-formatted multi-line layout must not be auto-compressed (CODE_STYLE.md).
- Vitest runs in `edge-runtime` (mimics the Convex runtime); `tests/convex/global-setup.ts` is the entry. Don't add Node-only imports to tests without checking.
- CI workflows are path-filtered (`ios/**`, `convex/**`, `shared/**`) and concurrency-grouped. SwiftLint runs with `--strict` — warnings fail the build. Prettier-check on `convex/**/*.ts` also blocks merge.

## Code style (enforced)

- TypeScript: `pnpm lint` + `pnpm format:check` must pass. `@typescript-eslint/no-explicit-any` and friends are intentionally off — Convex codegen and generic helpers need `any`. Prefer relaxing a rule over rewriting business logic.
- Swift: `swiftlint --strict` must pass. Long lines, deep nesting, large bodies are deliberately allowed (Chinese comments + SwiftUI chains regularly exceed normal limits). The opt-in extras worth knowing: `force_unwrapping`, `empty_count`, `empty_string`, `first_where`.

## Sub-agent / worktree workflow (ADR-006)

When spawning parallel sub-agents to work on different workstreams, use **manual git worktrees**, not the Agent tool's built-in `isolation: "worktree"`:

```bash
git worktree add ../OstrichApp_v2_ws_X -b ws-X/topic main
# sub-agent cd's into ../OstrichApp_v2_ws_X, commits, pushes, opens PR
git worktree remove ../OstrichApp_v2_ws_X   # after PR merges
```

Each worktree shares `.git` with the main checkout but has its own `node_modules` (pnpm store dedupes content). Push goes through the original remote.

## When in doubt

Consult, in this order: `docs/INTERFACES.md` (contract), `docs/BLUEPRINT.md` (full design), `docs/DECISIONS.md` (why we chose what we chose), `docs/CODE_STYLE.md` (lint baseline). The PR template (`.github/PULL_REQUEST_TEMPLATE.md`) expects you to call out which demo segment a change touches and to paste `git diff --stat` to prove the change stayed inside its workstream directory.
