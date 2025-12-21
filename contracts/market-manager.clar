;; market-manager.clar
;; Decentralized prediction market with verified oracle resolution
;; Uses Clarity 4 features: stacks-block-time, contract-hash?, to-ascii?

;; ========================================
;; Constants
;; ========================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u16001))
(define-constant ERR_MARKET_NOT_FOUND (err u16002))
(define-constant ERR_MARKET_CLOSED (err u16003))
(define-constant ERR_MARKET_NOT_RESOLVED (err u16004))
(define-constant ERR_INVALID_OUTCOME (err u16005))
(define-constant ERR_INVALID_AMOUNT (err u16006))
(define-constant ERR_ALREADY_CLAIMED (err u16007))
(define-constant ERR_ORACLE_NOT_VERIFIED (err u16008))
(define-constant ERR_MARKET_ACTIVE (err u16009))
(define-constant ERR_NO_POSITION (err u16010))
(define-constant ERR_EARLY_BIRD_PERIOD_OVER (err u16011))
(define-constant ERR_INSURANCE_NOT_FOUND (err u16012))
(define-constant ERR_INSURANCE_EXISTS (err u16013))
(define-constant ERR_INVALID_INSURANCE (err u16014))
(define-constant ERR_STAKE_NOT_FOUND (err u16015))
(define-constant ERR_INSUFFICIENT_STAKE (err u16016))
(define-constant ERR_STAKE_LOCKED (err u16017))
(define-constant ERR_LIQUIDITY_NOT_FOUND (err u16018))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u16019))
(define-constant ERR_LIQUIDITY_LOCKED (err u16020))
(define-constant ERR_DERIVATIVE_NOT_FOUND (err u16021))
(define-constant ERR_DERIVATIVE_EXISTS (err u16022))
(define-constant ERR_INVALID_STRIKE (err u16023))
(define-constant ERR_DERIVATIVE_EXPIRED (err u16024))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u16025))
(define-constant ERR_POSITION_EXISTS (err u16026))

;; Market status
(define-constant STATUS_OPEN u0)
(define-constant STATUS_CLOSED u1)
(define-constant STATUS_RESOLVED u2)
(define-constant STATUS_DISPUTED u3)
(define-constant STATUS_CANCELLED u4)

;; Protocol fee: 2% of winnings
(define-constant PROTOCOL_FEE_BPS u200)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var market-counter uint u0)
(define-data-var total-volume uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var contract-principal principal tx-sender)
(define-data-var early-bird-bonus-bps uint u1000)
(define-data-var early-bird-duration uint u86400)
(define-data-var total-early-bird-bonuses uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var insurance-premium-bps uint u500)
(define-data-var insurance-coverage-bps uint u5000)

;; ========================================
;; Data Maps
;; ========================================

;; Markets
(define-map markets
    uint
    {
        question: (string-ascii 256),
        creator: principal,
        oracle-contract: principal,
        outcomes: (list 10 (string-ascii 64)),
        outcome-count: uint,
        resolution-time: uint,
        created-at: uint,
        total-pool: uint,
        winning-outcome: (optional uint),
        status: uint
    }
)

;; Outcome pools (how much bet on each outcome)
(define-map outcome-pools
    { market-id: uint, outcome-index: uint }
    uint
)

;; User positions
(define-map positions
    { market-id: uint, user: principal, outcome-index: uint }
    uint
)

;; Track if user has claimed
(define-map claims
    { market-id: uint, user: principal }
    bool
)

;; Track early bird participants
(define-map early-bird-participants
    { market-id: uint, user: principal }
    {
        bet-time: uint,
        bet-amount: uint,
        bonus-earned: uint
    }
)

;; Verified oracles
(define-map verified-oracles
    principal
    {
        name: (string-ascii 64),
        contract-hash: (buff 32),
        verified-at: uint,
        total-resolutions: uint,
        active: bool
    }
)

;; Bet insurance policies
(define-map bet-insurance
    { market-id: uint, user: principal, outcome-index: uint }
    {
        insured-amount: uint,
        premium-paid: uint,
        coverage-amount: uint,
        purchased-at: uint,
        claimed: bool
    }
)

;; ========================================
;; Liquidity Mining Data Structures
;; ========================================

(define-data-var mining-rewards-per-bet uint u100) ;; Reward points per bet
(define-data-var stake-lock-period uint u604800) ;; 7 days lock period
(define-data-var total-staked uint u0)
(define-data-var total-mining-rewards uint u0)

;; User mining rewards (points earned from betting activity)
(define-map mining-rewards
    principal
    {
        total-earned: uint,
        total-claimed: uint,
        last-updated: uint
    }
)

;; Staked winnings for additional rewards
(define-map staked-winnings
    { user: principal, stake-id: uint }
    {
        amount: uint,
        staked-at: uint,
        unlock-at: uint,
        claimed: bool
    }
)

(define-data-var stake-counter uint u0)

;; Track user stakes
(define-map user-stakes
    principal
    (list 20 uint)
)

;; Market Maker Liquidity System
(define-data-var liquidity-counter uint u0)
(define-data-var total-liquidity-provided uint u0)

(define-map market-liquidity
    { market-id: uint }
    {
        total-liquidity: uint,
        total-shares: uint,
        fees-collected: uint
    }
)

(define-map liquidity-positions
    { provider: principal, market-id: uint }
    {
        shares: uint,
        amount-provided: uint,
        fees-earned: uint,
        provided-at: uint
    }
)

;; ========================================
;; Market Derivatives System
;; ========================================

(define-data-var derivative-counter uint u0)

;; Derivative types: call (bet on price going up), put (bet on price going down)
(define-constant DERIVATIVE_CALL u0)
(define-constant DERIVATIVE_PUT u1)

;; Market derivatives (options contracts)
(define-map market-derivatives
    { derivative-id: uint }
    {
        market-id: uint,
        derivative-type: uint,
        strike-price: uint,  ;; Target price/odds
        premium: uint,       ;; Cost to purchase
        expiry-time: uint,
        creator: principal,
        collateral: uint,
        total-supply: uint,
        sold: uint,
        active: bool,
        settled: bool,
        payout-per-contract: uint
    }
)

;; User derivative positions
(define-map derivative-positions
    { user: principal, derivative-id: uint }
    {
        contracts: uint,
        purchased-at: uint,
        total-cost: uint,
        exercised: bool
    }
)

;; Track derivatives for each market
(define-map market-derivative-list
    { market-id: uint }
    (list 50 uint)
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-current-time)
    stacks-block-time
)

(define-read-only (get-market (market-id uint))
    (map-get? markets market-id)
)

(define-read-only (get-outcome-pool (market-id uint) (outcome-index uint))
    (default-to u0 (map-get? outcome-pools { market-id: market-id, outcome-index: outcome-index }))
)

(define-read-only (get-position (market-id uint) (user principal) (outcome-index uint))
    (default-to u0 (map-get? positions { market-id: market-id, user: user, outcome-index: outcome-index }))
)

(define-read-only (has-claimed (market-id uint) (user principal))
    (default-to false (map-get? claims { market-id: market-id, user: user }))
)

;; Check if oracle is verified using contract-hash?
(define-read-only (is-oracle-verified (oracle-contract principal))
    (match (map-get? verified-oracles oracle-contract)
        oracle (and
            (get active oracle)
            (match (contract-hash? oracle-contract)
                ok-hash (is-eq ok-hash (get contract-hash oracle))
                err-val false
            )
        )
        false
    )
)

;; Get odds for an outcome (implied probability)
(define-read-only (get-outcome-odds (market-id uint) (outcome-index uint))
    (match (map-get? markets market-id)
        market (let
            (
                (outcome-pool (get-outcome-pool market-id outcome-index))
                (total-pool (get total-pool market))
            )
            (if (is-eq total-pool u0)
                u0
                (/ (* outcome-pool u10000) total-pool)
            )
        )
        u0
    )
)

;; Calculate potential payout for a bet
(define-read-only (calculate-payout (market-id uint) (outcome-index uint) (bet-amount uint))
    (match (map-get? markets market-id)
        market (let
            (
                (outcome-pool (get-outcome-pool market-id outcome-index))
                (total-pool (get total-pool market))
                (new-total (+ total-pool bet-amount))
                (new-outcome-pool (+ outcome-pool bet-amount))
            )
            (if (is-eq new-outcome-pool u0)
                u0
                (/ (* bet-amount new-total) new-outcome-pool)
            )
        )
        u0
    )
)

;; Calculate actual winnings for user
(define-read-only (calculate-winnings (market-id uint) (user principal))
    (match (map-get? markets market-id)
        market (match (get winning-outcome market)
            winning-index (let
                (
                    (user-position (get-position market-id user winning-index))
                    (winning-pool (get-outcome-pool market-id winning-index))
                    (total-pool (get total-pool market))
                )
                (if (or (is-eq user-position u0) (is-eq winning-pool u0))
                    u0
                    (/ (* user-position total-pool) winning-pool)
                )
            )
            u0
        )
        u0
    )
)

;; Get insurance policy
(define-read-only (get-insurance (market-id uint) (user principal) (outcome-index uint))
    (map-get? bet-insurance { market-id: market-id, user: user, outcome-index: outcome-index })
)

;; Check if user has insurance
(define-read-only (has-insurance (market-id uint) (user principal) (outcome-index uint))
    (is-some (get-insurance market-id user outcome-index))
)

;; Calculate insurance premium
(define-read-only (calculate-insurance-premium (bet-amount uint))
    (/ (* bet-amount (var-get insurance-premium-bps)) u10000)
)

;; Calculate insurance coverage
(define-read-only (calculate-insurance-coverage (bet-amount uint))
    (/ (* bet-amount (var-get insurance-coverage-bps)) u10000)
)

;; Generate market info message using to-ascii?
(define-read-only (generate-market-info (market-id uint))
    (match (map-get? markets market-id)
        market (let
            (
                (id-str (unwrap-panic (to-ascii? market-id)))
                (pool-str (unwrap-panic (to-ascii? (get total-pool market))))
                (status-str (unwrap-panic (to-ascii? (get status market))))
            )
            (concat
                (concat (concat "Market #" id-str) ": ")
                (concat (get question market)
                    (concat (concat " | Pool: " pool-str) (concat " | Status: " status-str))
                )
            )
        )
        "Market not found"
    )
)

;; Generate outcome odds message
(define-read-only (generate-odds-message (market-id uint) (outcome-index uint))
    (match (map-get? markets market-id)
        market (let
            (
                (odds (get-outcome-odds market-id outcome-index))
                (odds-str (unwrap-panic (to-ascii? odds)))
                (outcome-name (unwrap! (element-at? (get outcomes market) outcome-index) "Unknown"))
            )
            (concat 
                (concat outcome-name ": ")
                (concat odds-str " bps (implied probability)")
            )
        )
        "Market not found"
    )
)

;; Get protocol stats
(define-read-only (get-protocol-stats)
    {
        total-markets: (var-get market-counter),
        total-volume: (var-get total-volume),
        total-fees: (var-get total-fees-collected),
        current-time: stacks-block-time
    }
)

;; Check if market is open for betting
(define-read-only (is-market-open (market-id uint))
    (match (map-get? markets market-id)
        market (and 
            (is-eq (get status market) STATUS_OPEN)
            (< stacks-block-time (get resolution-time market))
        )
        false
    )
)

;; ========================================
;; Liquidity Mining Read-Only Functions
;; ========================================

(define-read-only (get-mining-rewards (user principal))
    (default-to
        { total-earned: u0, total-claimed: u0, last-updated: u0 }
        (map-get? mining-rewards user)
    )
)

(define-read-only (get-stake (user principal) (stake-id uint))
    (map-get? staked-winnings { user: user, stake-id: stake-id })
)

(define-read-only (get-user-stakes (user principal))
    (default-to (list) (map-get? user-stakes user))
)

(define-read-only (is-stake-unlocked (user principal) (stake-id uint))
    (match (get-stake user stake-id)
        stake (>= stacks-block-time (get unlock-at stake))
        false
    )
)

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-mining-stats)
    {
        total-staked: (var-get total-staked),
        total-mining-rewards: (var-get total-mining-rewards),
        rewards-per-bet: (var-get mining-rewards-per-bet),
        stake-lock-period: (var-get stake-lock-period)
    }
)

;; ========================================
;; Derivative Read-Only Functions
;; ========================================

(define-read-only (get-derivative (derivative-id uint))
    (map-get? market-derivatives { derivative-id: derivative-id })
)

(define-read-only (get-derivative-position (user principal) (derivative-id uint))
    (map-get? derivative-positions { user: user, derivative-id: derivative-id })
)

(define-read-only (get-market-derivatives (market-id uint))
    (default-to (list) (map-get? market-derivative-list { market-id: market-id }))
)

(define-read-only (calculate-derivative-value (derivative-id uint) (current-odds uint))
    (match (get-derivative derivative-id)
        deriv (let
            (
                (strike (get strike-price deriv))
                (deriv-type (get derivative-type deriv))
            )
            (if (is-eq deriv-type DERIVATIVE_CALL)
                ;; Call option: value = max(current - strike, 0)
                (if (> current-odds strike)
                    (- current-odds strike)
                    u0)
                ;; Put option: value = max(strike - current, 0)
                (if (> strike current-odds)
                    (- strike current-odds)
                    u0)))
        u0)
)

(define-read-only (get-derivative-stats (derivative-id uint))
    (match (get-derivative derivative-id)
        deriv {
            market-id: (get market-id deriv),
            derivative-type: (get derivative-type deriv),
            strike-price: (get strike-price deriv),
            premium: (get premium deriv),
            total-supply: (get total-supply deriv),
            sold: (get sold deriv),
            active: (get active deriv),
            settled: (get settled deriv)
        }
        {
            market-id: u0,
            derivative-type: u0,
            strike-price: u0,
            premium: u0,
            total-supply: u0,
            sold: u0,
            active: false,
            settled: false
        })
)

;; ========================================
;; Oracle Management
;; ========================================

;; Verify an oracle contract
(define-public (verify-oracle (oracle-contract principal) (name (string-ascii 64)))
    (let
        (
            (oracle-hash (unwrap! (contract-hash? oracle-contract) ERR_ORACLE_NOT_VERIFIED))
            (current-time stacks-block-time)
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set verified-oracles oracle-contract {
            name: name,
            contract-hash: oracle-hash,
            verified-at: current-time,
            total-resolutions: u0,
            active: true
        })
        
        (ok true)
    )
)

;; Revoke oracle verification
(define-public (revoke-oracle (oracle-contract principal))
    (let
        (
            (oracle (unwrap! (map-get? verified-oracles oracle-contract) ERR_ORACLE_NOT_VERIFIED))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set verified-oracles oracle-contract (merge oracle { active: false }))
        
        (ok true)
    )
)

;; ========================================
;; Market Management
;; ========================================

;; Create a new prediction market
(define-public (create-market
    (question (string-ascii 256))
    (outcomes (list 10 (string-ascii 64)))
    (resolution-time uint)
    (oracle-contract principal))
    (let
        (
            (caller tx-sender)
            (market-id (+ (var-get market-counter) u1))
            (current-time stacks-block-time)
            (outcome-count (len outcomes))
        )
        ;; Validations
        (asserts! (is-oracle-verified oracle-contract) ERR_ORACLE_NOT_VERIFIED)
        (asserts! (> resolution-time current-time) ERR_INVALID_AMOUNT)
        (asserts! (>= outcome-count u2) ERR_INVALID_OUTCOME)
        (asserts! (<= outcome-count u10) ERR_INVALID_OUTCOME)
        
        ;; Create market
        (map-set markets market-id {
            question: question,
            creator: caller,
            oracle-contract: oracle-contract,
            outcomes: outcomes,
            outcome-count: outcome-count,
            resolution-time: resolution-time,
            created-at: current-time,
            total-pool: u0,
            winning-outcome: none,
            status: STATUS_OPEN
        })
        
        ;; Initialize outcome pools
        (map-set outcome-pools { market-id: market-id, outcome-index: u0 } u0)
        (map-set outcome-pools { market-id: market-id, outcome-index: u1 } u0)
        
        (var-set market-counter market-id)
        
        ;; Print market info
        (print (generate-market-info market-id))
        
        (ok market-id)
    )
)

;; Place a bet on an outcome
(define-public (place-bet (market-id uint) (outcome-index uint) (amount uint))
    (let
        (
            (caller tx-sender)
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (current-position (get-position market-id caller outcome-index))
            (current-outcome-pool (get-outcome-pool market-id outcome-index))
        )
        ;; Validations
        (asserts! (is-market-open market-id) ERR_MARKET_CLOSED)
        (asserts! (< outcome-index (get outcome-count market)) ERR_INVALID_OUTCOME)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)

        ;; Transfer bet to contract
        (try! (stx-transfer? amount caller (var-get contract-principal)))

        ;; Update user position
        (map-set positions
            { market-id: market-id, user: caller, outcome-index: outcome-index }
            (+ current-position amount)
        )

        ;; Update outcome pool
        (map-set outcome-pools
            { market-id: market-id, outcome-index: outcome-index }
            (+ current-outcome-pool amount)
        )

        ;; Update market total
        (map-set markets market-id (merge market {
            total-pool: (+ (get total-pool market) amount)
        }))

        ;; Update total volume
        (var-set total-volume (+ (var-get total-volume) amount))

        ;; Check and reward early bird
        (let ((is-early-bird (< (- stacks-block-time (get created-at market)) (var-get early-bird-duration))))
            (if is-early-bird
                (let ((bonus (/ (* amount (var-get early-bird-bonus-bps)) u10000)))
                    (begin
                        (map-set early-bird-participants { market-id: market-id, user: caller } {
                            bet-time: stacks-block-time,
                            bet-amount: amount,
                            bonus-earned: bonus
                        })
                        (var-set total-early-bird-bonuses (+ (var-get total-early-bird-bonuses) bonus))
                        (print { event: "early-bird-bonus", market-id: market-id, user: caller, bonus: bonus, timestamp: stacks-block-time })
                        true))
                true))

        ;; Print odds update
        (print (generate-odds-message market-id outcome-index))

        (ok amount)
    )
)

;; Close market for betting (automatic at resolution time)
(define-public (close-market (market-id uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (current-time stacks-block-time)
        )
        ;; Must be at or past resolution time
        (asserts! (>= current-time (get resolution-time market)) ERR_MARKET_ACTIVE)
        (asserts! (is-eq (get status market) STATUS_OPEN) ERR_MARKET_CLOSED)
        
        (map-set markets market-id (merge market { status: STATUS_CLOSED }))
        
        (ok true)
    )
)

;; Resolve market (oracle only)
(define-public (resolve-market (market-id uint) (winning-outcome uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (oracle (unwrap! (map-get? verified-oracles (get oracle-contract market)) ERR_ORACLE_NOT_VERIFIED))
        )
        ;; Only designated oracle can resolve
        (asserts! (is-eq tx-sender (get oracle-contract market)) ERR_NOT_AUTHORIZED)
        (asserts! (or 
            (is-eq (get status market) STATUS_OPEN)
            (is-eq (get status market) STATUS_CLOSED)
        ) ERR_MARKET_NOT_RESOLVED)
        (asserts! (< winning-outcome (get outcome-count market)) ERR_INVALID_OUTCOME)
        
        ;; Verify oracle contract hasn't changed
        (asserts! (is-oracle-verified (get oracle-contract market)) ERR_ORACLE_NOT_VERIFIED)
        
        ;; Update market
        (map-set markets market-id (merge market {
            winning-outcome: (some winning-outcome),
            status: STATUS_RESOLVED
        }))
        
        ;; Update oracle stats
        (map-set verified-oracles (get oracle-contract market) (merge oracle {
            total-resolutions: (+ (get total-resolutions oracle) u1)
        }))
        
        (ok winning-outcome)
    )
)

;; Claim winnings
(define-public (claim-winnings (market-id uint))
    (let
        (
            (caller tx-sender)
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (winnings (calculate-winnings market-id caller))
            (fee (/ (* winnings PROTOCOL_FEE_BPS) u10000))
            (net-winnings (- winnings fee))
        )
        ;; Validations
        (asserts! (is-eq (get status market) STATUS_RESOLVED) ERR_MARKET_NOT_RESOLVED)
        (asserts! (not (has-claimed market-id caller)) ERR_ALREADY_CLAIMED)
        (asserts! (> winnings u0) ERR_NO_POSITION)
        
        ;; Mark as claimed
        (map-set claims { market-id: market-id, user: caller } true)
        
        ;; Transfer winnings
        (try! (stx-transfer? net-winnings (var-get contract-principal) caller))

        ;; Transfer fee
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))
        
        ;; Update fees collected
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        
        (ok net-winnings)
    )
)

;; Cancel market and refund all bets (admin only)
(define-public (cancel-market (market-id uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (not (is-eq (get status market) STATUS_RESOLVED)) ERR_MARKET_NOT_RESOLVED)
        
        (map-set markets market-id (merge market { status: STATUS_CANCELLED }))
        
        (ok true)
    )
)

;; Claim refund from cancelled market
(define-public (claim-refund (market-id uint) (outcome-index uint))
    (let
        (
            (caller tx-sender)
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (position (get-position market-id caller outcome-index))
        )
        (asserts! (is-eq (get status market) STATUS_CANCELLED) ERR_MARKET_ACTIVE)
        (asserts! (> position u0) ERR_NO_POSITION)
        (asserts! (not (has-claimed market-id caller)) ERR_ALREADY_CLAIMED)
        
        ;; Mark as claimed
        (map-set claims { market-id: market-id, user: caller } true)
        
        ;; Clear position
        (map-set positions { market-id: market-id, user: caller, outcome-index: outcome-index } u0)
        
        ;; Refund
        (try! (stx-transfer? position (var-get contract-principal) caller))
        
        (ok position)
    )
)

;; ========================================
;; Bet Insurance Functions
;; ========================================

;; Purchase insurance for a bet
(define-public (purchase-insurance (market-id uint) (outcome-index uint) (bet-amount uint))
    (let (
        (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
        (position (get-position market-id tx-sender outcome-index))
        (premium (calculate-insurance-premium bet-amount))
        (coverage (calculate-insurance-coverage bet-amount))
        (current-time stacks-block-time)
        )
        ;; Validations
        (asserts! (is-eq (get status market) STATUS_OPEN) ERR_MARKET_CLOSED)
        (asserts! (> bet-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= bet-amount position) ERR_INVALID_INSURANCE)
        (asserts! (is-none (get-insurance market-id tx-sender outcome-index)) ERR_INSURANCE_EXISTS)

        ;; Pay insurance premium
        (try! (stx-transfer? premium tx-sender (var-get contract-principal)))

        ;; Create insurance policy
        (map-set bet-insurance
            { market-id: market-id, user: tx-sender, outcome-index: outcome-index }
            {
                insured-amount: bet-amount,
                premium-paid: premium,
                coverage-amount: coverage,
                purchased-at: current-time,
                claimed: false
            }
        )

        ;; Update insurance pool
        (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) premium))

        (print {
            event: "insurance-purchased",
            market-id: market-id,
            user: tx-sender,
            outcome-index: outcome-index,
            insured-amount: bet-amount,
            premium: premium,
            coverage: coverage,
            timestamp: current-time
        })

        (ok { premium: premium, coverage: coverage })
    )
)

;; Claim insurance payout (for losing bets)
(define-public (claim-insurance-payout (market-id uint) (outcome-index uint))
    (let (
        (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
        (insurance (unwrap! (get-insurance market-id tx-sender outcome-index) ERR_INSURANCE_NOT_FOUND))
        (winning-outcome (unwrap! (get winning-outcome market) ERR_MARKET_NOT_RESOLVED))
        )
        ;; Validations
        (asserts! (is-eq (get status market) STATUS_RESOLVED) ERR_MARKET_NOT_RESOLVED)
        (asserts! (not (get claimed insurance)) ERR_ALREADY_CLAIMED)
        (asserts! (not (is-eq outcome-index winning-outcome)) ERR_INVALID_OUTCOME) ;; Can only claim if lost

        ;; Mark as claimed
        (map-set bet-insurance
            { market-id: market-id, user: tx-sender, outcome-index: outcome-index }
            (merge insurance { claimed: true })
        )

        ;; Pay coverage
        (try! (stx-transfer? (get coverage-amount insurance) (var-get contract-principal) tx-sender))

        ;; Update insurance pool
        (var-set insurance-pool-balance (- (var-get insurance-pool-balance) (get coverage-amount insurance)))

        (print {
            event: "insurance-claimed",
            market-id: market-id,
            user: tx-sender,
            outcome-index: outcome-index,
            payout: (get coverage-amount insurance),
            timestamp: stacks-block-time
        })

        (ok (get coverage-amount insurance))
    )
)

;; Admin: Update insurance parameters
(define-public (update-insurance-params (premium-bps uint) (coverage-bps uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= premium-bps u1000) ERR_INVALID_INSURANCE) ;; Max 10% premium
        (asserts! (<= coverage-bps u10000) ERR_INVALID_INSURANCE) ;; Max 100% coverage
        
        (var-set insurance-premium-bps premium-bps)
        (var-set insurance-coverage-bps coverage-bps)
        
        (print {
            event: "insurance-params-updated",
            premium-bps: premium-bps,
            coverage-bps: coverage-bps,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; ========================================
;; Liquidity Mining Public Functions
;; ========================================

;; Stake winnings for additional rewards
(define-public (stake-winnings (amount uint))
    (let
        (
            (stake-id (var-get stake-counter))
            (current-time stacks-block-time)
            (unlock-time (+ current-time (var-get stake-lock-period)))
            (user-stake-list (get-user-stakes tx-sender))
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)

        ;; Transfer STX to contract
        (unwrap! (stx-transfer? amount tx-sender (var-get contract-principal)) ERR_INVALID_AMOUNT)

        ;; Create stake record
        (map-set staked-winnings
            { user: tx-sender, stake-id: stake-id }
            {
                amount: amount,
                staked-at: current-time,
                unlock-at: unlock-time,
                claimed: false
            }
        )

        ;; Track user stakes
        (map-set user-stakes
            tx-sender
            (unwrap! (as-max-len? (append user-stake-list stake-id) u20) ERR_INVALID_AMOUNT)
        )

        ;; Update totals
        (var-set stake-counter (+ stake-id u1))
        (var-set total-staked (+ (var-get total-staked) amount))

        (print {
            event: "winnings-staked",
            user: tx-sender,
            stake-id: stake-id,
            amount: amount,
            unlock-at: unlock-time,
            timestamp: current-time
        })

        (ok stake-id)
    )
)

;; Unstake after lock period with 10% bonus
(define-public (unstake (stake-id uint))
    (let
        (
            (stake (unwrap! (get-stake tx-sender stake-id) ERR_STAKE_NOT_FOUND))
            (current-time stacks-block-time)
            (bonus (/ (get amount stake) u10))
        )
        (asserts! (not (get claimed stake)) ERR_ALREADY_CLAIMED)
        (asserts! (>= current-time (get unlock-at stake)) ERR_STAKE_LOCKED)

        ;; Mark as claimed
        (map-set staked-winnings
            { user: tx-sender, stake-id: stake-id }
            (merge stake { claimed: true })
        )

        ;; Transfer back with bonus
        (unwrap! (stx-transfer? (+ (get amount stake) bonus) (var-get contract-principal) tx-sender) ERR_INVALID_AMOUNT)

        ;; Update total staked
        (var-set total-staked (- (var-get total-staked) (get amount stake)))

        (print {
            event: "winnings-unstaked",
            user: tx-sender,
            stake-id: stake-id,
            amount: (get amount stake),
            bonus: bonus,
            timestamp: current-time
        })

        (ok true)
    )
)

;; Admin: Update mining parameters
(define-public (set-mining-params (rewards-per-bet uint) (lock-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> rewards-per-bet u0) ERR_INVALID_AMOUNT)
        (asserts! (> lock-period u0) ERR_INVALID_AMOUNT)

        (var-set mining-rewards-per-bet rewards-per-bet)
        (var-set stake-lock-period lock-period)

        (print {
            event: "mining-params-updated",
            rewards-per-bet: rewards-per-bet,
            lock-period: lock-period,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Provide liquidity to market
(define-public (provide-liquidity (market-id uint) (amount uint))
    (let ((market (unwrap! (get-market market-id) ERR_MARKET_NOT_FOUND))
          (liq (default-to { total-liquidity: u0, total-shares: u0, fees-collected: u0 }
                           (map-get? market-liquidity { market-id: market-id })))
          (shares (if (is-eq (get total-shares liq) u0) amount
                      (/ (* amount (get total-shares liq)) (get total-liquidity liq)))))
        (unwrap! (stx-transfer? amount tx-sender (var-get contract-principal)) ERR_INVALID_AMOUNT)
        (map-set market-liquidity { market-id: market-id }
            { total-liquidity: (+ (get total-liquidity liq) amount),
              total-shares: (+ (get total-shares liq) shares),
              fees-collected: (get fees-collected liq) })
        (map-set liquidity-positions { provider: tx-sender, market-id: market-id }
            { shares: shares, amount-provided: amount, fees-earned: u0, provided-at: stacks-block-time })
        (print { event: "liquidity-provided", market-id: market-id, provider: tx-sender, amount: amount, shares: shares })
        (ok shares)))

;; Withdraw liquidity from market
(define-public (withdraw-liquidity (market-id uint) (shares uint))
    (let ((pos (unwrap! (map-get? liquidity-positions { provider: tx-sender, market-id: market-id }) ERR_LIQUIDITY_NOT_FOUND))
          (liq (unwrap! (map-get? market-liquidity { market-id: market-id }) ERR_LIQUIDITY_NOT_FOUND))
          (amount (/ (* shares (get total-liquidity liq)) (get total-shares liq))))
        (asserts! (>= (get shares pos) shares) ERR_INSUFFICIENT_LIQUIDITY)
        (unwrap! (stx-transfer? amount (var-get contract-principal) tx-sender) ERR_INSUFFICIENT_LIQUIDITY)
        (map-set market-liquidity { market-id: market-id }
            { total-liquidity: (- (get total-liquidity liq) amount),
              total-shares: (- (get total-shares liq) shares),
              fees-collected: (get fees-collected liq) })
        (print { event: "liquidity-withdrawn", market-id: market-id, provider: tx-sender, amount: amount })
        (ok amount)))

;; ========================================
;; Market Derivatives Public Functions
;; ========================================

;; Create derivative contract for a market
(define-public (create-derivative (market-id uint) (derivative-type uint) (strike-price uint) (premium uint) (total-supply uint) (expiry-duration uint) (collateral uint))
    (let
        (
            (market (unwrap! (get-market market-id) ERR_MARKET_NOT_FOUND))
            (derivative-id (+ (var-get derivative-counter) u1))
            (current-time stacks-block-time)
            (expiry-time (+ current-time expiry-duration))
            (derivatives-list (get-market-derivatives market-id))
        )
        (asserts! (is-eq (get status market) STATUS_OPEN) ERR_MARKET_CLOSED)
        (asserts! (or (is-eq derivative-type DERIVATIVE_CALL) (is-eq derivative-type DERIVATIVE_PUT)) ERR_INVALID_OUTCOME)
        (asserts! (> strike-price u0) ERR_INVALID_STRIKE)
        (asserts! (> premium u0) ERR_INVALID_AMOUNT)
        (asserts! (> total-supply u0) ERR_INVALID_AMOUNT)
        (asserts! (> collateral u0) ERR_INSUFFICIENT_COLLATERAL)
        
        ;; Transfer collateral to contract
        (try! (stx-transfer? collateral tx-sender (var-get contract-principal)))
        
        ;; Create derivative
        (map-set market-derivatives
            { derivative-id: derivative-id }
            {
                market-id: market-id,
                derivative-type: derivative-type,
                strike-price: strike-price,
                premium: premium,
                expiry-time: expiry-time,
                creator: tx-sender,
                collateral: collateral,
                total-supply: total-supply,
                sold: u0,
                active: true,
                settled: false,
                payout-per-contract: u0
            }
        )
        
        ;; Add to market derivative list
        (map-set market-derivative-list
            { market-id: market-id }
            (unwrap! (as-max-len? (append derivatives-list derivative-id) u50) ERR_INVALID_AMOUNT)
        )
        
        (var-set derivative-counter derivative-id)
        
        (print {
            event: "derivative-created",
            derivative-id: derivative-id,
            market-id: market-id,
            derivative-type: derivative-type,
            strike-price: strike-price,
            premium: premium,
            total-supply: total-supply,
            creator: tx-sender,
            timestamp: current-time
        })
        
        (ok derivative-id)
    )
)

;; Purchase derivative contracts
(define-public (purchase-derivative (derivative-id uint) (contracts uint))
    (let
        (
            (deriv (unwrap! (get-derivative derivative-id) ERR_DERIVATIVE_NOT_FOUND))
            (existing-position (get-derivative-position tx-sender derivative-id))
            (cost (* contracts (get premium deriv)))
            (new-sold (+ (get sold deriv) contracts))
        )
        (asserts! (get active deriv) ERR_DERIVATIVE_EXPIRED)
        (asserts! (>= (get expiry-time deriv) stacks-block-time) ERR_DERIVATIVE_EXPIRED)
        (asserts! (> contracts u0) ERR_INVALID_AMOUNT)
        (asserts! (<= new-sold (get total-supply deriv)) ERR_INSUFFICIENT_LIQUIDITY)
        
        ;; Transfer payment to creator
        (try! (stx-transfer? cost tx-sender (get creator deriv)))
        
        ;; Update or create position
        (match existing-position
            position (map-set derivative-positions
                { user: tx-sender, derivative-id: derivative-id }
                {
                    contracts: (+ (get contracts position) contracts),
                    purchased-at: (get purchased-at position),
                    total-cost: (+ (get total-cost position) cost),
                    exercised: false
                })
            (map-set derivative-positions
                { user: tx-sender, derivative-id: derivative-id }
                {
                    contracts: contracts,
                    purchased-at: stacks-block-time,
                    total-cost: cost,
                    exercised: false
                }))
        
        ;; Update derivative
        (map-set market-derivatives
            { derivative-id: derivative-id }
            (merge deriv { sold: new-sold })
        )
        
        (print {
            event: "derivative-purchased",
            derivative-id: derivative-id,
            buyer: tx-sender,
            contracts: contracts,
            cost: cost,
            timestamp: stacks-block-time
        })
        
        (ok true)
    )
)

;; Settle derivative based on market outcome
(define-public (settle-derivative (derivative-id uint) (final-odds uint))
    (let
        (
            (deriv (unwrap! (get-derivative derivative-id) ERR_DERIVATIVE_NOT_FOUND))
            (market (unwrap! (get-market (get market-id deriv)) ERR_MARKET_NOT_FOUND))
            (intrinsic-value (calculate-derivative-value derivative-id final-odds))
            (payout (if (> intrinsic-value u0) intrinsic-value u0))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status market) STATUS_RESOLVED) ERR_MARKET_NOT_RESOLVED)
        (asserts! (not (get settled deriv)) ERR_ALREADY_CLAIMED)
        
        ;; Mark as settled
        (map-set market-derivatives
            { derivative-id: derivative-id }
            (merge deriv {
                settled: true,
                active: false,
                payout-per-contract: payout
            })
        )
        
        (print {
            event: "derivative-settled",
            derivative-id: derivative-id,
            final-odds: final-odds,
            payout-per-contract: payout,
            timestamp: stacks-block-time
        })
        
        (ok payout)
    )
)

;; Exercise/claim derivative payout
(define-public (exercise-derivative (derivative-id uint))
    (let
        (
            (deriv (unwrap! (get-derivative derivative-id) ERR_DERIVATIVE_NOT_FOUND))
            (position (unwrap! (get-derivative-position tx-sender derivative-id) ERR_NO_POSITION))
            (total-payout (* (get contracts position) (get payout-per-contract deriv)))
        )
        (asserts! (get settled deriv) ERR_MARKET_NOT_RESOLVED)
        (asserts! (not (get exercised position)) ERR_ALREADY_CLAIMED)
        (asserts! (> total-payout u0) ERR_INVALID_AMOUNT)
        
        ;; Transfer payout to user
        (try! (stx-transfer? total-payout (var-get contract-principal) tx-sender))
        
        ;; Mark as exercised
        (map-set derivative-positions
            { user: tx-sender, derivative-id: derivative-id }
            (merge position { exercised: true })
        )
        
        (print {
            event: "derivative-exercised",
            derivative-id: derivative-id,
            user: tx-sender,
            contracts: (get contracts position),
            payout: total-payout,
            timestamp: stacks-block-time
        })
        
        (ok total-payout)
    )
)

;; Cancel derivative if not sold out (creator only)
(define-public (cancel-derivative (derivative-id uint))
    (let
        (
            (deriv (unwrap! (get-derivative derivative-id) ERR_DERIVATIVE_NOT_FOUND))
            (refund (get collateral deriv))
        )
        (asserts! (is-eq tx-sender (get creator deriv)) ERR_NOT_AUTHORIZED)
        (asserts! (get active deriv) ERR_DERIVATIVE_EXPIRED)
        (asserts! (is-eq (get sold deriv) u0) ERR_POSITION_EXISTS)
        
        ;; Refund collateral to creator
        (try! (stx-transfer? refund (var-get contract-principal) tx-sender))
        
        ;; Mark as inactive
        (map-set market-derivatives
            { derivative-id: derivative-id }
            (merge deriv { active: false })
        )
        
        (print {
            event: "derivative-cancelled",
            derivative-id: derivative-id,
            creator: tx-sender,
            refund: refund,
            timestamp: stacks-block-time
        })
        
        (ok refund)
    )
)

