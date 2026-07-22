# Walkthrough — the five-minute tour

**Tallystitch** answers one question for handmade sellers: *what's my real
margin?* Track materials, define product recipes, log sales — stock deducts
itself and the margin is always live. Web version: <https://tallystitch.vercel.app>

This repo is the **native SwiftUI iOS client**. Web (Next.js) and React
Native clients share the same backend.

## The system in one diagram

```
 iOS (SwiftUI)   Web (Next.js)   React Native
       └──────────────┼──────────────┘
                      ▼
      Supabase — managed Postgres + auth
      the rules live IN the database:
      triggers, one atomic RPC, RLS
```

No custom backend. The rules that must never be wrong are in Postgres, so
three clients can't drift apart on them.

## Repo map

```
Packages/TallystitchCore/   pure Swift domain (models, StockMath, Formatting)
                            — zero UI/network deps, all the tests live here
  Scripts/verify.sh         runs core checks with just swiftc (no Xcode needed)
Tallystitch/
  Services/                 thin async wrappers over supabase-swift
  App/  Theme/  Views/      SwiftUI: auth, tab shell, dashboard, CRUD screens
project.yml                 XcodeGen source of truth (generates .xcodeproj)
```

**Architecture in one line:** pragmatic MVVM over a Clean-*inspired* layering
— the dependency rule holds (core depends on nothing), but no Interactors and
no repository protocols, deliberately.

## Five decisions, one line each

1. **Stock deduction lives in a Postgres trigger** — one authoritative
   implementation; the Swift/TS copies are read-only projections for previews.
2. **Sales go through one atomic RPC** (`create_order_with_items`) — order +
   items + stock changes commit or roll back together, on all three clients.
3. **The client is hostile territory** — only the publishable key ships;
   RLS does authorization; account deletion runs in an Edge Function holding
   the service-role key server-side.
4. **Unit cost is snapshotted onto each sale** — historic margins can't drift
   when today's material prices change.
5. **PKCE + keychain for auth** — magic links reopen the app via
   `tallystitch://`; an intercepted code is useless without the verifier.

## Run it

```bash
brew install xcodegen
cp Tallystitch/Config/Secrets.example.xcconfig Tallystitch/Config/Secrets.xcconfig  # fill in
xcodegen generate && open Tallystitch.xcodeproj    # ⌘R (Xcode 16+, iOS 16+)

# core logic check, no Xcode required:
Packages/TallystitchCore/Scripts/verify.sh
```

## Read more

| Doc | Depth |
|---|---|
| [README](../README.md) | status + setup |
| [ARCHITECTURE](../ARCHITECTURE.md) | what was chosen, why, and the known trade-offs |
| [INTERNALS](INTERNALS.md) | how every mechanism works + two end-to-end traces |
