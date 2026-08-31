# Game Design Document
*(Living document — built iteratively for Cursor AI-assisted development)*

---

## Section 5: Master Technical Performance & Optimization Directives

This section defines the mandatory technical architecture for all script generation. Any code created by Codex that violates these parameters must be refactored immediately.

### 1. Engine Execution & Typing Standards
- **Compiler Optimization Flags:** Every script and ModuleScript must begin with:
  ```lua
  --!strict
  --!native
  ```
  *Note: reserve `--!native` for math-heavy/algorithmic modules (pathfinding, projectile math, damage calc). Skip it on simple UI/event-wiring scripts where it adds compile/memory overhead with no payoff.*
- **Modern Task Library:** Raw global timing methods are forbidden.
  - Forbidden: `wait()`, `delay()`, `spawn()`, `coroutine.resume()`.
  - Mandatory: `task.wait()`, `task.delay()`, `task.spawn()`, `task.defer()`.
- **Generalized Iteration:** Do not use `pairs()` or `ipairs()`. Use `for index, value in array do`.
- **Array Pre-allocation:** Use `table.create(capacity)` for tables with predictable size.

### 2. Event-Driven Architecture (Zero-Polling Rule)
- **No Active Loops:** `while true do task.wait() end` polling patterns are banned.
- **Signal-Driven State:** Logic must sleep until woken by a signal:
  - `:GetPropertyChangedSignal("PropertyName")` for engine objects.
  - BindableEvents or custom signal modules for non-instance variables.

### 3. Parallel Luau (Multithreading Container Rules)
- **Thread Splitting:** Heavy algorithmic work (multi-raycast validation, pathfinding, regional bounds scanning) must desynchronize from the main thread.
- **Safety Pipeline:**
  ```lua
  task.desynchronize()
  -- Pure math/data only: Raycasts, Distance Vector Math, line-of-sight checks
  -- NO Instance property access or mutation while desynchronized
  task.synchronize()
  -- Safe to mutate player health, Instances, etc. here
  ```

### 4. StreamingEnabled Workspace Architecture
- `StreamingEnabled = true` is set on `Workspace.$properties` in `default.project.json` (Rojo-synced) to protect mobile/low-end hardware.
- `StreamingMinRadius` is set to **256** studs in `default.project.json`, matching the client presentation cutoff (`LootPresentationConfig.PRESENTATION_DISTANCE_STUDS`) so content within nametag/spin presentation range is never streamed out mid-interaction.
- `StreamingTargetRadius` is set to **1024** studs in `default.project.json` — the radius Roblox tries to keep loaded around the camera when performance allows (ceiling, vs. `StreamingMinRadius`'s guaranteed floor).
- `StreamingPauseMode` / `ModelStreamingBehavior` are left at engine defaults — no tuned values are specced yet. Flagging as an open question (see Section 1.6-style open items) rather than inventing numbers; revisit once real per-zone geometry size / player density data exists.
- **No Asset Assumptions:** Never assume Workspace geometry exists on the client via raw dot notation.
- **Safe Retrieval:** Use `:WaitForChild("Name", 5)` (5s default timeout) with fallback handling.
- **Dynamic Tag Tracking:** Use CollectionService (`:GetInstanceAddedSignal()`, `:GetInstanceRemovedSignal()`) to track streamed player characters instead of hardcoded tables.

#### 4.1 Distance-gated client loot presentation

Client loot handlers (`LootSpinHandler`, `LootVfxHandler`, `LootNametagHandler`) only bind presentation within **`PRESENTATION_DISTANCE_STUDS` (256)** of the local character, debounced on movement via `ClientPresentationDistance`. Movement refresh must sample `HumanoidRootPart` on `Heartbeat` — `GetPropertyChangedSignal("Position")` does not fire for Humanoid / physics walking, so far-spawned loot would never retry bind when the player walks into range:

| System | Within 256 studs | Beyond 256 studs |
| --- | --- | --- |
| Loot spin (`LootSpinHandler`) | Spin + bob active | Stopped; loot model stays visible if streamed in |
| Loot VFX (`LootVfxHandler`) | VFX anchor parented | Not bound |
| Loot nametags (`LootNametagHandler`) | Billboard enabled | Not bound |

- Constants live in `LootPresentationConfig.luau`; motion tuning in `LootSpinConfig.luau` (placeholder until GDD 1.5 specced).
- **Nametag distance cutoff matches spin's exactly:** `BillboardGui.MaxDistance` is a Roblox engine property measured from the **camera**, not the character, so `LootNametagHandler` cannot rely on it alone as the presentation cutoff (it would drift from the character-distance-based cutoff `LootSpinHandler` uses, which has no engine-level distance property at all). `LootPresentationConfig.MAX_VISIBLE_DISTANCE_STUDS` is therefore set well above `PRESENTATION_DISTANCE_STUDS` (4x) purely as a camera-side safety net; the actual show/hide cutoff is `LootNametagHandler`'s own character-distance `Enabled` toggle at the same 256-stud `PRESENTATION_DISTANCE_STUDS` spin uses.
- **Out-of-range loot is deferred, not warned** — handlers retry when the player moves closer; warnings only fire once for nearby loot that still lacks a PrimaryPart after the wait timeout.
- **Slow-streaming loot self-heals:** if a loot model's PrimaryPart/NametagAnchor hasn't replicated yet when the wait timeout elapses, the handler re-arms the same wait (indefinitely, every wait-timeout interval) instead of giving up — it only warns once per model, but keeps retrying so presentation still activates once the geometry finishes streaming, without requiring the player to move or respawn.
- **Atomic streaming:** each loot pickup `Model` uses `ModelStreamingMode = Atomic`, set in `LootPool.prepareTemplateModel`, so parts replicate together when the model streams in.
- **Loot spin implementation:** client-local `Workspace:BulkMoveTo` on `PrimaryPart` — one batch per `RenderStepped` frame while any nearby loot is spinning. Do **not** use client-side physics (`AngularVelocity` / unanchoring) on server-anchored loot; it has no visible effect. `Model:PivotTo` / per-part CFrame writes from LocalScripts do not replicate.
- **Studio loot templates** (`ReplicatedStorage.Assets.Loot/<ItemId>`): at least one `BasePart` descendant; a part named `PrimaryPart` (recommended); `Model.PrimaryPart` set; `NametagAnchor` Attachment for nametags; flat hierarchy (mesh parts as direct children) so `LootPrefabSetup` welds correctly.

### 5. Network Throttling & Payload Restrictions
- **"Server is Blind" Rule:** Server handles authoritative logic/vector math only — never visuals, tweens, UI, or audio.
- **Delta-Only Messaging:** RemoteEvents send only small packets (Instance references, Enum integers, action strings) — never full tables or high-frequency position data.
- **Rate Limiting:** Every incoming client RemoteEvent call is tick-checked (e.g. max 5 requests/sec/user) to block macro exploits.

### 6. Memory Hygiene & Object Pooling
- **Garbage Collection:** Every non-permanent `:Connect()` is tracked and explicitly `:Disconnect()`'d on cycle reset.
- **High-Frequency Instantiation Ban:** No repeated `Instance.new()` + `:Destroy()` for lasers, impacts, floating combat text, or breakable debris.
- **Pre-allocated Pools:** A master Object Pooler Module in `ReplicatedStorage` instantiates visual parts once at load; properties (CFrame, Transparency, CanCollide) are toggled to recycle parts from/to an off-screen storage vector.
- **Breakable Object / Debris Pooling:** Pool by generic fragment *type* (small shard, medium chunk, large chunk) rather than per-object dedicated pools. Any breakable obstacle re-skins/resizes a generic fragment via CFrame, Size, and texture rather than requiring its own pre-fractured pooled model.

### 7. Enforcement & Self-Audit Protocol

*Added after the August 2026 memory-leak audit of ObstacleManager and ObstacleShrinkHandler. Cursor generated code that violated Section 6 despite Section 6 existing — stating a rule as prose is not sufficient to make a model check its own output against it. This section exists to close that gap with concrete negative examples and a mandatory self-check step, rather than another abstract principle.*

#### 7.1 Why this section exists

Stating "track and disconnect every connection" as a principle is not sufficient — a model generating code pattern-matches against how similar code is usually written, not against this document line-by-line. Compliance requires (a) concrete negative examples of the *specific shapes* that count as violations, and (b) a mandatory self-check step that runs on every generation, not an optional one a human has to remember to request.

#### 7.2 Named anti-patterns (with real examples)

**A. Closure capture of a long-lived Instance.**
A connection or loop that outlives a single call must close over an `id` (`player.UserId`, an obstacle's unique attribute, etc.), never the `Player` or `Model` instance itself — even if the instance is still valid when the closure is created, holding it directly keeps it reachable for the life of the connection and couples cleanup to the connection's lifetime instead of the reverse.

```lua
-- BAD: closure holds the full Player for the connection's lifetime
RunService.Heartbeat:Connect(function()
    processPlayerRadiusDamageTick(player)
end)

-- GOOD: closure holds only the id; re-resolves and bails if the player left
local userId = player.UserId
RunService.Heartbeat:Connect(function()
    local currentPlayer = Players:GetPlayerByUserId(userId)
    if currentPlayer == nil then return end
    processPlayerRadiusDamageTick(currentPlayer)
end)
```

**B. Connections scoped to something narrower than PlayerRemoving.**
A connection made on `CharacterAdded` (or any per-respawn, per-obstacle, per-session scope) must be torn down on the matching narrower lifecycle event (`CharacterRemoving`, obstacle reset, session end) — not left to only `PlayerRemoving` or implicit Instance-destroy cleanup. "It gets cleaned up eventually" is not the same as "it's torn down at the right boundary."

```lua
-- BAD: no explicit teardown narrower than PlayerRemoving
character.DescendantAdded:Connect(function(descendant) ... end)

-- GOOD: stored per-scope, disconnected at the matching boundary
local connections: { [number]: RBXScriptConnection } = {}
connections[player.UserId] = character.DescendantAdded:Connect(function(descendant) ... end)
-- ...and in a CharacterRemoving handler:
connections[player.UserId]:Disconnect()
connections[player.UserId] = nil
```

**C. Redundant connections doing the same job.**
Before scheduling a one-shot callback (`task.defer`, a self-disconnecting `Heartbeat:Connect`, `task.delay`), check whether a prior one for the same (player, purpose) key is still pending and cancel it first. Don't schedule two mechanisms to do the same thing "to be safe" — that doubles the live-connection count under rapid repeated calls.

**D. `Completed`/`Ended`/similar one-shot signals wired with `:Connect()`.**
Any signal that only ever fires once per object (tween `Completed`, sound `Ended`) should use `:Once()`, not `:Connect()` + manual disconnect. This is a free simplification, not just a leak fix — `:Once()` guarantees exactly one firing and self-cleans.

**E. Instance.new()/:Destroy() on any hot path (breaks, hits, impacts, SFX).**
If a category of instance is created more than once per obstacle-break or per-hit event, it must come from a pool module (`Acquire`/`Release`), never raw `Instance.new()` + `:Destroy()`. This applies even to "small" instances like `NoCollisionConstraint` or `Sound` — churn frequency matters more than per-instance size.

**F. Tracking guards must exist at every level that can be called twice.**
If a function tracks child-level state with a `trackedX[part] = true` guard against double-connecting, the same function must also guard the parent level it operates on (e.g. `trackedModels[model]`), or a second call for the same parent silently stacks a duplicate top-level connection even though the children are protected.

#### 7.3 Mandatory self-audit step

Any Cursor-generated or Cursor-edited script that creates **any** of the following must end its generation with a self-audit comment block listing each instance and confirming its teardown/pooling path, before the response is considered complete:

- `:Connect(`, `:GetPropertyChangedSignal(`, `.Touched`/`.TouchEnded`
- `Instance.new(`
- `task.spawn(`, `task.delay(`, `task.defer(` used for anything other than a single immediate deferral with no captured long-lived instance

```lua
--[[
    SELF-AUDIT (Section 7):
    - RunService.Heartbeat:Connect (line 42) — stored in loopState,
      disconnected in stopPlayerDamageLoop, closes over userId only. OK.
    - character.DescendantAdded:Connect (line 88) — stored per userId,
      disconnected on CharacterRemoving + PlayerRemoving. OK.
]]
```

If any item can't be justified this way, it must be fixed before the response is returned — not flagged for a later pass.

#### 7.4 Automatable guardrail (outside the model's judgment)

Prose and self-audits are still probabilistic. Add a pre-commit or CI grep check that fails the build on the cheapest-to-detect violations, since these don't depend on the model remembering anything:

```bash
#!/usr/bin/env bash
# scripts/check-memory-hygiene.sh
# Fails if Instance.new( appears outside a *Pool.luau module.
violations=$(grep -rn "Instance\.new(" src/ --include="*.luau" \
  | grep -v "Pool\.luau")
if [ -n "$violations" ]; then
    echo "Instance.new() found outside a Pool module:"
    echo "$violations"
    exit 1
fi
```

This won't catch closure capture or connection-lifecycle mismatches (those need semantic review, not grep), but it closes off the cheapest, highest-frequency violation category for free and doesn't degrade over a long session the way prose instructions can.

#### 7.5 Living checklist

When a Cursor-generated script is found to violate Section 6/7 in a way not already covered by 7.2's named anti-patterns, add the new pattern here as a named entry with a bad/good example — the same way A–F above were captured from the August 2026 audit. This section should grow from this project's actual failure modes, not stay generic.

- *(none logged yet beyond A–F)*

### 8. Auto-Hit / Contact Damage Pattern (Obstacles)
Applies to all obstacle-damage interactions (grass, sand, rocks, etc.) and any future breakable type:
1. `.Touched` fires → resolve hit part to a player via `Players:GetPlayerFromCharacter()`; ignore non-player touches.
2. Debounce per (player, obstacle) pair so multiple limbs touching in one frame don't multi-count.
3. On first valid touch: apply one damage tick immediately, then start a scoped `task.spawn` loop that ticks damage every `X` seconds **only while contact is active** — this is scoped to the individual contact session, not a global loop, and satisfies the Zero-Polling Rule.
4. `.TouchEnded` (or the contact session's own state) ends the damage tick immediately.
5. Obstacle HP hitting 0 triggers the standard break/destroy-via-pool sequence (never raw `Instance.new()`/`:Destroy()` for the resulting debris — see Section 6).
6. Passive strength gain and client activity feedback (ObstacleHit popups) from traversal are capped to once per overlap scan interval (~0.1s) per player; obstacle damage and breaks are not capped.

### 9. Client Number Display (`NumberFormatter`)
All client UI labels that show Cash, prices, or other economy numbers must use the shared `NumberFormatter` ModuleScript in `ReplicatedStorage.Shared` — never hand-roll `K`/`M` suffixes in individual UI scripts.

- **Server is blind:** the server stores and compares raw numbers only; formatting is client display-only (see Section 5.5).
- **Abbreviation threshold:** values `>= 1000` may use `K`, `M`, `B`, … suffixes.
- **Accuracy rule (mandatory):** abbreviated text must still represent the true value — never truncate so aggressively that the label lies. Examples:
  - `1500` → **`1.5K`**, not `1K`
  - `7500` → **`7.5K`**, not `7K`
  - `3000` → **`3K`** (whole thousands omit unnecessary decimals)
  - `1250` → **`1.25K`**
- **Truncation, not rounding:** mantissa digits truncate toward zero (consistent with existing formatter behavior).
- **Explicit override:** callers may pass `{ Decimals = N }` to force a fixed mantissa width; default/auto mode picks the minimum decimal places needed so `mantissa × 1000^tier` reconstructs the floored original value.
- **Shop buy buttons:** use `ShopBuyButton.formatCashPrice` (which wraps `NumberFormatter`) so weapon/upgrade prices follow the same rules.

---

## Section 1: Core Gameplay Loop

**Genre:** Incremental/idle simulator (inspired by *+1 Cut Grass Adventure*) — click strength + traversal-based obstacle breaking, loot collection, selling, upgrading, and rebirthing.

### 1.1 The Loop (moment-to-moment)
1. Player spawns at the hub and walks toward Zone 1, into their **own private instanced field** (not shared server-wide — each player has an isolated copy of the zone geometry/obstacles).
2. Player makes contact with obstacles (grass, sand, etc.). Contact triggers auto-hit damage (see Section 5.7) — no manual clicking on the obstacle itself is required to deal traversal damage.
3. Obstacle HP depletes → obstacle breaks → clears the path forward.
4. Loot spawns in the zone, independent of the obstacle-break event (not a guaranteed drop off the obstacle itself — separate spawn logic).
5. Player collects loot as they traverse.
6. Player returns to the spawn-area NPC and sells loot for **Cash**.
7. **On return to spawn, the player's private field resets** — obstacles regenerate/respawn for the next run. There is no permanent "clearing" of a zone; every outbound trip is a fresh sweep through the same private instance.
8. Cash is spent on equipment/upgrades that increase **Strength**.
9. **Strength** also increases via: (a) manual clicks (classic +1 idle mechanic), and (b) passively through the core traversal loop itself.
10. Strength growth lets the player one-shot/faster-shot obstacles that previously took multiple hits, letting them push deeper into the private field per run.

### 1.2 Progression Stack
- **Strength** — single unified stat. Drives obstacle damage-per-hit. Increases via manual clicks and core loop participation; also boosted by purchased equipment/upgrades.
- **Level** — derived from Strength thresholds. Crossing a Strength threshold grants a Level.
- **Rebirth** — gated by reaching a target Level. Rebirthing resets Strength and Level back to a baseline, but grants a **permanent stacking multiplier** (e.g. Strength gain %, or similar) that persists across all future rebirths. Because zones are never persistently "unlocked" (they're per-run private instances, not gated by prior progress), rebirth has nothing to reset there — it purely resets the Strength/Level stat pair.

### 1.3 Economy Loop
- **Currency:** Cash, earned by selling loot at the spawn NPC.
- **Sinks:** Equipment purchases, upgrades — both ultimately convert Cash → Strength.
- **Loot:** Spawns independently within each player's private zone instance per run; not tied 1:1 to obstacle breaks.

### 1.4 Architecture Implications (for Cursor)
- **Per-player private instancing:** each player's zone/obstacle-field is a separate, isolated set of instances (e.g. cloned from a template and positioned in dedicated server-side space, or otherwise isolated per player) — not shared or visible to other players. Obstacle HP state, loot spawns, and reset timers are tracked per player, not globally.
- **Reset trigger:** the "return to spawn → sell → field resets" step means obstacle/loot reset logic should hook off the sell action (or proximity to the NPC/spawn zone), not a global timer — keeping it event-driven per the Zero-Polling Rule.
- **Data-driven zones:** obstacle HP-per-zone, loot tables per zone, and zone layout should be defined in data (ModuleScript config tables), not hardcoded per-zone logic, so future zones/updates are additive (new config entries) rather than new code paths.

**Obstacle types (`ObstacleConfig`):**

| ObstacleType | Zone | MaxHP |
|---|---|---|
| Sand | 1 | 50 |
| Sand2 | 2 | 1,000 |
| Sand3 | 3 | 7,500 |
| Sand4 | 4 | 15,000 |
| Sand5 | 5 | 25,000 |
| Sand6 | 6 | 40,000 |
| Sand7 | 7 | 60,000 |
| Sand8 | 8 | 85,000 |
| Sand9 | 9 | 115,000 |
| Sand10 | 10 | 150,000 |
| Sand11 | 11 | 190,000 |
| Sand12 | 12 | 235,000 |
| Sand13 | 13 | 285,000 |
| Sand14 | 14 | 340,000 |
| Sand15 | 15 | 400,000 |
| Sand16 | 16 | 465,000 |
| Sand17 | 17 | 535,000 |

### 1.5 Loot Rarity & Zone Luck

Loot items live in a shared data table (`LootConfig`), keyed by ItemId. Each entry has Name, Rarity, BaseSellValue, and IconId. World pickup Models are named by ItemId under `ReplicatedStorage.Assets.Loot`.

**Rarity ladder (low → high):** Common → Uncommon → Rare → Epic → Legendary → Mythic → Godly → Divine → Celestial → Secret.

Each zone defines an explicit **rarity roll table** in `LootConfig.ZONE_RARITY_WEIGHTS` — no automatic floor/neighbor math. When a zone **introduces** a new tier, that tier gets **20%** and the prior tier **80%**. Once a tier is the sole roll for a zone, it gets **100%**.

| Zone | Roll weights |
|---|---|
| 1 | Common 80%, Uncommon 20% |
| 2 | Uncommon 100% |
| 3 | Uncommon 80%, Rare 20% |
| 4 | Rare 100% |
| 5 | Rare 80%, Epic 20% |
| 6 | Epic 100% |
| 7 | Epic 80%, Legendary 20% |
| 8 | Legendary 100% |
| 9 | Legendary 80%, Mythic 20% |
| 10 | Mythic 100% |
| 11 | Mythic 80%, Godly 20% |
| 12 | Godly 100% |
| 13 | Godly 80%, Divine 20% |
| 14 | Divine 100% |
| 15 | Divine 80%, Celestial 20% |
| 16 | Celestial 100% |
| 17 | Celestial 80%, Secret 20% |

If a tier in the table has no items (or no available model), that tier is skipped for the roll and the remaining weights apply as-is. Within a chosen rarity, pick uniformly among available items.

**Current loot table:**

| ItemId | Name | Rarity | BaseSellValue |
|---|---|---|---|
| Snowflake | Snowflake | Common | 100 |
| Acorn | Acorn | Common | 120 |
| MessageInABottle | Message In A Bottle | Common | 200 |
| FireShard | Fire Shard | Uncommon | 300 |
| GoldCoin | Gold Coin | Uncommon | 250 |
| Key | Key | Uncommon | 275 |
| Goblet | Goblet | Uncommon | 295 |
| Rune | Rune | Rare | 500 |
| DiamondRing | Diamond Ring | Rare | 870 |
| Pendant | Pendant | Rare | 680 |
| Compass | Compass | Rare | 750 |
| TreasureChest | Treasure Chest | Epic | 6000 |
| GemBag | Gem Bag | Epic | 4750 |
| PhoenixFeather | Phoenix Feather | Epic | 5800 |
| AncientScroll | Ancient Scroll | Epic | 5100 |
| Trident | Trident | Legendary | 98000 |
| Hourglass | Hourglass | Legendary | 95000 |
| MageBook | Mage Book | Legendary | 105000 |
| GoldenBanana | Golden Banana | Mythic | 500000 |

**Per-zone spawn tuning:** max **5** active loot pickups per zone; max **2** of the same ItemId active per zone (falls back to allowing duplicates only when every item in the rolled rarity is already at cap); **15s** respawn delay after collection.

Selling uses BaseSellValue (then any Cash multipliers from upgrades/passives). Loot spawn/collect/sell remain event-driven and pooled per Section 5–6; the server never handles loot visuals.

### 1.6 Open Design Questions (to resolve in future sections)
- Exact Strength thresholds per Level, and Level target required to unlock Rebirth. *(Level gate and Strength curve resolved in Section 3.)*
- Rebirth multiplier formula/curve — resolved in Section 3.3: linear +0.5 Strength / +0.2 Cash per rebirth.
- Offline progression (the reference game grants Strength & Cash while offline) — is this in scope?

### 1.7 Onboarding Tutorial

First-time players (see `PlayerDataSchema.TutorialCompleted`) receive a **6-step server-authoritative** onboarding segment. Step copy is shown on the client via the Studio `Notifications` ScreenGui → `Frame` → `DefaultNotificationText` label (wired by `TutorialClient` / `TutorialNotification`; not the ephemeral `NotificationToast` pool).

| Step | Message | Server completion condition |
|------|---------|----------------------------|
| 1 | Press to gain 20 strength | `Strength >= 20` |
| 2 | Shovel sand to clear the area | First obstacle segment broken for the player |
| 3 | Dig to the loot to pick it up | First loot collected into trip inventory |
| 4 | Sell the loot you collected | First sell action that grants Cash |
| 5 | Save money for a better shovel — shows `(N Cash)` at 0 balance, `(N more Cash)` once the player already has partial cash | `Cash >=` first purchasable weapon cost (currently **Iron Shovel**, 500 Cash — from `WeaponConfig`) |
| 6 | Buy a better shovel | Successful Cash purchase of **Iron Shovel** via `WeaponShopService.TryPurchase` |

**Persistence:** `TutorialStep` (1–6 while active, 0 when done) and `TutorialCompleted` live in player save data (schema v6). Existing saves migrated to `TutorialCompleted = true` so returning players are not forced through onboarding.

**Replication:** Server sets `TutorialStep`, `TutorialMessage`, and `TutorialCompleted` player attributes; client listens and updates the notification label. Step 1 may append live `(current/20)` strength progress client-side for display only — completion remains server-gated.

**Config:** Step messages and thresholds are data-driven in `ReplicatedStorage.Shared.TutorialConfig`.

---

## Section 2: Upgrades, Equipment & Economy

### 2.1 Base Stat Upgrades (Cash-purchased)
Four purchasable stat tracks, each independently leveled with Cash at the spawn hub. All roll up into the player's effective combat/traversal performance; none of them are "Strength" directly — Strength is the composite damage stat, separately increased by clicks/core loop per Section 1.2.

| Stat | Effect |
|---|---|
| **Range** | Increases the size of the auto-hit contact hitbox — lets the player damage obstacles from further away / more forgiving proximity. |
| **Agility** | Increases attack speed — reduces the interval between auto-hit damage ticks (see Section 5.7's per-contact tick loop). |
| **Capacity** | Increases max loot the player can carry before needing to return and sell. |
| **Walk Speed** | Increases traversal movement speed through the zone. |

Each stat should be a leveled track (Level 1, 2, 3...) with an escalating Cash cost curve, stored in a data table — not hardcoded per-level logic — so balancing or adding more levels later is a config change, not a code change.

### 2.2 Weapons (Equipment)
- Weapons (e.g. the flamethrower) are **equip-one-at-a-time** — equipping a new weapon replaces the base tool/currently equipped weapon entirely.
- Each weapon is a distinct data entry with its own stat block (e.g. base damage, and optionally its own Range/Agility modifiers layered on top of the player's stat-track values).
- Weapons are purchased with Cash (higher-tier weapons gated behind Cash cost and/or a minimum Level, consistent with the Level-gates-Rebirth pattern from Section 1.2).
- Because only one is ever active, equipping is a simple state swap (`Player.EquippedWeaponId`) rather than an inventory-slot system — keep this simple unless a future update calls for a loadout system.

### 2.3 Passive Multipliers (Auras / Pets)
- Auras and/or pets provide **passive multipliers** (e.g. % Strength, % Cash, % loot rarity) independent of the equipped weapon slot.
- Recommend treating these as their own equip slot(s), separate from the weapon slot, so a player can have one weapon + one aura + one pet active simultaneously (mirrors the reference game's structure).
- Whether pets can stack (multiple equipped at once) or are also equip-one-at-a-time is an open decision — flagged below.

### 2.4 Currency & Monetization
- **Cash** — primary currency, earned by selling loot (Section 1.3). Funds all stat upgrades and weapon purchases.
- **Robux — dual purchase path:** every Cash-purchasable item (each stat upgrade level, each weapon) also has a corresponding **dev product** so it can be bought directly with Robux instead of grinding Cash. This is a convenience/skip purchase, not exclusive content — everything remains earnable for free — which keeps it on the fair side of the incremental-sim genre norm while still monetizing impatience on every single purchasable item, not just broad boosts.
- Additional gamepasses (non-item-specific) remain worth keeping: 2x Cash earned, 2x Strength gain, instant field reset. These stack alongside the per-item dev products rather than replacing them.

### 2.5 Data Architecture (for Cursor)
All of the above — stat track costs/levels, weapon stat blocks, aura/pet multipliers — should live in **ModuleScript config tables** in `ReplicatedStorage` (e.g. `StatUpgradeConfig`, `WeaponConfig`, `AuraConfig`, `PetConfig`), keyed by id. Each entry carries **both** a `CashCost` and a `DevProductId` field, so purchase logic (Cash path or Robux path) resolves to the exact same "grant this item to this player" function regardless of which path was used. Adding a new weapon or aura in a future update is then a new table entry (plus registering its dev product ID in the Roblox Creator Dashboard), not new code — directly supporting the adaptability goal from earlier in this doc.

### 2.6 Dev Product Purchase Handling (Critical Technical Rule)
Because every upgrade/weapon has a dev product, the game will have many product IDs feeding into Robux purchases. This requires strict discipline around `MarketplaceService.ProcessReceipt`:
- **Single global handler only.** There must be exactly one `ProcessReceipt` callback registered for the entire game. It dispatches internally on `receiptInfo.ProductId` (via the same config tables from Section 2.5) to determine which item to grant — never register a second handler per system, as the second silently overwrites the first.
- **Idempotent granting.** Roblox retries `ProcessReceipt` (including after server restarts) until it receives `Enum.ProductPurchaseDecision.PurchaseGranted`. The handler must check a **persisted** record of already-granted `PurchaseId`s (DataStore-backed, not just an in-memory set) before granting, so a retried callback can never double-grant an item.
- **Return the correct decision.** Only return `PurchaseGranted` after the grant is confirmed persisted; return `NotProcessedYet` on any failure (e.g. DataStore unavailable) so Roblox retries later rather than silently losing the purchase.

### 2.7 Open Design Questions
- Do pets stack (multiple active at once) or equip-one-at-a-time like weapons?
- Exact Cash cost curve per stat level (linear, exponential, etc.), and its Robux dev-product-price equivalent.
- Specific aura/pet rarity tiers and where they're obtained (shop purchase vs. loot drop vs. Robux exclusive).
- Broad gamepass lineup beyond the per-item dev products (2x Cash, 2x Strength, etc.) and their pricing.

### 2.8 Shovel Tier List & Pricing (Resolved)

Replaces the earlier partial weapon lineup (Bucket/Spade/SmallShovel/MediumShovel/LargeShovel/BigScooper — removed, `PlayerDataSchema` migrated to v7). `WoodenShovel` is the free starter (`IsStarter = true`, same role the old `Bucket` played); the other 17 are Cash-purchasable, one-at-a-time equip per Section 2.2.

**Target-zone mapping:** the first 6 upgrades map 1:1 to Zones 1-6. From Zone 7 on, obstacle-HP growth decelerates sharply (Zone 14→17 is only ~1.15-1.2x/zone per Section 1.4) while shovel damage keeps roughly doubling per tier, so upgrades spread out to roughly one per 1.5-2 zones. The last 5 shovels (Galaxy → Moonlight) intentionally out-power the current Zone 17 cap (465,000 HP) and are priced as forward-looking/prestige tiers for zones beyond the current 17-zone roster — this is expected, not a bug: late-game the bottleneck shifts from "can I break this obstacle" to "how long until I've saved enough Cash."

| Id | Name | BaseDamage | Target Zone | CashCost |
|---|---|---|---|---|
| WoodenShovel | Wooden Shovel | 1 | Zone 1 (starter) | Free |
| IronShovel | Iron Shovel | 3 | Zone 1 | 500 |
| GoldShovel | Gold Shovel | 15 | Zone 2 | 1,100 |
| DiamondShovel | Diamond Shovel | 30 | Zone 3 | 1,700 |
| EmeraldShovel | Emerald Shovel | 50 | Zone 4 | 4,000 |
| AduriteShovel | Adurite Shovel | 85 | Zone 5 | 10,500 |
| SpikyShovel | Spiky Shovel | 170 | Zone 6 | 39,000 |
| MushroomShovel | Mushroom Shovel | 350 | Zone 7 | 195,000 |
| LoveShovel | Love Shovel | 750 | Zone 9 | 1,600,000 |
| ChocolateShovel | Chocolate Shovel | 2,000 | Zone 11 | 7,900,000 |
| MagmaShovel | Magma Shovel | 3,500 | Zone 12 | 21,600,000 |
| RadioactiveShovel | Radioactive Shovel | 7,500 | Zone 14 | 116,000,000 |
| RainbowShovel | Rainbow Shovel | 15,000 | Zone 16 | 617,000,000 |
| GalaxyShovel | Galaxy Shovel | 27,500 | Future Zone 18+ | 2,390,000,000 |
| SlimyShovel | Slimy Shovel | 50,000 | Future Zone 19+ | 5,090,000,000 |
| AngelicShovel | Angelic Shovel | 125,000 | Future Zone 21+ | 21,600,000,000 |
| SunshineShovel | Sunshine Shovel | 500,000 | Future Zone 23+ | 91,200,000,000 |
| MoonlightShovel | Moonlight Shovel | 1,100,000 | Future Zone 25+ | 384,600,000,000 |

**Pricing formula:** for each target zone, compute the loot-table average sell value weighted by that zone's rarity roll (`LootConfig.ZONE_RARITY_WEIGHTS`, real `BaseSellValue`s from `LootConfig.luau`). Then:

```
ratio(rank) = 3 + 0.85 * (rank - 1)        -- rank 1 = IronShovel ... 17 = MoonlightShovel
CashCost = round(ratio(rank) * AvgZoneLootValue(targetZone))
```

`ratio` climbs from 3x (need ~3 average-value loot pickups to afford the first upgrade — matches the old Spade-at-500-Cash feel) up to ~16.6x late-game, so later upgrades always cost a few more average loot pickups than the last — a deliberate anti-trivialization lever since late-game combat itself becomes near one-shot. The 5 "future zone" tiers have no real Zone 18+ HP/loot data yet, so their anchor value continues the same ~2x-per-zone loot-value growth trend observed across real Zones 14-17; treat these 5 CashCosts as provisional until Zone 18+ content and loot tables actually exist.

This is a first-pass balance derived from the documented loot/obstacle curves, not playtested — expect tuning passes once real trip-time and Cash-earn-rate data comes in (consistent with Section 3.5's stance on the Strength/Rebirth curve).

---

## Section 3: Progression & Rebirth Curve

### 3.1 Strength-to-Level Curve
Strength required to reach a given Level follows a constant ~9.49% exponential compounding rate, refit against design targets spanning Level 2 through Level 34 for accuracy at both ends of the curve:

```
StrengthRequired(Level) = round(45 * 1.0949 ^ (Level - 2))   -- valid for Level >= 2
```

Validated against design targets (small variance at mid-range levels is expected/accepted — see note below):

| Level | Strength Required |
|---|---|
| 2 | 45 |
| 3 | ~49 |
| 4 | ~54 |
| 5 | 59 |
| 6 | ~65 |
| 10 | ~93 |
| 19 | ~211 (target: 200, ~5% variance) |
| 20 | ~231 (target: 218, ~6% variance) |
| 25 | ~363 |
| 30 | ~571 |
| 33 | ~750 (target: 748) |
| 34 | ~821 (target: 817) |

*Note: this single exponential formula closely matches the low end (Level 2-6) and high end (Level 33-34) of the design targets, with a ~5-6% overshoot in the Level 19-25 mid-range. That gap reflects the target numbers likely coming from hand-tuned/manually-adjusted values rather than a perfectly clean formula — accepted as within tolerance rather than building a piecewise/lookup-table curve.*

This single formula covers early-game and late-game levels — no separate acceleration curve is needed after any rebirth; the same 9.49%/level rate compounding over a larger Level range is what produces late-game steepness (see 3.2).

### 3.2 Rebirth Level Gate
The Level required to perform the *n*-th rebirth is simple linear growth, confirmed against data points spanning Rebirth 1 through Rebirth 11:

```
RebirthLevelGate(n) = 25 * n   -- n = 1 for first rebirth, 2 for second, etc.
```

| Rebirth # | Level Required |
|---|---|
| 1 | 25 |
| 2 | 50 |
| 3 | 75 |
| 4 | 100 |
| 5 | 125 |
| 6 | 150 |
| 7 | 175 |
| 8 | 200 |
| 9 | 225 |
| 10 | 250 |
| 11 | 275 |

Combined with 3.1's exponential Strength-per-level curve, the required *Strength* for each successive rebirth still grows extremely fast (since the Level target itself keeps climbing and each additional Level costs exponentially more Strength) — the increasing playtime-per-rebirth comes entirely from 3.1's compounding, not from the Level-gate formula needing to accelerate on its own. Linear Level growth + exponential Strength-per-level growth together produce the intended late-game steepness.

### 3.3 Rebirth Reward
- Each rebirth permanently adds **+0.5 Strength gain** and **+0.2 Cash gain** to the player's multipliers (linear stacking; does not compound on itself):

```
StrengthGainMultiplier(n) = 1 + 0.5 * n   -- n = total rebirths completed
CashGainMultiplier(n)  = 1 + 0.2 * n
```

| Rebirths | Strength gain | Cash gain |
|---|---|---|
| 0 | x1 | x1 |
| 1 | x1.5 | x1.2 |
| 2 | x2 | x1.4 |
| 3 | x2.5 | x1.6 |
| 5 | x3.5 | x2 |
| 10 | x6 | x3 |

- On rebirth: Strength and Level reset to baseline; the stacked multipliers persist across all future rebirths.

### 3.4 Architecture Notes (for Cursor)
- Implement 3.1, 3.2, and 3.3 as **pure functions in a shared `ProgressionConfig` ModuleScript**, not hardcoded per-level/per-rebirth lookup tables — tuning the entire game's pacing later means changing the constants (`45`, `1.0949` for Strength-per-level; `25` for the rebirth Level-gate; `0.5` / `0.2` for Strength/Cash gain per rebirth) in one place, not editing a giant table.
- `StrengthRequired(Level)` should be called on-demand (e.g. when checking level-up eligibility after a Strength gain event), not precomputed/cached into a growing table per player.
- Level-up and rebirth-eligibility checks are event-driven off the Strength-gain event itself (per Section 5's Zero-Polling Rule) — check thresholds only when Strength actually changes, never via a periodic scan.

### 3.5 Open Design Questions
- Formula constants (Strength curve: 45 base, 1.0949 rate; Rebirth gate: 25/rebirth; rebirth reward: +0.5 Strength / +0.2 Cash per rebirth) — confirm final or still subject to playtesting tuning.
