# Multipli Barebones Vault (v2) — Security Contest Agent Context

This file is the architecture and rules brief for agents reviewing **Multipli Protocol v2** for the HackenProof program [Multipli Smart Contracts](https://hackenproof.com/programs/multipli-smart-contracts).

**Source of truth for code:** [`multipli-libs/Barebones-MultipliVault` branch `v2`](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2) at `3c37f80f2337a1f8e01156cf4b8c10f735580374` (2026-01-16). The repo default branch is `v2`.

**Compiler:** `pragma solidity 0.8.30` on every in-scope file. Foundry profile: `solc = 0.8.30`, optimizer runs `8000`.

**Pinned libraries** (`foundry.lock`, third-party, not the hunt surface):

| Library | Commit | What Multipli uses |
| --- | --- | --- |
| OpenZeppelin Contracts | `a1a0a67a2050f5b0edac2bb64ba679cb07a88943` | ERC-20, `SafeERC20`, `Math`, `Ownable`, UUPS, `Address` |
| OpenZeppelin Upgradeable | `60b305a8f3ff0c7688f02ac470417b6bbf1c4d27` (OZ **v5.3.0**) | `ERC4626Upgradeable`, `PausableUpgradeable`, `ReentrancyGuardUpgradeable`, `Initializable` |
| Solmate | `89365b880c4f3c786bdd453d4b8e8fe410344a69` | `Authority` interface and deployed `RolesAuthority` |
| openzeppelin-foundry-upgrades | `cbce1e00305e943aa1661d43f41e5ac72c662b07` | Deployment scripts only (`Upgrades.deployUUPSProxy`) |

Read this as the protocol’s intended behavior. Prefer the Solidity over the README, and prefer **live Avalanche state** over deployment-script placeholders (`OWNER = address(0x123)` in the mainnet scripts is not the live owner).

Live figures below were read from Avalanche C-Chain on **2026-09-28**. Balances move. Re-read them before filing a report that depends on a number.

---

## 0. How agents should work this contest

1. Review production Solidity that can affect an in-scope target. Start with `src/`. Use `script/deployment/common/` only to understand the intended role and fee wiring, then confirm against the live `RolesAuthority`.
2. Ignore `test/`, `**/mocks/**`, Anvil scripts, and testnet scripts that deploy `MockERC20`. Those files are out of scope by the program rules and by this brief.
3. Do not audit OpenZeppelin or unmodified Solmate for their own bugs. `RolesAuthority` is a deployed target because Multipli’s **capability configuration** matters. A bug inside unmodified Solmate is out of scope unless Multipli’s call pattern turns it into fund loss or a broken invariant.
4. The HackenProof program text calls Multipli a “ZK-based” protocol and mentions “ZK-integrated contract logic.” **This repository contains no verifier, circuit, or proof contract.** Do not invent a ZK hunt surface, and do not review off-repo infrastructure.
5. `v1` and the Monad deployment are a different codebase. Do not review them for this contest.
6. A report needs a **runnable Foundry or Hardhat PoC**. AI-generated reports without one are rejected. Fork Avalanche (chain id `43114`) or use a local deployment of these contracts. Do not move, freeze, or take mainnet assets. Keep tests on wallets you control.
7. File only on HackenProof. No public disclosure, tweets, or discussion outside HackenProof and Multipli.
8. Owner-only powers (`adminMint`, UUPS upgrade, fee-config changes, `cancelRedeem`) are governance. Do not file “the owner can rug” unless a **non-owner** caller, or a public user, can reach that power or break an invariant the privileged role was not supposed to break.
9. Known issues in [section 12](#12-known-issues-and-prior-review) are acknowledged. Refile one only with a new path and a PoC that shows impact beyond what was already accepted.

---

## 1. Program facts (HackenProof)

| Field | Value |
| --- | --- |
| Program | [Multipli Smart Contracts](https://hackenproof.com/programs/multipli-smart-contracts) |
| Status | Live |
| Type | Smart contract / Solidity / DeFi |
| PoC | Required. Foundry or Hardhat preferred |
| Reputation gate | 150 |
| Rewards | Critical $5,000–$10,000 · High $2,000–$5,000 · Medium $750–$2,000 · Low $0–$750 (range $0–$10,000) |
| SLA | First response 3d · Triage 3d · Reward 3d · Resolution 14d |
| Eligibility | First reporter, 18+, not a current or former Multipli employee or contractor, submitted within 24 hours of discovery, same email as the HackenProof account |
| Chains of bugs | Rewarded only at the **highest** severity in the chain |
| Disclosure | None. No partial or timeline disclosure. PoCs stay private |

Product, in the program’s words: yield on assets that do not natively yield (the live v2 vaults are **USDC** and **BTC.b** on Avalanche). The on-chain system is an ERC-4626 vault whose share price is updated by a privileged operator from off-chain delta-neutral strategies. The strategies themselves are not in this repo.

### 1.1 In-scope targets

Same severity (Critical) on every row. The GitHub row is this `v2` tree.

| Target | What it actually is | Address |
| --- | --- | --- |
| Token contract (ERC-1967 proxy), Avalanche xUSDC | **User-facing vault proxy.** Name `xUSDC`, symbol `xUSDC`, 6 decimals. This is the contract users deposit to | [`0xCF0Eb4ac018C06a16ED5c63484823C7805e7599D`](https://snowtrace.io/address/0xCF0Eb4ac018C06a16ED5c63484823C7805e7599D) |
| MultipliVault, Avalanche xUSDC | **UUPS implementation** behind that proxy. Not a second vault. `initialize` on it reverts (`InvalidInitialization`, selector `0xf92ee8a9`). `proxiableUUID()` is the standard ERC-1967 implementation slot | [`0xb63601A11c5bDC79D511B8F73871d7C0d8B57AE9`](https://snowtrace.io/address/0xb63601A11c5bDC79D511B8F73871d7C0d8B57AE9) |
| VaultFundManager, Avalanche xUSDC | Immutable helper bound to the xUSDC proxy | [`0x01e676EAA0C9780A88395c651349Cf08Fe52368e`](https://snowtrace.io/address/0x01e676EAA0C9780A88395c651349Cf08Fe52368e) |
| RolesAuthority, Avalanche xUSDC | Solmate roles for the xUSDC vault | [`0xf580B985e2Fd8A8b0e4a56C2a7E24bC28e872609`](https://snowtrace.io/address/0xf580B985e2Fd8A8b0e4a56C2a7E24bC28e872609) |
| VariableVaultFee, Avalanche | **Not a proxy.** Shared fee contract for xUSDC and xBTC.b | [`0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72`](https://snowtrace.io/address/0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72) |
| GitHub repo | `src/` on `v2`, plus the deployment wiring that explains it | [Barebones-MultipliVault `v2`](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2) |

The README also lists a second live vault, **xBTC.b**, deployed from this same code. It is **not** a separate row on the HackenProof target list. It shares the in-scope `VariableVaultFee`. A bug in shared fee logic, or in vault code that also runs on the in-scope xUSDC proxy, is in scope. Do not file an issue whose only impact is the xBTC.b deployment’s own `RolesAuthority` or fund manager unless that same bug is reachable on an in-scope target.

| xBTC.b (context, not a listed target) | Address |
| --- | --- |
| Vault proxy (`xBTC.b`, 8 decimals, asset BTC.b) | `0x468BbabAEf852C134b584382C0fef83F2954Cd5c` |
| Implementation | `0xc17649fc83564fd380be8625f9902626d263357d` |
| VaultFundManager | `0x62c2181618833b202e68b5addc4279542978Ef47` |
| RolesAuthority | `0x2393D41EBc41270431Bdbdd3B3Ed03879636Ee42` |

**Assets**

| Vault | Asset | Address | Decimals |
| --- | --- | --- | --- |
| xUSDC | USDC (Avalanche) | `0xB97EF9Ef8734C71904D8002F8b6bc66Dd9c48a6E` | 6 |
| xBTC.b | BTC.b | `0x152b9d0FdC40C096757F570A51E494bd4b943E50` | 8 |

**Common owner** of both vaults, both authorities, and `VariableVaultFee` (read 2026-09-28): `0xf25c404c101D40d88b5dCD64B82583dBC918Dd25`.

### 1.2 Impact policy — what is in scope

The program wants incorrect contract behavior with a demonstration.

**Critical / High**

- Theft or permanent loss of funds
- Unauthorized withdrawals or transfers
- Incorrect accounting that mints or burns the wrong number of shares
- Yield, rate, or share-price inflation or deflation
- A broken protocol invariant
- Behavior that diverges from the business rules in this file and the repo README
- Upgradeable proxy mistakes: wrong implementation slot, unsafe `delegatecall`, broken UUPS
- Bypassing admin, role, or guardian checks
- Cross-module calls that skip verification (`manage` → fund manager → vault callback is the one to study)
- Reentrancy, direct or cross-contract
- Storage collision or shadowing

**Medium / Low**

- Overflow or underflow with impact
- Balance manipulation through an unexpected state change
- Precision or rounding with **measurable** financial impact
- Incorrect fee or reward distribution
- Time misalignment that lets someone skip a cost or capture value
- A bad execution path across multiple calls

### 1.3 Out of scope

Not eligible unless the report shows **clear fund loss or a broken invariant**:

- Third-party library bugs (OpenZeppelin, Solmate, forge-std)
- Gas, style, “best practice”
- Test or mock contracts
- Minor rounding with no financial impact
- MEV or frontrunning that only captures profit and does not break an invariant
- Governance assumptions that need owner privileges
- Issues that need unrealistic liquidity or miner collusion
- A public zero-day with no PoC
- Compiler-version warnings with no exploit
- Theoretical issues with no demonstration
- Social engineering or anything that is not the smart contracts

Also out of scope by the program rules, full stop:

- Scanners that generate heavy traffic
- Attacks on infrastructure, DNS, frontend, API, or backend
- Real fund damage on mainnet
- Touching another user’s assets
- DoS, DDoS, spam, or destructive testing

### 1.4 Where to put a finding

| Severity on this program | Typical fit for this codebase |
| --- | --- |
| Critical | A public user, or a role that was not granted that power, steals or permanently locks assets, or mints unbacked shares that redeem against other depositors |
| High | Share-price manipulation, a broken `totalAssets` / `totalSupply` invariant, or an auth bypass on `manage`, `fulfillRedeem`, `removeFunds`, or `onUnderlyingBalanceUpdate`, with a concrete gain |
| Medium | Fee math that over- or under-charges in a way users cannot avoid, or a state-order bug with a bounded but real loss |
| Low | A real accounting mismatch whose loss is bounded and repairable (the README already accepts some of these; see section 12) |

“The fund manager can report a false strategy balance” is the trust model, not a finding. “A depositor can move that balance, or can exit in the same transaction the balance moves, beyond the acknowledged sandwich” is a finding if the PoC shows it.

---

## 2. What the system is

Multipli v2 is an **asynchronous ERC-4626 vault**. Users deposit an underlying asset and receive share tokens (`xUSDC` or `xBTC.b`). The vault does not lend, trade, or run a strategy on-chain. Operators move idle underlying to exchanges, and later write the strategy NAV into the vault as `aggregatedUnderlyingBalances`. That number **is** the yield oracle. Share price is:

```text
totalAssets = idle ERC-20 balance of the vault + aggregatedUnderlyingBalances
price       = totalAssets / totalSupply          (OZ virtual shares, see below)
```

Direct `withdraw` and `redeem` revert with `UseRequestRedeem()`. Users call `requestRedeem`. Shares move to the vault and stay in `totalSupply`. A fund manager later pulls assets back and calls `fulfillRedeem`, which burns the escrowed shares and pays the user. Documented processing time is **4–10 days**. That delay is operational, not an on-chain timer. There is no maturity timestamp in the contracts.

Two code paths exist and are **not** in production use, by the README:

- `MultipliMigrator` — v1 (StarkEx / off-chain ledger) to v2 share migration. **No deployment** on mainnet or testnet. Role `ETHEREUM_MIGRATOR_V1` is unused.
- `flashRedeem` — instant unwind of shares that sit in another protocol. The README says permissions were revoked and the feature will be removed in v3. On 2026-09-28 the **role capability is still granted** to `FUND_MANAGER_CONTRACT` on both vaults. Whether any `whitelistedUserOperator` entry is set cannot be enumerated from a mapping. Do not assume the path is deleted, and do not file “the function exists.”

`requestInstantRedeem` / `fulfillInstantRedeem` are a second redemption type (higher fee). On both live authorities **no role** has those selectors. Only the vault owner can call them, because `AuthUpgradeable` treats `owner` as authorized for every selector on the vault itself.

---

## 3. Architecture

```text
User
  │  deposit / mint / requestRedeem / ERC-20 transfer of shares
  ▼
MultipliVault  (UUPS proxy, ERC-4626 share token)
  │  totalAssets = idle balance + aggregatedUnderlyingBalances
  │  fees via VaultFeeUpgradeable ───────────────► VariableVaultFee (shared, Ownable)
  │  auth via AuthUpgradeable ───────────────────► RolesAuthority (per vault)
  │
  │  manage(target, data, value)     only if caller is authorized AND
  │                                  authority.canCall(caller, target, selector)
  ▼
VaultFundManager (not upgradeable, immutable vault + asset)
  │  onlyVault on every method except flashRedeem
  │  callbacks into the vault:
  │     removeFunds / onUnderlyingBalanceUpdate / fulfillRedeem / flashRedeem
  ▼
Whitelisted recipient (exchange or strategy wallet)   ← off-chain delta-neutral book
```

There is one `VariableVaultFee` per network in Multipli’s deployment pattern. xUSDC was deployed first (`Base.s.sol` deploys a new fee contract). xBTC.b was deployed second (`BaseWithSharedConfig.s.sol` reuses it). Each vault has its **own** `RolesAuthority` and `VaultFundManager`.

`MultipliVault` inheritance, in order:

`UUPSUpgradeable`, `ERC4626Upgradeable`, `IMultipliVault`, `AuthUpgradeable`, `PausableUpgradeable`, `VaultFeeUpgradeable`, `FundMovementHelperUpgradeable`, `ReentrancyGuardUpgradeable`.

Custom storage is ERC-7201, not laid out in the inheritance slots. OZ v5 upgradeable contracts use their own namespaced slots. Collisions would be a finding; the layout is designed to avoid them.

| Namespace (as coded) | Slot constant | Contract |
| --- | --- | --- |
| `multipli.storage.MultipliVaultStorage` | `0x5c514b81e93a4e64ed3b3d78d8355319d5f0f527b3964e825d59f3a9d74af900` | `MultipliVault` |
| Annotation says `erc7201:multipli.storage.vaultfee`. The slot comment is `multipli.storage.vaultfeeV1` | `0x4e0114f5bb788bf295d0ab17f602045fbe9841605d1e05a2674fbfa584e94700` | `VaultFeeUpgradeable` |
| `auth.storage` | `0xdd3fd67aef415aded9493b31ad20a02d2991d4bb2760431cc729821271eaea00` | `AuthUpgradeable` |
| `multipli.storage.FundMovementHelperStorage` | `0x2bbdf87c296f0fc445d947563c77d7b805fc738a2e220084769a264d45deaf00` | `FundMovementHelperUpgradeable` |
| `openzeppelin.storage.ERC4626` | `0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00` | OZ ERC-4626 |

Use the **constants in the source**, not a fresh hash of the annotation string. The fee namespace comment and the annotation disagree.

`VaultFundManager` storage is ordinary (not ERC-7201) and the contract is not behind a proxy. Replacing it means deploying a new manager and moving role bits. The old manager keeps `FUND_MANAGER_CONTRACT` until an authority owner clears it.

---

## 4. Actors and live authorization

Roles (`src/common/Role.sol`):

| Value | Name | Live use on xUSDC (2026-09-28) |
| --- | --- | --- |
| 0 | `NONE` | — |
| 1 | `ADMIN` | Vault owner `0xf25c…Dd25` has this bit (`getUserRoles = 0x02`) |
| 2 | `FUND_MANAGER` | EOAs / operator wallets. Bit `0x04`. The wallet address is not stored on the vault; it is whoever the authority assigned |
| 3 | `FUND_MANAGER_CONTRACT` | The `VaultFundManager` address only (`getUserRoles = 0x08`) |
| 4 | `ORACLE` | Defined, **not granted**, not referenced by deployment scripts |
| 5 | `EXTERNAL_CURATOR` | Defined for instant redeem in comments, **not granted** |
| 6 | `ETHEREUM_MIGRATOR_V1` | Defined for `MultipliMigrator`, **not granted**, migrator not deployed |

Solmate stores roles as bits in a `bytes32`. `canCall` is true only if the capability is public (none are) or the caller’s role bits overlap the roles allowed for `(target, selector)`.

**Owner bypass is only inside `MultipliVault.isAuthorized`.** `requiresAuth` passes for the vault owner even when no role bit is set. `RolesAuthority.canCall` does **not** special-case the owner. `manage()` checks both:

1. `requiresAuth` on `manage` itself (owner, or a role that has the `manage` selector).
2. `authority.canCall(msg.sender, target, selector)` on the inner call. The owner still needs a role bit for that inner selector.

So the owner can call `adminMint`, `upgradeToAndCall`, `cancelRedeem`, `setFeeContract`, `fulfillInstantRedeem` **directly** on the vault. The owner cannot `manage()` into `VaultFundManager.removeFunds` or `removeFundsNative`, because those selectors have **no** role capability.

### 4.1 Live capability map (xUSDC authority, 2026-09-28)

No capability is public. Role bits: ADMIN `0x02`, FUND_MANAGER `0x04`, FUND_MANAGER_CONTRACT `0x08`.

| Selector | Role that `canCall` |
| --- | --- |
| `MultipliVault.manage(address,bytes,uint256)` | FUND_MANAGER |
| `MultipliVault.manage(address[],bytes[],uint256[])` | ADMIN (granted on xUSDC; **not** granted on xBTC.b) |
| `pause` / `unpause` | FUND_MANAGER |
| `onUnderlyingBalanceUpdate(uint256)` | FUND_MANAGER_CONTRACT |
| `removeFunds(uint256,address)` | FUND_MANAGER_CONTRACT |
| `fulfillRedeem(address,uint256,uint256)` | FUND_MANAGER_CONTRACT |
| `flashRedeem(address,address,address,uint256,uint256,bytes)` | FUND_MANAGER_CONTRACT |
| `VaultFundManager.removeFundsFromVault(address,uint256)` | FUND_MANAGER |
| `VaultFundManager.updateUnderlyingBalance(uint256,uint256)` | FUND_MANAGER |
| `VaultFundManager.addFundsAndFulfillRedeem(address,uint256,uint256)` | FUND_MANAGER |
| `VaultFundManager.updateUserOperatorWhitelist(address,address,bool)` | ADMIN |
| `fulfillInstantRedeem`, `requestInstantRedeem`, `adminMint`, `adminBurn`, `cancelRedeem`, `setFeeContract`, `upgradeToAndCall`, `whitelistFundTransferRecipient` | **no role** (owner direct calls only) |
| `VaultFundManager.removeFunds(address,uint256)`, `removeFundsNative(address,uint256)` | **no role** |

xBTC.b matches on `flashRedeem` (role 3), single `manage` (role 2), and the whitelist setter (role 1). It does **not** grant batch `manage`.

Intended operator path, and the one the README says to use:

```text
FUND_MANAGER
  → MultipliVault.manage(fundManager, calldata, 0)
      → VaultFundManager.<method>()          // msg.sender == vault, onlyVault passes
          → MultipliVault.<callback>()       // msg.sender == fundManager, role 3 passes
```

`flashRedeem` on `VaultFundManager` is the exception: any address whose `(user, operator)` pair is whitelisted may call it directly. It then calls `vault.flashRedeem` as the fund-manager contract.

---

## 5. Accounting

### 5.1 Share price

`MultipliVault.totalAssets()` overrides OZ:

```text
IERC20(asset).balanceOf(vault) + aggregatedUnderlyingBalances
```

`totalPendingAssets` is **not** subtracted. Shares escrowed for redemption stay in `totalSupply` (they sit on the vault’s own balance).

OZ v5.3.0 conversion, and `MultipliVault` does not override it (`_decimalsOffset()` returns 0):

```text
shares = assets * (totalSupply + 1) / (totalAssets + 1)     // floor on deposit
assets = shares * (totalAssets + 1) / (totalSupply + 1)     // floor on redeem, ceil on mint
```

The `+ 1` virtual share and virtual asset are the inflation-attack mitigation. Deployment also does an initial `deposit` of `INITIAL_LOCK_DEPOSIT_AMOUNT` to the owner. Those seed shares are ordinary shares. They are not burned and not locked. The owner can `requestRedeem` them like any holder.

`lastPricePerShare` is **not** the live ERC-4626 price. It is a snapshot written only inside `onUnderlyingBalanceUpdate`:

```text
lastPricePerShare = totalAssets * 1e18 / totalSupply
```

Always 1e18, regardless of the asset’s decimals (6 for USDC, 8 for BTC.b). `VaultFundManager`’s flash-redeem check compares `convertToAssets(10 ** decimals)` with itself across the call, and `lastPricePerShare` with itself. Those two numbers are different scales (about `1e6` vs `1e18` on xUSDC). The check uses **percentage change of each**, so the scale gap is not itself a broken comparison. A comment in `_captureCurrentStateInformation` says they should be equal. They are not. That comment is wrong; do not file it unless a check uses them as if they were the same unit.

### 5.2 Circuit breaker

`onUnderlyingBalanceUpdate`:

- Reverts if `block.number <= lastBlockUpdated` (at most once per block).
- If `lastPricePerShare == 0`, percentage change is defined as 0, so the **first** update never pauses.
- If the absolute percentage move exceeds `maxPercentageChange`, the vault **pauses**. It does not revert the update. The new balance is stored, then the pause happens.
- Default and live value: `1e16` = 1%. `updateMaxPercentageChange` requires `new < 1e17` (strictly under 10%).
- Pause runs through `_update`, so **mints, burns, and share transfers** revert while paused. `adminMint` / `adminBurn` comments say they work while paused. They do not: both go through `_update`, which is `whenNotPaused`. `deposit`, `mint`, `requestRedeem`, and `flashRedeem` are also `whenNotPaused`. `fulfillRedeem` has no pause modifier, but it burns shares, so it reverts while paused too.

The 1% cap is the on-chain limit on a single NAV print. It does not enforce the off-chain “21 updates over 7 days” schedule. That schedule is backend policy (section 12).

### 5.3 Invariants the code is written to hold

Treat a break of one of these, with a PoC, as the core of a report. Confirm the invariant still exists in the function you are reading before you cite it.

1. A public caller cannot `withdraw` or `redeem`. Both revert `UseRequestRedeem()`.
2. A public caller cannot change `aggregatedUnderlyingBalances`. The writer is `onUnderlyingBalanceUpdate`, and on the live vault only `FUND_MANAGER_CONTRACT` (plus the owner, directly) is authorized.
3. `removeFundsFromVault` keeps `totalAssets` and `totalSupply` unchanged: tokens leave the vault, and the aggregated balance increases by the same amount. The recipient must already be on the vault whitelist (`RecipientNotWhitelisted` otherwise).
4. `addFundsAndFulfillRedeem` refuses `assetsWithFee > aggregatedUnderlyingBalances` (`InsufficientAggregateUnderlyingBalance`). Idle tokens that were never swept into the aggregated balance cannot be paid out through this function. The operator must sweep first (`removeFundsFromVault`), which moves the accounting into the aggregated number.
5. `requestRedeem` pulls shares only from `msg.sender` (`NotSharesOwner`). There is no allowance-based request and no permit. `REQUEST_ID` is always 0. Pending state is one bucket per **receiver**, not per request id: a second request to the same receiver adds to `shares` and `assets`.
6. `fulfillRedeem` / `cancelRedeem` cannot take more shares or more assets than that receiver’s bucket. Shares and assets are checked separately. The contract does **not** recompute the fair asset amount from the current price. The caller passes `assetsWithFee`.
7. Percentage fees cannot be configured above 5% (`5e16`). Flat fees have no percentage cap. `feeOnTotal` reverts if a flat fee is larger than the amount. `feeOnRaw` can return a flat fee larger than the amount; the caller is expected to handle that.
8. UUPS: `_authorizeUpgrade` is `requiresAuth`. On the live vault no role has `upgradeToAndCall`. The implementation’s initializer is disabled in the constructor.

---

## 6. User flows

### 6.1 Deposit

`deposit(assets, receiver)` and `mint(shares, receiver)` are the ERC-4626 entry points. Both are `whenNotPaused` and `nonReentrant`. Both revert if the **asset** amount is below `minDepositAmount`.

Live minimums (2026-09-28): xUSDC `10e6` = 10 USDC. xBTC.b `7978` = 0.00007978 BTC.b.

Slippage overloads, added after the Shieldify review:

- `deposit(assets, receiver, minShares)` calls the two-argument `deposit`, then reverts `InsufficientSharesReceived` if `shares < minShares`.
- `mint(shares, receiver, maxAssets)` calls the two-argument `mint`, then reverts `ExcessiveAssetsRequired` if `assets > maxAssets`.

The two-argument forms are still the standard ERC-4626 functions and have no slippage parameter. That is intended. The three-argument forms are the user-facing protection. Do not refile “deposit has no slippage parameter.”

Fee on deposit (live: **flat 0** for both assets, so the fee branch is dormant):

1. `previewDeposit(assets)` computes `fee = feeOnTotal(DEPOSIT)` and previews shares on `assets - fee`.
2. `_deposit` pulls the **full** `assets` from the caller via OZ `safeTransferFrom`, mints `shares` to `receiver`, then transfers `fee` from the vault to `feeRecipient` if both are non-zero.
3. Net assets left in the vault equal `assets - fee`, which is what the share preview used.

`previewMint` does the reverse: OZ preview of the raw assets, then `feeOnRaw(DEPOSIT)` added on top. The user pays raw + fee; the fee is forwarded; the raw amount stays.

If `feeContract` is `address(0)`, every fee read reverts `ConfiguredIncorrectly`. Deposits would revert. The owner can `setFeeContract`. Pointing it at an unregistered asset reverts `InvalidAsset` inside `VariableVaultFee`.

### 6.2 Request redemption

`requestRedeem(shares, receiver, owner)`:

- `owner` must be `msg.sender`, `shares > 0`, balance sufficient.
- Gross assets are `ERC4626.previewRedeem(shares)` (the **super** call, before the withdrawal fee). The net `previewRedeem` subtracts the withdrawal fee and is what a user should quote, but the pending bucket stores the gross number.
- Shares transfer to the vault. `totalSupply` does not change. `totalPendingAssets` increases by the gross amount.
- `pendingRedeem[receiver]` accumulates `(shares, assets)`.
- Event `RedeemRequest(receiver, owner, assetsWithFee, shares)`.

The user is then waiting on the operator. There is no on-chain claim. The user cannot cancel their own request. `cancelRedeem` is an authorized function with **no role capability** on the live vault (owner only). The README says operators cancel when a fee change between request and fulfillment is large, then the user requests again.

### 6.3 Fulfillment (operator, not the user)

`addFundsAndFulfillRedeem(receiver, shares, assetsWithFee)` on the fund manager, reached through `vault.manage`:

1. Fund manager contract must already hold `assetsWithFee` of the underlying (sent in by the backend from the exchange).
2. `assetsWithFee` must be `<= aggregatedUnderlyingBalances`.
3. Transfer that amount to the vault.
4. `vault.fulfillRedeem`: shrink the pending bucket, emit `RequestFulfilled`, then `_executeWithdrawal` for `RedeemType.NORMAL`.
5. `onUnderlyingBalanceUpdate(aggregated - assetsWithFee)`.

`_executeWithdrawal` for a normal redeem:

- `fee = feeOnTotal(WITHDRAWAL, assetsWithFee)`.
- Burns `shares` from the vault (the escrow).
- Sends `assetsWithFee - fee` to `receiver`.
- Sends `fee` to `feeRecipient` when both are non-zero.

Instant fulfillment uses `feeOnTotal(INSTANT_WITHDRAWAL)` instead. Same pending bucket. The redeem type is chosen by **which fulfill function** the authorized caller uses, not locked at request time. On the live deployment only the owner can call `fulfillInstantRedeem`.

`previewWithdraw` exists and includes the withdrawal fee, but `withdraw()` reverts. It is not the redemption path.

### 6.4 What a depositor actually earns

Yield is not a streamed rate. It appears when an operator calls `updateUnderlyingBalance(oldAggregated, newAggregated)` and `newAggregated` is higher. Losses appear the same way. Every share, including shares escrowed in the vault for a pending redeem, is in `totalSupply` while the NAV updates, so pending redeemers still take part in yield and loss until fulfillment. At fulfillment they are paid the **gross amount stored at request time**, not the new price, minus the fee at fulfillment time. The README treats the leftover price drift as an accepted design limit (section 12).

---

## 7. Operator flows

All three of these are `onlyVault` + `nonReentrant`, and on the live authority they are callable through `manage` by `FUND_MANAGER`.

### 7.1 `removeFundsFromVault(recipient, amount)`

Moves idle underlying to a whitelisted exchange wallet without changing share price.

- Vault token balance must cover `amount`.
- `vault.removeFunds(amount, recipient)` transfers and requires `isRecipientWhitelisted(recipient)`.
- Then `onUnderlyingBalanceUpdate(oldAggregated + amount)`.
- Reverts `TotalAssetsMismatch` or `TotalSupplyMismatch` if either total moved.

Whitelist is `whitelistFundTransferRecipient`, owner-only on the live vault (no role bit).

### 7.2 `updateUnderlyingBalance(oldAggregatedBalance, newAggregatedBalance)`

NAV print.

- Reverts `AggregatedBalanceMismatch` if the vault’s current aggregated balance is not the `old` value the operator passed. That is a checksum against a stale transaction, not a sandwich fix.
- Calls `onUnderlyingBalanceUpdate(new)`.
- Emits `UnderlyingBalanceUpdated` **again**. The vault already emitted one. Shieldify L-01 acknowledged the duplicate. The `old` argument is the checksum and is no longer “only for the event.”

The backend is supposed to pause and alert if the contract auto-pauses because the move exceeded `maxPercentageChange`. Watch `Paused`.

### 7.3 `addFundsAndFulfillRedeem`

Covered in section 6.3. Order on current `v2` is: transfer in, **then** `fulfillRedeem`, **then** lower the aggregated balance. That order is the Shieldify M-02 fix. The old order (lower the NAV before burning shares) is not the code you are reading.

### 7.4 `flashRedeem(operator, shares, data)` on the fund manager

Not `onlyVault`. Caller must be on `whitelistedUserOperator[msg.sender][operator]`. Admin sets that list through `manage` → `updateUserOperatorWhitelist`.

Steps:

1. `assetsWithFee = vault.convertToAssets(shares)`.
2. Fund manager must hold that much underlying, and aggregated balance must be at least that much and non-zero.
3. Transfer underlying to the vault.
4. `vault.flashRedeem(initiator = msg.sender, operator, receiver = operator, shares, assetsWithFee, data)`.
5. Lower aggregated balance by `assetsWithFee`.
6. `_validateStateChanges`: percentage move of `lastPricePerShare` and of `convertToAssets(10 ** decimals)` must each be **strictly under `1e15` (0.1%)**. A natspec comment says 0.5%. The `require` is 0.1%. Also checks total assets, total supply, token balance, and the aggregated delta.

`MultipliVault.flashRedeem` (role 3, `nonReentrant`, `whenNotPaused`):

- Fee is `feeOnTotal(FLASH_REDEEM, assetsWithFee)`. Live flash fee is 0.02%, same shape as the normal withdrawal fee, not the 0.5% instant fee.
- Sends `assetsWithFee - fee` to `receiver` (the operator, when called from the fund manager) and the fee to `feeRecipient` **before** the callback.
- Calls `IMultipliVaultCallee(operator).onRedemptionFlashLoan(initiator, vault, asset, shares, assetsWithoutFee, data)`.
- Requires the vault’s **share** balance to have increased by at least `shares` (the operator must return xTokens, not underlying).
- Burns those shares from the vault.
- Requires `totalSupply` dropped by exactly `shares`, and the vault’s underlying balance to be at least `balanceBefore - assetsWithFee` (the operator may donate extra underlying; it may not leave the vault short).

The callback runs while the vault’s reentrancy guard is held, so `deposit` / `mint` / `requestRedeem` / a nested `flashRedeem` on the vault revert. `fulfillRedeem` is **not** `nonReentrant`. Whether a callback can reach it depends on auth: the caller of `fulfillRedeem` would be the operator, who does not hold role 3. The owner and the fund-manager contract do.

### 7.5 Migrator (in the repo, not deployed)

`MultipliMigrator` is `Ownable` + `ReentrancyGuard`. Allowlisted operators call:

- `adminMintSingle(id, receiver, assets, minShares)`
- `adminMintBatch(...)` with `MAX_BATCH_SIZE = 10`

Both `previewDeposit` the current rate, `adminMint` that many shares, mark `migrationID[id]`, then `onUnderlyingBalanceUpdate(aggregated + assets)`. No tokens move. The shares are backed only by the accounting credit. That is the design: v1 balances lived on StarkEx and a backend ledger, not in this vault. Replay of an id reverts. The migrator must be granted `ETHEREUM_MIGRATOR_V1` or otherwise be authorized for `adminMint` and `onUnderlyingBalanceUpdate`. Nothing on Avalanche has that grant today.

A bug here is in scope because `src/migrator/` is part of the GitHub target. Say clearly in the report that there is no live deployment, and show the impact on a vault configured the way `adminMint` + `onUnderlyingBalanceUpdate` actually work.

---

## 8. Fees

`VariableVaultFee` is a separate `Ownable` contract. One deployment, many assets. The vault only stores the fee-contract address and calls `feeOnRaw` / `feeOnTotal` / `getFeeRecipient`.

| Enum | Meaning |
| --- | --- |
| `FeeType.FLAT = 0` | `feeAmount` is an absolute token amount |
| `FeeType.PERCENTAGE = 1` | `feeAmount` uses `1e18 = 100%`. Cap `5e16` = 5% |
| `FeeOperation` | `DEPOSIT = 0`, `WITHDRAWAL = 1`, `INSTANT_WITHDRAWAL = 2`, `FLASH_REDEEM = 3` |

Percentage math (`Math.Rounding.Ceil`, in the protocol’s favor):

```text
feeOnRaw(assets)   = assets * fee / 1e18
feeOnTotal(assets) = assets * fee / (fee + 1e18)
```

`feeOnTotal` is the “fee already included in the amount” formula. A 1% fee on a total of 100 is `100 * 0.01 / 1.01`, not `1`.

**Live config, both USDC and BTC.b, read 2026-09-28.** The deployment script’s comments (0.1% withdrawal, 0.1% flash) are stale.

| Operation | Type | Rate | Where it is charged |
| --- | --- | --- | --- |
| Deposit | Flat | 0 | `previewDeposit` / `_deposit` |
| Withdrawal (normal redeem) | Percentage | `2e14` = **0.02%** | `_executeWithdrawal` at fulfillment, on the gross amount stored at request time |
| Instant withdrawal | Percentage | `5e15` = **0.5%** | Only if `fulfillInstantRedeem` is used |
| Flash redeem | Percentage | `2e14` = **0.02%** | `flashRedeem`, on `convertToAssets(shares)` |

Fee recipient for both assets: the owner `0xf25c404c101D40d88b5dCD64B82583dBC918Dd25`.

Only the fee-contract owner can `registerAsset`, `updateAssetFeeConfig`, and `deregisterAsset`. Deregistering an asset that a live vault uses makes deposits and redeems revert. That is an owner action.

Fees can change between `requestRedeem` and `fulfillRedeem`. The user is charged the fee **at fulfillment**. The README documents this and the `cancelRedeem` mitigation. Do not refile it as a surprise.

---

## 9. Live snapshot (Avalanche C-Chain, 2026-09-28)

Both vaults were unpaused.

| | xUSDC proxy | xBTC.b proxy |
| --- | --- | --- |
| `totalSupply` | 11,167.203380 shares | 0.00149952 shares |
| `totalAssets` | 11,781.764924 USDC | 0.00154403 BTC.b |
| `aggregatedUnderlyingBalances` | 9,038.586567 USDC | 0.00154403 BTC.b (idle ≈ 0) |
| Idle in the vault | ≈ 2,743.178357 USDC | ≈ 0 |
| `totalPendingAssets` | 213.848663 USDC | 0 |
| `lastPricePerShare` | ≈ 1.055033e18 | ≈ 1.029683e18 |
| `lastBlockUpdated` | 95,031,937 | 95,025,196 |
| `maxPercentageChange` | 1% | 1% |
| `minDepositAmount` | 10 USDC | 0.00007978 BTC.b |
| `feeContract` | shared `0x4E5F…B72` | same |
| `authority` | `0xf580…2609` | `0x2393…Ee42` |
| Fund manager `vault()` | the xUSDC proxy | the xBTC.b proxy |

xUSDC idle is large relative to pending redemptions. Aggregated balance is the off-vault NAV the operator has posted, not a token balance you can read from an exchange contract in this repo.

---

## 10. File map (`src/`)

Review these. Line counts are the `v2` tree at the commit above.

| File | Lines | Role |
| --- | --- | --- |
| `src/vault/MultipliVault.sol` | 1092 | User vault, ERC-4626, async redeem, NAV update, UUPS, `manage` |
| `src/managers/VaultFundManager.sol` | 698 | Sweep, NAV print, fulfill, flash redeem, native and ERC-20 sweeps |
| `src/fees/VariableVaultFee.sol` | 291 | Per-asset fee config and math |
| `src/base/VaultFeeUpgradeable.sol` | 249 | Vault-side fee dispatch. `setFeeContract` on the base has **no** auth; `MultipliVault` overrides it with `requiresAuth` |
| `src/base/FundMovementHelperUpgradeable.sol` | 162 | Recipient whitelist and `_removeFunds` |
| `src/base/AuthUpgradeable.sol` | 131 | Upgradeable Solmate-style auth. Owner is authorized for every selector |
| `src/migrator/MultipliMigrator.sol` | 173 | Undeployed v1→v2 minter |
| `src/libraries/Errors.sol` | 118 | Custom errors |
| `src/interfaces/IMultipliVault.sol` | 170 | Events, `PendingRedeem`, external signatures |
| `src/interfaces/IVariableVaultFee.sol` | 104 | Fee types |
| `src/interfaces/IMultipliVaultCallee.sol` | 25 | `onRedemptionFlashLoan` callback |
| `src/common/Role.sol` | 12 | Role enum |
| `src/base/Compatible.sol` | 94 | **Unused.** Not in the vault inheritance. Skip |
| `src/interfaces/IWETH9.sol` | 15 | **Unused** by any `src/` contract. Skip |

`VaultFundManager.sol` imports `forge-std/console.sol` and does not call it. That is a leftover. Style and unused imports are out of scope unless you show the import changes production behavior.

### Deployment scripts (context, not a mock hunt)

| Script | Use |
| --- | --- |
| `script/deployment/common/Base.s.sol` | First vault on a network. Deploys `RolesAuthority`, `VariableVaultFee`, UUPS vault, `VaultFundManager`. Registers the asset. Initial deposit. Role wiring in section 4 |
| `script/deployment/common/BaseWithSharedConfig.s.sol` | Later vaults. Reuses an existing fee contract. Same role wiring |
| `script/deployment/DeployXBTCAvalancheMainnet.s.sol` | Placeholder owner and fee address. **Do not** treat `address(0x123)` as live configuration |
| `script/deployment/DeployXUSDCAvalancheAnvil.s.sol` and `*Testnet.s.sol` | Deploy `MockERC20`. Out of scope |

`Base.s.sol` does not grant `fulfillInstantRedeem`, `requestInstantRedeem`, `adminMint`, `cancelRedeem`, `removeFunds` on the fund manager, or batch `manage`. Batch `manage` for ADMIN on xUSDC was added after that script. Trust the live `getRolesWithCapability` reads in section 4.

---

## 11. Upgrades

`MultipliVault` is UUPS. The proxy is ERC-1967. The implementation slot of the xUSDC proxy is the in-scope implementation address `0xb636…AE9`.

- Constructor calls `_disableInitializers()`.
- `initialize` sets ERC-20 name/symbol, ERC-4626 asset, owner, authority `address(0)`, fee contract `address(0)`, `maxPercentageChange = 1%`, `minDepositAmount = 0`. The deployment script then `setFeeContract`, `setAuthority`, deposits the seed, and `updateMinDepositAmount`.
- `_authorizeUpgrade` is `requiresAuth` and does not check that `newImplementation` is a contract or that it is a `MultipliVault`. On the live vault only the owner passes `requiresAuth` for `upgradeToAndCall`. An upgrade that bricks the proxy or points at a malicious implementation is an owner action.
- `VaultFundManager`, `VariableVaultFee`, and `RolesAuthority` are not upgradeable. Fee and role changes are owner transactions on those contracts (`VariableVaultFee.owner` and `RolesAuthority.owner` are the same `0xf25c…` address).

A storage-collision or initializer-reentry bug that a **non-owner** can trigger is in scope. “Owner can upgrade” is not.

---

## 12. Known issues and prior review

### 12.1 README section 8 (accepted behavior)

1. **Yield sandwich on `onUnderlyingBalanceUpdate`.** A depositor can enter before a NAV print and receive a share of that print. The documented mitigation is operational: the backend prints the NAV **21 times a week** (about every 8 hours for 7 days) instead of once. The contract only enforces once-per-block and the 1% pause. Public users **cannot** `redeem` in the same transaction; they enter the 4–10 day queue. Instant redeem is not role-granted. Refile this only if the PoC exits faster than that queue, or breaks an invariant the stagger does not cover. The program also excludes frontrunning that does not break an invariant.
2. **Fee can change between request and fulfill.** User receives more or less than `previewRedeem` at request time. Mitigation: operator `cancelRedeem`, user requests again. Accepted.
3. **`fulfillRedeem` does not check that `assetsWithFee` matches the shares at the current price.** It only checks both numbers are within the pending bucket. A mismatch leaves the remainder pending. The README assigns the check to the backend. A PoC that turns this into theft of **someone else’s** funds, rather than a stuck remainder, is new and in scope.
4. **Pending redemptions distort price until fulfillment.** `requestRedeem` does not reduce `totalSupply` or `totalAssets`. A NAV update in between, then a fulfillment at the old gross amount, moves the remaining share price. README severity: low, no funds lost, accepted. One discussed fix (exclude pending shares from price) is explicitly not implemented.

### 12.2 Shieldify, 8 July 2025

Report in the repo: `audits/multipli-vault-security-review-shieldify-2025-07-08.pdf`.

| | |
| --- | --- |
| Reviewed commit | `c6ff40b438fe6d0ec01a6630f3ef2c9020ea4f8d` (older and smaller than this `v2`) |
| Fixes commit cited by Shieldify | `664fd70bd9f09dd362eacd0b3bbaa5eee2013038` |

| ID | Title | Status then | How current `v2` relates |
| --- | --- | --- | --- |
| H-01 | Sandwich `onUnderlyingBalanceUpdate` | Fixed | Not fixed in code. Same issue as README item 1, with the operational stagger. The async redeem path removes the “withdraw immediately” exit the original write-up assumed |
| M-01 | Underflow in `addFundsAndFulfillRedeem` blocked redemption of the initial deposit | Fixed | Current code reverts `InsufficientAggregateUnderlyingBalance` instead of underflowing. Idle seed deposits must be swept into the aggregated balance before this function will pay them out |
| M-02 | Price manipulation from update-then-fulfill ordering | Fixed | Current order is transfer, fulfill, then update. Do not report the old order |
| M-03 | No slippage on `deposit` / `mint` | Fixed | Three-argument `deposit` and `mint` exist |
| L-01 | Duplicate `UnderlyingBalanceUpdated` | Acknowledged | Still duplicated. The extra argument is now a checksum. Out of scope (no fund loss) |

`2025-07-02-scope.md` in the repo predates that audit and asks reviewers to spend extra time on `flashRedeem`. Shieldify’s five findings do not include a flash-redeem issue. The function has grown since that review (state snapshots, 0.1% checks). Review the current function. Do not file “flash redeem is powerful” without an unauthorized gain.

### 12.3 Comments that disagree with the code

Use the code if you are deciding whether something is a bug. These mismatches are already visible and are not, by themselves, findings:

- `adminMint` / `adminBurn` say they work while paused. `_update` is `whenNotPaused`, so they revert.
- `VaultFeeUpgradeable._feeOnTotalFlashWithdrawal` has a comment that says it temporarily uses the instant-withdrawal fee. The call passes `FeeOperation.FLASH_REDEEM`.
- Flash-redeem natspec says 0.5% slippage. The check is `< 1e15` (0.1%).
- `lastPricePerShare` vs `convertToAssets(10 ** decimals)` are not the same unit. The percentage checks do not require them to be.
- README “oracle” language. There is no Chainlink or signed-price contract. The oracle is the fund manager’s `uint256`.

---

## 13. What not to open

| Path | Why |
| --- | --- |
| `test/**` | Out of scope. Program rule and this brief |
| `test/mocks/**`, `MockERC20` | Out of scope |
| `script/deployment/*Anvil*`, `*Testnet*` that construct mock tokens | Out of scope |
| `lib/**` | Third-party. Read OZ ERC-4626 and Solmate `RolesAuthority` to understand behavior. Do not hunt them |
| `src/base/Compatible.sol`, `src/interfaces/IWETH9.sol` | Not used by production contracts |
| Branch `v1`, Monad addresses in the README | Different contest surface. Not listed on this program |
| Off-chain backend, StarkEx, exchange accounts, frontend, DNS, API | Out of scope. The backend’s event watcher is context for how NAV updates are timed, not a target |
| ZK circuits | Not in this repo |

A faithful PoC deploys or forks **`MultipliVault` behind its proxy**, with a real `VariableVaultFee` and `RolesAuthority` wired the way section 4 describes. Skipping auth with a mock owner, or calling the implementation address as if it held the USDC, is not a demonstration.

---

## 14. Report checklist

Before submitting:

- The bug is in `src/` (or in live configuration of an in-scope address), not in a test, mock, or unmodified library.
- The caller is not “the owner, using an owner-only function,” unless you show a non-owner path.
- The impact matches section 1.2, and you are not restating section 12.
- The PoC runs. Name the fork block or the local deployment, the addresses, the calls, and the balances before and after.
- Severity is the program’s scale, not a generic audit scale. A chain of bugs is scored once, at the top severity.
- The write-up stays on HackenProof.
