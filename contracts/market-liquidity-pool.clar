;; market-liquidity-pool.clar
;; Liquidity pool integration for prediction markets
;; Uses Clarity 4 epoch 3.3

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u10001))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u10002))

(define-data-var pool-counter uint u0)
(define-data-var total-liquidity uint u0)

(define-map liquidity-pools
    uint
    {
        market-id: uint,
        total-liquidity: uint,
        provider-count: uint,
        fee-bps: uint,
        created-at: uint,
        active: bool
    }
)

(define-map provider-positions
    { pool-id: uint, provider: principal }
    {
        amount: uint,
        shares: uint,
        fees-earned: uint,
        deposited-at: uint
    }
)

(define-public (create-pool (market-id uint) (fee-bps uint))
    (let
        (
            (pool-id (+ (var-get pool-counter) u1))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set liquidity-pools pool-id {
            market-id: market-id,
            total-liquidity: u0,
            provider-count: u0,
            fee-bps: fee-bps,
            created-at: stacks-block-time,
            active: true
        })
        (var-set pool-counter pool-id)
        (print {
            event: "liquidity-pool-created",
            pool-id: pool-id,
            market-id: market-id,
            fee-bps: fee-bps,
            timestamp: stacks-block-time
        })
        (ok pool-id)
    )
)

(define-public (add-liquidity (pool-id uint) (amount uint))
    (let
        (
            (pool (unwrap! (map-get? liquidity-pools pool-id) ERR_INSUFFICIENT_LIQUIDITY))
        )
        (map-set liquidity-pools pool-id
            (merge pool {
                total-liquidity: (+ (get total-liquidity pool) amount),
                provider-count: (+ (get provider-count pool) u1)
            }))
        (map-set provider-positions
            { pool-id: pool-id, provider: tx-sender }
            {
                amount: amount,
                shares: amount,
                fees-earned: u0,
                deposited-at: stacks-block-time
            })
        (var-set total-liquidity (+ (var-get total-liquidity) amount))
        (print {
            event: "liquidity-added",
            pool-id: pool-id,
            provider: tx-sender,
            amount: amount,
            timestamp: stacks-block-time
        })
        (ok true)
    )
)

(define-read-only (get-pool (pool-id uint))
    (map-get? liquidity-pools pool-id)
)
