# Architecture

Tallystitch is one product with three front ends — a SwiftUI iOS app, a
Next.js web app, and a React Native app — over a **single shared Supabase
backend**. This document explains the load-bearing decisions and, just as
importantly, the trade-offs they carry.

The guiding idea: **push the rules that must never be wrong into the database,
and keep the clients thin.**

---

## The system

```
   iOS (SwiftUI)      Web (Next.js)      React Native (Expo)
        │                  │                    │
        └─────────┬────────┴─────────┬──────────┘
                  ▼                   ▼
        ┌─────────────────────────────────────┐
        │  Supabase (managed Postgres + BaaS)  │
        │  • Row-Level Security (per-user)     │
        │  • Auth  (GoTrue, PKCE)              │
        │  • Edge Functions (privileged ops)   │
        │  • Business logic in the DB:         │
        │      triggers + a transactional RPC  │
        └─────────────────────────────────────┘
                  │  (web only)
                  ▼
              Stripe (billing)
```

There is **no bespoke backend server**. The database *is* the backend, and the
critical logic lives inside it so all three clients share one implementation
and physically can't drift apart on the rules that matter.

---

## Which architecture pattern — and why

**Chosen: pragmatic MVVM over a Clean-*inspired* layering, with a pure domain
core.** Not textbook Clean Architecture, and not VIPER. Here's the honest
mapping and the reasoning:

**MVVM — yes, but only where it earns its keep.** `DashboardViewModel` is a
real ViewModel: it aggregates orders into revenue/low-stock, which is logic
worth extracting and observing. The CRUD screens deliberately *skip* the
ViewModel and use `@State` + `.task` calling a service directly — a list that
fetches rows and renders them gains nothing from an extra layer except a file
to keep in sync. Dogmatic one-ViewModel-per-screen was rejected as ceremony.

**Clean Architecture — the spirit, not the ceremony.** What was kept is the
part of Clean that pays for itself: the **dependency rule**. `TallystitchCore`
(entities + domain logic) is the innermost layer and depends on nothing — no
SwiftUI, no Supabase — and everything points inward toward it. What was
deliberately *not* adopted: Use-Case/Interactor objects and protocol-abstracted
repositories. At this app's size, every boundary protocol would have exactly
one implementation — speculative abstraction that adds indirection without
adding options. Clean's known weak spot is where that ceremony concentrates:
the composition root, which ends up knowing every concrete type in the system,
and (with a DI container) moves wiring errors from compile time to runtime.
This app keeps its composition root tiny and compile-time-checked — two stores
injected via `.environmentObject` at the app entry — precisely by *not*
abstracting every seam.

**VIPER — no.** VIPER's Presenter/Interactor/Router split solves coordination
problems of large UIKit codebases with many contributors. In SwiftUI the View
already *is* a function of state, navigation is declarative, and this codebase
has one author — VIPER here would be five files per screen answering a question
nobody asked.

**The trade consciously accepted:** skipping repository protocols means the
service layer has no seam for mocks and is therefore untestable today (see
*Known trade-offs*, item 1). The domain core — the part most likely to be
wrong — is fully testable. If the app grows or gains contributors, introducing
protocols **only at the data boundary** (not everywhere) is the planned first
step, which would also make the "Clean" label fully earned rather than
"inspired."

---

## The iOS app — layers

Pragmatic **MVVM over a Clean-inspired layering**, with a pure domain core.

```
┌───────────────────────────────────────────────┐
│ Views (SwiftUI)                                │  declarative; consume stores
│  Dashboard · Materials · Products · Sales ·    │  via @EnvironmentObject;
│  Settings · Onboarding · Auth                  │  call services with async/await
├───────────────────────────────────────────────┤
│ Stores (@MainActor ObservableObject)           │  AuthStore, ProfileStore —
│  injected at the app root                      │  app-wide reactive state
├───────────────────────────────────────────────┤
│ Services (stateless enums)                     │  Materials/Products/Sales/
│  thin async wrappers over supabase-swift       │  Account — the data gateway
├───────────────────────────────────────────────┤
│ TallystitchCore  (pure Swift package)          │  Models · StockMath ·
│  ZERO UIKit/SwiftUI — unit-tested in isolation │  Formatting — the domain
└───────────────────────────────────────────────┘
             dependencies point inward ──▶
```

- **MVVM where it earns its keep.** `DashboardViewModel` aggregates orders into
  revenue/low-stock. The CRUD screens skip the ViewModel and use `@State` +
  `.task` calling a service directly — no ceremony where there's no logic.
- **The dependency rule holds for the core.** `TallystitchCore` depends on
  nothing (no SwiftUI, no Supabase), so the correctness-critical math is
  testable without a simulator and can't be tangled into a view.
- **Not full Clean / not VIPER.** There are no Interactors, Presenters, or
  protocol-abstracted repositories. That's deliberate — see *Trade-offs*.

---

## The one decision everything hangs on: stock deduction

Selling a product deducts its recipe's materials from inventory. That rule is
the correctness risk of the whole product, so it lives in **one authoritative
place** with two read-only mirrors:

| Where | Role |
|---|---|
| **Postgres trigger** (`tg_order_items_stock`) | **Authoritative.** The only thing that ever *mutates* stock, inside the transaction. |
| `stock.ts` (web) | **Projection only.** "If you import this CSV, here's what stock would look like." Never writes. |
| `StockMath.swift` (iOS) | **Projection only.** Live margin today; oversell preview when CSV import lands. Never writes. |

So it's **one source of truth + two projections**, not three competing
implementations.

**Why the DB, not the client?** Concurrency. The same account can have the web
app and the phone open at once. If a client computed stock and wrote the
result back, two clients racing would produce a lost update — one silently
overwrites the other. Only the database can serialise it, and the trigger runs
inside the same transaction as the insert, so deduction is atomic.

**Writes go through one atomic RPC.** `create_order_with_items` creates the
order, its line items, and fires every stock trigger in a single transaction —
all three clients call it, so the *write path* has exactly one implementation.
A partial network failure can't leave an order with no items or items with no
order.

**The honest cost:** the two projections can drift from the trigger. Mitigation
is a shared test suite — the Swift tests are a direct port of the web's
`stock.test.ts`. That's a mitigation, not a guarantee. The single-implementation
fix would be to expose the projection as a Postgres function and call it over
RPC, at the cost of a network round-trip on every keystroke of the preview. The
write path could afford that round-trip; the preview path chose responsiveness.

---

## Security model

The client is treated as **hostile territory** — anything in an `.ipa` can be
extracted, so nothing privileged ships in it.

- **RLS is the real authorization.** Every query is scoped to `auth.uid()` in
  Postgres. The client only ever holds the **publishable (anon) key**, which
  identifies the project but authorizes nothing on its own — it gets you to the
  door; RLS decides which rows you see.
- **Privileged ops run server-side.** Account deletion touches auth records,
  which needs the **service-role key** — the one credential you can never ship
  in an app. It runs in an **Edge Function**; the client calls it with its
  normal JWT, and the function re-derives *which* user is asking from that
  token. A client can only ever say "delete me," never "delete user X."
- **Secrets via `.xcconfig`.** `Secrets.xcconfig` is gitignored; a committed
  `.example` lets anyone clone and build. Values reach `Info.plist` at build
  time. Only the URL + anon key — never the service-role key.
- **PKCE for auth.** A mobile app is a public client (no client secret it can
  keep). The magic-link flow generates a verifier stored in the **keychain**,
  sends only its hash, and the code exchange only succeeds by presenting the
  original verifier — so an intercepted redirect code can't be redeemed by
  another app.

*(This is the same threat model an embedded SDK faces: your code runs inside
apps you don't control and can be decompiled, so anything privileged lives
behind a boundary you own.)*

---

## Known trade-offs (what I'd change)

Written down deliberately — these are conscious shortcuts, not blind spots.

1. **`SupabaseManager` is a singleton with a global `supabase` accessor.** It's
   convenient but it makes the service layer untestable — services grab a live
   client, so there's no seam to inject a fake. That's exactly why the core has
   tests and the services don't. The fix is protocol-based dependency injection:
   define repository protocols, inject them, pass mocks in tests. This is also
   the single change that would make the "Clean Architecture" claim defensible.
2. **No pagination.** `SalesService.list(limit: 200)` is a placeholder, not a
   design. A user with years of orders wouldn't see most of them.
3. **Dashboard aggregates client-side.** It fetches rows and folds them in the
   app; that should be a Postgres view or RPC — don't ship a thousand rows to
   compute one number.
4. **Three stock-math implementations.** See above — collapse to one via an RPC
   if the round-trip is acceptable.
5. **`fatalError` on missing config.** Fine for a portfolio app; unacceptable in
   a shipped SDK, where it would crash someone else's app instead of degrading.
6. **No offline handling.** Every action assumes the network is present.

---

## Verifying the core without Xcode

The domain package is dependency-free, so its logic can be checked on any Mac:

```bash
cd Packages/TallystitchCore
./Scripts/verify.sh      # compiles StockMath/Formatting + runs the assertions
```

On a Mac with full Xcode, prefer `swift test` (the complete XCTest suites).
