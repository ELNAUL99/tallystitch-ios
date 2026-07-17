# Internals — how every mechanism actually works

[ARCHITECTURE.md](../ARCHITECTURE.md) explains *what* was chosen and *why*.
This document goes one level deeper: the mechanics of each moving part, from
the database up through the SwiftUI layer, including two end-to-end traces.
It's written for a reader who wants to understand the system well enough to
change it.

---

## 1. Database layer

### Supabase = Postgres + glue

Supabase is managed PostgreSQL plus an auto-generated REST API (PostgREST),
an auth server (GoTrue), and serverless functions (Deno). When the app calls
`supabase.from("materials").select()`, that's an HTTPS request to PostgREST,
translated into SQL. Everything below is plain Postgres — the schema,
triggers, and RPCs would port to any Postgres host.

### Triggers — where the stock rule lives

A trigger is a function the database runs automatically on row changes,
**inside the same transaction** as the statement that fired it.

`tg_order_items_stock` on `order_items`:

- **INSERT** → deduct `recipe_qty × order_qty` from each material of the
  product's recipe, and snapshot the product's current unit cost onto the row.
- **DELETE** → add the stock back (this is how deleting a sale reverses
  inventory with zero application code — the FK cascade deletes the items,
  and each deletion fires the reversal).
- **UPDATE** → reverse the old line, apply the new one.

Because the trigger runs inside the transaction, the item insert and the
stock deduction are atomic: there is no moment where one happened and the
other didn't.

**BEFORE vs AFTER:** the INSERT trigger is `BEFORE` because it must modify
the row being inserted (write `unit_cost_snapshot` into it). The DELETE and
UPDATE triggers are `AFTER` — they only react.

### The atomic write path: `create_order_with_items`

All three clients create sales through one PL/pgSQL function rather than
separate inserts. Inside one transaction it:

1. **Guards identity** — `if p_user is distinct from auth.uid() then raise`.
   RLS already enforces this on the inserts; the explicit check is
   belt-and-braces and produces a clearer error.
2. **Computes gross server-side** from the line items, so a client cannot
   send a total that disagrees with the lines.
3. Inserts the order header, then all items (firing the per-row stock
   triggers), and returns the order id. Any failure aborts everything —
   an order can never exist without its items, and stock can never be
   deducted for an order that failed to land.

The function is `SECURITY INVOKER` (runs with the caller's permissions, so
RLS applies inside it). The *triggers* are `SECURITY DEFINER` because they
must update `materials` regardless of the statement's row context.

### Row-Level Security — the actual mechanism

RLS is not middleware — it is a WHERE clause the database itself appends to
every query, which the client cannot remove. Each request carries the user's
JWT; PostgREST verifies it and exposes the token's `sub` claim as
`auth.uid()` in the session. A policy like `using (user_id = auth.uid())`
means even a hostile `select * from materials` returns only the caller's
rows. This is why shipping the anon key in the binary is safe: **the key
gets you to the door; RLS decides which rows exist for you.**

The known sharp edge: RLS is opt-in per table. A new table without a policy
is a hole. Mitigations are discipline plus Supabase's advisors; at team
scale this belongs in a CI schema check.

### Foreign-key behaviors — each one deliberate

| Relation | Behavior | Why |
|---|---|---|
| `orders → order_items` | **CASCADE** | Deleting a sale deletes its lines; each deletion fires the stock-reversal trigger. |
| `recipe_items → materials` | **RESTRICT** | Can't delete a material a recipe still uses — would orphan the recipe. |
| `order_items → products` | **RESTRICT** | Can't delete a product with sales — would destroy history. |

The app translates exactly Postgres error `23503` (FK violation) into
plain-language messages ("this material is used in a recipe…") and rethrows
everything else. Catching broadly would mask network or RLS failures behind
a misleading explanation.

### Two deliberate denormalizations

1. **`products.unit_cost_cached`** — derivable from the recipe, but
   recomputing on every read means joining recipe+materials constantly.
   A trigger recomputes the cache whenever a recipe row changes *or a
   material's price changes*. Pay on write, free on read.
2. **`order_items.unit_cost_snapshot`** — the unit cost frozen at sale
   time. If dashboards used the live product cost, raising a material price
   today would silently rewrite last month's profit. Historic margins must
   not drift; this is an accounting rule expressed as a column.

### Idempotent CSV import

```sql
create unique index on orders(user_id, source, external_order_id)
  where external_order_id is not null;
```

Re-importing the same file hits the index; the importer maps `23505`
(unique violation) to "skipped duplicate" rather than failing the batch.
Idempotency — safe to retry — is a property, not a feature.

---

## 2. Auth mechanics

### JWTs

`header.payload.signature`, base64. The payload carries claims (`sub` = user
id, `exp`, `role`); the signature is an HMAC over the rest using a secret
only the server holds — so the server can verify a token wasn't tampered
with, without a database lookup. The short-lived **access token** rides on
every request (and feeds `auth.uid()`); the long-lived **refresh token** is
exchanged for new access tokens automatically by `supabase-swift`. Both live
in the **keychain** (encrypted, hardware-backed) — never `UserDefaults`,
which is a plaintext plist.

### PKCE — why and how

A mobile app is a *public client*: it cannot keep a client secret, because
anything in the `.ipa` can be extracted. PKCE replaces the secret with proof
of possession:

1. Requesting a magic link, the SDK generates a random **verifier**, stores
   it in the keychain, and sends only its **hash** (the challenge).
2. The email links to `tallystitch://auth/callback?code=...`. The custom
   scheme (registered in `Info.plist` → `CFBundleURLTypes`) reopens the app;
   SwiftUI delivers the URL via `.onOpenURL`.
3. `AuthStore.handleDeepLink` → `supabase.auth.session(from: url)` sends the
   code **plus the original verifier**. The server hashes it and compares to
   the challenge. Match → session.

Security property: an intercepted redirect code is useless to another app —
it doesn't hold the verifier, which never left the keychain. Side effect:
the link only completes on the device that requested it.

**Failure path:** an expired or reused link makes the exchange throw.
Originally that failure was silent — the app opened and nothing happened.
Now `AuthStore` captures it in `linkError` and `RootView` surfaces an alert
saying what happened and what to do. Silent failure is the worst failure.

### Password recovery

Same deep-link machinery: `resetPasswordForEmail` → emailed link reopens the
app → `authStateChanges` emits `.passwordRecovery` → `AuthStore` sets
`passwordRecovery = true` → `RootView` presents `SetNewPasswordView` as a
`fullScreenCover` → `updatePassword` uses the recovery session to set a new
password without knowing the old one.

### Signup

`signUp(email:password:)` sends the same `tallystitch://auth/callback`
redirect. With email confirmation on, the server returns **no session** —
the account exists but is unusable until the emailed confirm link is tapped,
so the form shows "check your email" instead of navigating anywhere. The
confirm link rides the same deep-link machinery as magic links; confirmation
is not a special case.

Why offer password *and* magic link: parity with web/RN (one auth story
across three clients), and each covers the other's failure mode — the magic
link rescues a forgotten password; the password works when email delivery is
slow or rate-limited.

---

## 3. iOS app mechanics

### The SwiftUI model

A view is a function of state: you never mutate the screen, you mutate state
and SwiftUI recomputes `body`. Views are cheap structs, recreated constantly —
so state needs property wrappers that give it storage outside the struct's
lifetime:

- `@State` — view-local storage surviving re-renders (form fields, `busy`).
- `@StateObject` — the view *owns and creates* a reference-type object once
  (`DashboardView`'s ViewModel). Using `@ObservedObject` here would recreate
  the object on every parent re-render and wipe its state — the classic trap.
- `@EnvironmentObject` — object injected by an ancestor (`AuthStore`,
  `ProfileStore` from the app root), visible to the whole subtree.
- `@Published` — properties on an `ObservableObject` whose changes drive
  view updates.

Views are `struct`s (throwaway descriptions, value semantics); stores are
`class`es (shared mutable state needs reference identity — every screen must
see the *same* session).

### Concurrency

- `async/await` with `Task { }` bridging sync UI events into async work.
- `async let` runs the dashboard's two fetches (orders, materials) in
  parallel instead of doubling latency.
- `@MainActor` on the stores makes "mutated published state off the main
  thread" a **compile error instead of a runtime crash** — a guarantee, not
  a discipline.
- `[weak self]` in `AuthStore.init`: the store starts a long-lived task
  iterating `authStateChanges` (an unbounded stream). A strong capture would
  create a retain cycle (task keeps store alive, store keeps task alive) and
  `deinit` — which cancels the task — would never run.
- Core models are `Sendable` (pure value types), ready for strict
  concurrency checking.

### Decoding and small idioms

- Models are `Codable` with explicit `CodingKeys` mapping Postgres
  `snake_case` to Swift `camelCase`. A renamed column with a stale key fails
  at decode time — that boundary is runtime-checked, not compile-checked.
- Services are case-less `enum`s: Swift's idiom for a pure namespace — they
  hold no state and cannot be instantiated.

### Trace 1 — app launch

1. `TallystitchApp` creates `AuthStore` + `ProfileStore` (`@StateObject`)
   and injects both via `.environmentObject`.
2. `AuthStore.init` starts a task: read the persisted session from the
   keychain (`loading → false`), then keep listening to `authStateChanges`.
3. `RootView` renders from state: loading → spinner; no session → auth flow;
   session → `.task(id: session.user.id)` refreshes the profile; then the
   gates run **in order** — access (trial/subscription) → onboarding-needed →
   tab shell. Each gate assumes the previous one passed; the ordering is the
   state machine.

### Trace 2 — recording a sale (crosses every layer)

1. `SaleFormView` holds lines in `@State`; the date comes from a native
   `DatePicker` capped at today (cannot produce an invalid or future date).
2. "Record sale" → `Task { await save() }` → client-side validation →
   `SalesService.create`.
3. The service calls `supabase.rpc("create_order_with_items", …)` over HTTPS
   with the JWT attached.
4. In Postgres, inside one transaction: identity guard → RLS → order insert →
   item inserts → BEFORE INSERT trigger per item deducts recipe materials and
   snapshots unit cost.
5. Success → `dismiss()`; the list refetches on focus. Failure → nothing
   changed anywhere, and the error lands in the form.
6. If the same account has the web app open: same RPC, same trigger — the
   two clients cannot race their way into inconsistent stock, because only
   the database ever computes it.

### The client-side stock mirror — `StockMath`

Section 1 said the stock rule lives in Postgres. Yet `TallystitchCore`
ships `StockMath` — pure Swift reimplementations of the trigger math
(`applyOrderLine`, `computeUnitCost`, `wouldOversell`, `marginPct`) carrying
the package's heaviest test suite. Today the app only calls `marginPct`
(product editor and product list); the deduction functions are used by **no
view**. That is deliberate, not dead code:

1. **Previews need the math without the write.** "What would importing this
   CSV do to stock — would anything oversell?" must be answerable *before*
   inserting a single row, and the database only computes stock as a side
   effect of writes. The mirror is the preview engine for the roadmap CSV
   importer, exactly the role the web's `stock.ts` plays there.
2. **The database rule needs tests this repo can run.** A Postgres trigger
   cannot be unit-tested from a Swift package. The mirror plus its tests is
   an executable specification of the deduction rule — `verify.sh` checks it
   with nothing but a compiler.

The price is duplication that can drift, which is why the file header pins
it to `tg_order_items_stock` and the migration it must stay aligned with.
And the mirror is never trusted to *write* — authority stays in the
database; the Swift copy only predicts.

### Profile and the access gate

`ProfileStore` fetches the `profiles` row once per sign-in, and everything
reads from it: the currency in every formatter, the business name, the
subscription fields. Hoisting it into one store (mirror of the RN
`ProfileProvider`) means a settings edit calls `refresh()` once and the
whole UI reflows together — the alternative is every screen re-querying and
briefly disagreeing after an edit.

The gate itself is two lines in core: `Access.hasAppAccess` — `active`
always passes, `trialing` passes until `trial_ends_at`, everything else is
locked. It lives in `TallystitchCore` and mirrors web/RN because a rule this
consequential must not be re-derived per client; all three must agree about
who is locked out.

Note what the gate is and is not: `LockedView` is business enforcement, not
security. A user who somehow bypassed it would still hit RLS and see only
their own rows. Data protection stays in the database; the gate only decides
whether the app is *usable*.

### Sample data — a demo that runs through the real pipeline

Settings can load a demo workshop (a candle + soap maker, the same dataset
as web/RN). `SampleData.load` inserts materials → products + recipes →
backdated orders and their items, every row tagged `is_sample = true`. The
item inserts fire the **real** stock triggers, so the sample sales deduct
stock exactly as real ones would — the demo exercises the actual pipeline,
not a mock of it.

Two decisions worth naming:

- **Direct inserts, not the RPC.** `create_order_with_items` exists to make
  a *user-initiated* sale atomic; the demo loader needs backdated
  `order_date`s and the `is_sample` tag, and a partially-loaded demo is an
  annoyance, not a corruption risk — so plain inserts keep it simple. (This
  also shows the RPC's server-computed gross is a property of that path, not
  a table constraint: the loader writes `gross_amount` itself.)
- **A flag, not a sandbox.** Tagging rows instead of using a separate demo
  account means the demo renders in the user's real dashboard, and removal
  is three deletes filtered on the flag. Their order — orders → products →
  materials — is forced by the FK design in section 1: RESTRICT forbids
  deleting products that have sales or materials still in recipes, so orders
  must go first; and deleting them fires the reversal trigger, so clearing
  the demo restores stock as a side effect.

Why it exists at all: an empty dashboard teaches nothing. The demo hands a
new user a working system to poke at — real triggers, real margins — and
one tap removes it without touching anything they created themselves.

---

## 4. Build system

- **XcodeGen**: `.xcodeproj` is machine-generated XML — unreviewable diffs,
  merge-conflict bait. `project.yml` is the diffable source of truth;
  `xcodegen generate` produces the project.
  - Hard-won detail: XcodeGen regenerates `Info.plist` from the `info:`
    section on every generate. Custom keys (URL scheme, `SUPABASE_*`) that
    live only in the plist file get wiped — they must be declared in
    `project.yml`. (Learned by losing them.)
- **Secrets**: `Secrets.xcconfig` (gitignored; `.example` committed) →
  build settings → substituted into `Info.plist` → read via `Bundle.main`.
  Only the URL and the publishable key — never the service-role key.
  xcconfig quirk: `//` starts a comment, so URLs use the `https:/$()/`
  escape.
- **SwiftPM**: `TallystitchCore` is a local package; `supabase-swift` comes
  from SPM. The package's platform floor (macOS 12) is what allows
  `Scripts/verify.sh` to compile and check the core with bare `swiftc` on a
  machine that has no Xcode — the runner exists because Command Line Tools
  ship no XCTest, and unverified stock math was not an acceptable
  alternative.

---

## 5. Cross-cutting decisions

- **Why no custom backend:** one maintainer, three clients. Rules live in
  the database — closer to the data, shared by every client, no server to
  operate. Escape hatch: it's plain Postgres.
- **Why billing is web-only (for now):** scope, plus App Store policy —
  digital subscriptions sold in-app must go through Apple IAP; linking out
  to external checkout from inside the app risks rejection. The compliant
  native path (StoreKit 2 / RevenueCat) is on the roadmap.
- **Edge Function for account deletion:** deletion touches auth records and
  needs the service-role key, which must never ship in a client binary
  (anything in an `.ipa` can be extracted). The function verifies the
  caller's JWT and re-derives *who* is asking — a client can only ever say
  "delete me," never "delete user X."
- **Dashboard limitation (known):** the lean mobile query doesn't select
  `unit_cost_snapshot`, so the headline is revenue-focused; full
  cost-of-goods aggregation belongs in a Postgres view/RPC rather than
  shipping rows to the client — see *Known trade-offs* in ARCHITECTURE.md.
