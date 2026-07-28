# Monetization test plan (Studio)

Everything below is currently inert on purpose: `src/shared/config/ProductsConfig.luau` ships with `productId = 0` and `passId = 0`, and every code path checks `ProductsConfig.isConfigured(...)` before prompting. With ids at 0 the game silently falls back to the free Continue, so nothing breaks before the products exist.

## 1. Create the products (Creator Dashboard, done by the owner)

| Item | Type | Suggested price | Where the id goes |
| --- | --- | --- | --- |
| Continue | Developer Product | 49 R$ | `ProductsConfig.products.Continue.productId` |
| VIP | Game Pass | owner's choice | `ProductsConfig.passes.VIP.passId` |
| Supporter Pack | Game Pass | owner's choice | `ProductsConfig.passes.Supporter.passId` |

Developer Products live under the experience → Monetization → Developer Products. Game Passes under Monetization → Passes. Copy the numeric id from the URL of each item's page and paste it into `ProductsConfig`.

Both passes are cosmetic-only by design (`cosmeticOnly = true`). Credits, weapons, weapon upgrades, skills and perk slots must never be sold for Robux — that rule is in `CLAUDE.md` and is the reason `MonetizationService` has no credit-granting handler.

## 2. Enable Studio purchase testing

In Studio: **Game Settings → Security → Enable Studio Access to API Services** must be on (it also enables real DataStores, which `ProfileManager` probes for). Purchases prompted in Studio use the test flow and do not charge Robux for the place owner.

## 3. Test cases

### 3.1 Continue happy path
1. Start a run, let a zombie kill you.
2. On the results screen the right button should read `Continue  49 R$` (it reads plain `Continue` while `productId` is 0).
3. Press it → the Roblox purchase prompt appears.
4. Confirm → you respawn at the death position with a short ForceField, zombie lure cleared, and the death UI closes.

Expected server behaviour: `DeathService.grantContinue` runs from `MonetizationService`'s grant handler, not from the client message.

### 3.2 Continue cancelled
Press Continue, then dismiss the Roblox prompt. Nothing should happen: no revive, no credits spent, the results screen stays open and `Return to base` still works.

### 3.3 One revive per run
Continue once, die again in the same run. The Continue button must no longer revive you — the server returns you to the hub (`REVIVES_PER_RUN = 1` in `DeathService`). Verify the counter resets when you start a fresh run.

### 3.4 Receipt idempotency
This is the case that costs real money if it is wrong.
1. Buy Continue.
2. Check the profile's `PurchaseHistory` contains the `PurchaseId` key (add a temporary `print` in `MonetizationService.processReceipt`, or inspect via a command-bar `ProfileManager.get(player)`).
3. Force a re-delivery: leave and rejoin during the purchase, or kill the server session mid-grant. Roblox re-calls `ProcessReceipt` for an ungranted receipt.
4. The second call must return `PurchaseGranted` immediately from the `PurchaseHistory` short-circuit and must NOT revive again.

### 3.5 Profile not loaded
Prompt a purchase in the first second after joining, before the profile session starts. `processReceipt` must return `NotProcessedYet` (never `PurchaseGranted`), so Roblox retries later instead of the player losing Robux.

### 3.6 Game pass ownership cache
With a pass id filled in, call `MonetizationService.ownsPass(player, "VIP")` twice from the command bar. The second call must return from cache (no second web call within `PASS_CACHE_TTL = 120` seconds). Then simulate a failure by disabling network access — after three retries the call must return the cached value if there is one, and `false` otherwise, never error.

### 3.7 Unknown product
Temporarily point `ProductsConfig.products.Continue.productId` at an id that is not in the config and buy it. `processReceipt` must warn and return `NotProcessedYet` rather than granting anything.

## 4. Two-client check

Run a two-player Studio test (Test → Clients and Servers → 2 players). Kill player A only. Player A's Continue prompt must not affect player B's run, and player B's results screen must show their own numbers.

## 5. After the ids are live

Re-run 3.1 through 3.5 in a published place with a non-owner account, because Studio purchase testing does not exercise the real receipt pipeline end to end.
