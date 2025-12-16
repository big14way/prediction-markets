# Decentralized Prediction Market

Create markets on any outcome with verified oracle resolution and trustless payouts on Stacks.

## Clarity 4 Features Used

| Feature | Usage |
|---------|-------|
| `stacks-block-time` | Market open/close times, betting deadlines |
| `contract-hash?` | Verify oracle contracts before trusting resolution |
| `to-ascii?` | Generate market descriptions, odds messages |
| `restrict-assets?` | Safe bet placement and payout distribution |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Oracle Registry                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  contract-hash?() → Verify oracle code integrity      │   │
│  │  Track reputation, resolutions, disputes             │   │
│  │  Slash malicious oracles                             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Market Manager                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  create-market() → Define question, outcomes, oracle  │   │
│  │  place-bet() → Bet on outcome with STX               │   │
│  │  stacks-block-time → Manage betting windows          │   │
│  │  resolve-market() → Oracle submits result            │   │
│  │  claim-winnings() → Winners collect payout           │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Oracle Verification**: Admin verifies oracle contracts via `contract-hash?`
2. **Market Creation**: Anyone creates market with verified oracle
3. **Betting Period**: Users bet on outcomes until resolution time
4. **Resolution**: Designated oracle submits winning outcome
5. **Payout**: Winners claim proportional share of pool minus 2% fee

## Market Types

| Type | Example Question | Oracle Type |
|------|-----------------|-------------|
| Sports | "Will Lakers win NBA Finals?" | Sports Oracle |
| Crypto | "Will BTC hit $100k by EOY?" | Price Oracle |
| Politics | "Who wins 2028 election?" | Election Oracle |
| Weather | "Will it rain in NYC tomorrow?" | Weather Oracle |
| Custom | "Will SpaceX land on Mars by 2030?" | Custom Oracle |

## Contract Functions

### Oracle Management

```clarity
;; Verify an oracle (admin)
(verify-oracle (oracle-contract principal) (name (string-ascii 64)))

;; Check oracle validity
(is-oracle-verified (oracle-contract principal))

;; Revoke oracle
(revoke-oracle (oracle-contract principal))
```

### Market Creation

```clarity
;; Create a prediction market
(create-market
    (question (string-ascii 256))
    (outcomes (list 10 (string-ascii 64)))
    (resolution-time uint)
    (oracle-contract principal))
```

### Betting

```clarity
;; Place a bet
(place-bet (market-id uint) (outcome-index uint) (amount uint))

;; Check if market is open
(is-market-open (market-id uint))
```

### Resolution & Payout

```clarity
;; Resolve market (oracle only)
(resolve-market (market-id uint) (winning-outcome uint))

;; Claim winnings
(claim-winnings (market-id uint))

;; Calculate potential winnings
(calculate-winnings (market-id uint) (user principal))
```

### Read-Only Helpers

```clarity
;; Get current odds for outcome
(get-outcome-odds (market-id uint) (outcome-index uint))

;; Calculate potential payout for bet
(calculate-payout (market-id uint) (outcome-index uint) (bet-amount uint))

;; Generate market info
(generate-market-info (market-id uint))
;; Returns: "Market #1: Will BTC hit $100k? | Pool: 5000000000 | Status: 0"

;; Generate odds message
(generate-odds-message (market-id uint) (outcome-index uint))
;; Returns: "Yes: 6500 bps (implied probability)"
```

## Fee Structure

| Fee | Rate | When Applied |
|-----|------|--------------|
| Protocol Fee | 2% | On winnings claim |

Example: 100 STX winnings → 98 STX to winner, 2 STX to protocol

## Odds & Payout Calculation

**Odds** (implied probability):
```
odds = (outcome_pool / total_pool) × 10000
```

**Potential Payout**:
```
payout = (bet_amount × total_pool) / outcome_pool
```

**Example**:
- Total pool: 1000 STX
- "Yes" pool: 400 STX
- "No" pool: 600 STX
- Bet 100 STX on "Yes"
- If "Yes" wins: 100 × (1100/500) = 220 STX payout

## Oracle System

### Verification Process

1. Admin reviews oracle contract code
2. Contract hash captured via `contract-hash?`
3. Oracle registered with type and stake
4. Any code change invalidates verification

### Reputation System

- **Reliability Score**: (successful / total) resolutions
- **Stake**: Collateral slashed for disputes
- **History**: Track all resolutions

```clarity
;; Check oracle can resolve
(can-oracle-resolve (oracle-id uint))

;; Get reliability score (0-10000 bps)
(get-reliability-score (oracle-id uint))
```

## Security Features

1. **Oracle Verification**: Only approved oracles via `contract-hash?`
2. **Asset Protection**: `restrict-assets?` on all transfers
3. **Time Bounds**: Markets close automatically at resolution time
4. **Dispute System**: Admin can cancel questionable markets
5. **Refund Mechanism**: Full refund if market cancelled

## Installation & Testing

```bash
cd prediction-market
clarinet check
clarinet test
```

## Example: Create Sports Market

```typescript
// 1. Verify sports oracle
await verifyOracle({
    oracleContract: 'ST...sports-oracle',
    name: "ESPN Sports Oracle"
});

// 2. Create market
const now = await getCurrentTime();
const oneWeek = 604800;

const marketId = await createMarket({
    question: "Will Lakers win 2025 NBA Finals?",
    outcomes: ["Yes", "No"],
    resolutionTime: now + oneWeek,
    oracleContract: 'ST...sports-oracle'
});

// 3. Users place bets
await placeBet(marketId, 0, 50000000); // 50 STX on Yes
await placeBet(marketId, 1, 30000000); // 30 STX on No

// 4. Check odds
const yesOdds = await getOutcomeOdds(marketId, 0);
// Returns: 6250 (62.5% implied probability)

// 5. Oracle resolves (Lakers win)
await resolveMarket(marketId, 0); // 0 = Yes

// 6. Winner claims
const winnings = await claimWinnings(marketId);
```

## Market Lifecycle

```
OPEN → CLOSED → RESOLVED
  ↓                 ↓
  └── CANCELLED ←───┘
         ↓
      (Refunds)
```

## Hiro Chainhooks Integration

Monitor prediction market activity in real-time using Hiro Chainhooks.

### Monitored Events

- Market creation and configuration
- Bet placements and position updates
- Oracle reports and resolutions
- Market resolutions and outcome determinations
- Payout claims by winners

### Quick Start

```bash
cd chainhooks
npm install
cp .env.example .env
npm start
```

See `chainhooks/README.md` for detailed documentation.

## License

MIT License
