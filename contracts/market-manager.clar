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
(define-data-var market-metric-1 uint u1)
(define-data-var market-metric-2 uint u2)
(define-data-var market-metric-3 uint u3)
(define-data-var market-metric-4 uint u4)
