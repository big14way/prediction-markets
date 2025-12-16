;; oracle-registry.clar
;; Registry and verification system for prediction market oracles
;; Uses Clarity 4 features: contract-hash?, stacks-block-time, to-ascii?

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u16101))
(define-constant ERR_ORACLE_NOT_FOUND (err u16102))
(define-constant ERR_ORACLE_EXISTS (err u16103))
(define-constant ERR_INVALID_PARAMS (err u16104))

;; Oracle types
(define-constant ORACLE_TYPE_SPORTS u0)
(define-constant ORACLE_TYPE_CRYPTO u1)
(define-constant ORACLE_TYPE_POLITICS u2)
(define-constant ORACLE_TYPE_WEATHER u3)
(define-constant ORACLE_TYPE_CUSTOM u4)

(define-data-var oracle-counter uint u0)
(define-data-var contract-principal principal tx-sender)

;; Oracle registry
(define-map oracles
    uint
    {
        contract: principal,
        name: (string-ascii 64),
        oracle-type: uint,
        contract-hash: (buff 32),
        registered-at: uint,
        last-activity: uint,
        total-resolutions: uint,
        disputed-resolutions: uint,
        reputation-score: uint,
        stake: uint,
        active: bool
    }
)

;; Lookup by contract address
(define-map oracle-by-contract
    principal
    uint
)

;; Oracle type names
(define-map type-names
    uint
    (string-ascii 32)
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-current-time) stacks-block-time)

(define-read-only (get-oracle (oracle-id uint))
    (map-get? oracles oracle-id)
)

(define-read-only (get-oracle-by-contract (oracle-contract principal))
    (match (map-get? oracle-by-contract oracle-contract)
        oracle-id (map-get? oracles oracle-id)
        none
    )
)

(define-read-only (get-type-name (oracle-type uint))
    (default-to "Unknown" (map-get? type-names oracle-type))
)

;; Verify oracle integrity using contract-hash?
(define-read-only (verify-oracle-integrity (oracle-id uint))
    (match (map-get? oracles oracle-id)
        oracle (match (contract-hash? (get contract oracle))
            ok-hash (is-eq ok-hash (get contract-hash oracle))
            err-val false
        )
        false
    )
)

;; Calculate oracle reliability score
(define-read-only (get-reliability-score (oracle-id uint))
    (match (map-get? oracles oracle-id)
        oracle (let
            (
                (total (get total-resolutions oracle))
                (disputed (get disputed-resolutions oracle))
            )
            (if (is-eq total u0)
                u10000 ;; New oracle starts at 100%
                (/ (* (- total disputed) u10000) total)
            )
        )
        u0
    )
)

;; Generate oracle info using to-ascii?
(define-read-only (generate-oracle-info (oracle-id uint))
    (match (map-get? oracles oracle-id)
        oracle (let
            (
                (id-str (unwrap-panic (to-ascii? oracle-id)))
                (resolutions-str (unwrap-panic (to-ascii? (get total-resolutions oracle))))
                (reliability (get-reliability-score oracle-id))
                (reliability-str (unwrap-panic (to-ascii? reliability)))
                (type-name (get-type-name (get oracle-type oracle)))
            )
            (concat 
                (concat (concat "Oracle #" id-str) (concat ": " (get name oracle)))
                (concat (concat " | Type: " type-name)
                    (concat (concat " | Resolutions: " resolutions-str)
                        (concat " | Reliability: " (concat reliability-str "bps"))
                    )
                )
            )
        )
        "Oracle not found"
    )
)

;; Get registry stats
(define-read-only (get-registry-stats)
    {
        total-oracles: (var-get oracle-counter),
        current-time: stacks-block-time
    }
)

;; Check if oracle can resolve markets
(define-read-only (can-oracle-resolve (oracle-id uint))
    (match (map-get? oracles oracle-id)
        oracle (and
            (get active oracle)
            (verify-oracle-integrity oracle-id)
            (>= (get reputation-score oracle) u5000) ;; Min 50% reputation
        )
        false
    )
)

;; ========================================
;; Admin Functions
;; ========================================

;; Initialize type names
(define-public (initialize-types)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set type-names ORACLE_TYPE_SPORTS "Sports")
        (map-set type-names ORACLE_TYPE_CRYPTO "Cryptocurrency")
        (map-set type-names ORACLE_TYPE_POLITICS "Politics")
        (map-set type-names ORACLE_TYPE_WEATHER "Weather")
        (map-set type-names ORACLE_TYPE_CUSTOM "Custom")
        
        (ok true)
    )
)

;; Register a new oracle
(define-public (register-oracle
    (oracle-contract principal)
    (name (string-ascii 64))
    (oracle-type uint)
    (stake uint))
    (let
        (
            (oracle-id (+ (var-get oracle-counter) u1))
            (current-time stacks-block-time)
            (oracle-hash (unwrap! (contract-hash? oracle-contract) ERR_ORACLE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (map-get? oracle-by-contract oracle-contract)) ERR_ORACLE_EXISTS)
        (asserts! (<= oracle-type ORACLE_TYPE_CUSTOM) ERR_INVALID_PARAMS)
        
        ;; Transfer stake
        (if (> stake u0)
            (try! (stx-transfer? stake tx-sender (var-get contract-principal)))
            true
        )
        
        ;; Register oracle
        (map-set oracles oracle-id {
            contract: oracle-contract,
            name: name,
            oracle-type: oracle-type,
            contract-hash: oracle-hash,
            registered-at: current-time,
            last-activity: current-time,
            total-resolutions: u0,
            disputed-resolutions: u0,
            reputation-score: u10000, ;; Start at 100%
            stake: stake,
            active: true
        })
        
        (map-set oracle-by-contract oracle-contract oracle-id)
        (var-set oracle-counter oracle-id)
        
        (print (generate-oracle-info oracle-id))
        
        (ok oracle-id)
    )
)

;; Deactivate oracle
(define-public (deactivate-oracle (oracle-id uint))
    (let
        (
            (oracle (unwrap! (map-get? oracles oracle-id) ERR_ORACLE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set oracles oracle-id (merge oracle { active: false }))
        
        (ok true)
    )
)

;; Record resolution (called by market manager)
(define-public (record-resolution (oracle-id uint) (disputed bool))
    (let
        (
            (oracle (unwrap! (map-get? oracles oracle-id) ERR_ORACLE_NOT_FOUND))
            (current-time stacks-block-time)
        )
        ;; In production, would verify caller is market manager
        
        (map-set oracles oracle-id (merge oracle {
            last-activity: current-time,
            total-resolutions: (+ (get total-resolutions oracle) u1),
            disputed-resolutions: (if disputed 
                (+ (get disputed-resolutions oracle) u1)
                (get disputed-resolutions oracle)
            )
        }))
        
        (ok true)
    )
)

;; Slash oracle stake for bad behavior
(define-public (slash-stake (oracle-id uint) (slash-amount uint))
    (let
        (
            (oracle (unwrap! (map-get? oracles oracle-id) ERR_ORACLE_NOT_FOUND))
            (current-stake (get stake oracle))
            (actual-slash (if (> slash-amount current-stake) current-stake slash-amount))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        ;; Update stake and reputation
        (map-set oracles oracle-id (merge oracle {
            stake: (- current-stake actual-slash),
            reputation-score: (/ (* (get reputation-score oracle) u9) u10) ;; -10%
        }))
        
        ;; Transfer slashed amount to protocol
        (try! (stx-transfer? actual-slash (var-get contract-principal) CONTRACT_OWNER))
        
        (ok actual-slash)
    )
)

;; Re-verify oracle (check hash still matches)
(define-public (reverify-oracle (oracle-id uint))
    (let
        (
            (oracle (unwrap! (map-get? oracles oracle-id) ERR_ORACLE_NOT_FOUND))
        )
        (if (verify-oracle-integrity oracle-id)
            (ok true)
            (begin
                ;; Hash changed - deactivate
                (map-set oracles oracle-id (merge oracle { active: false }))
                ERR_NOT_AUTHORIZED
            )
        )
    )
)
