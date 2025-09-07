;; Oracle and Liquidation System for Simple Lending Platform
;; Provides price feeds and automated liquidation functionality

;; ===================
;; CONSTANTS & ERRORS
;; ===================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u701))
(define-constant ERR-ORACLE-NOT-FOUND (err u702))
(define-constant ERR-STALE-PRICE (err u703))
(define-constant ERR-INVALID-PRICE (err u704))
(define-constant ERR-LOAN-NOT-LIQUIDATABLE (err u705))
(define-constant ERR-LIQUIDATION-FAILED (err u706))
(define-constant ERR-INSUFFICIENT-REWARD (err u707))
(define-constant ERR-ORACLE-PAUSED (err u708))
(define-constant ERR-INVALID-ASSET (err u709))
(define-constant ERR-COOLDOWN-ACTIVE (err u710))
(define-constant ERR-INVALID-LENDING-CONTRACT (err u711))
(define-constant ERR-PRICE-DEVIATION-TOO-HIGH (err u712))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-PRICE-AGE u144) ;; 1 day in blocks
(define-constant MAX-PRICE-DEVIATION u20) ;; 20% max price change
(define-constant LIQUIDATION-REWARD u5) ;; 5% reward for liquidators
(define-constant MIN-LIQUIDATION-VALUE u100000) ;; 0.1 STX minimum for gas efficiency
(define-constant ORACLE-COOLDOWN u10) ;; 10 blocks between updates
(define-constant MAX-ORACLES-PER-ASSET u5) ;; Maximum oracles per asset

;; ===================
;; DATA VARIABLES
;; ===================

;; System state
(define-data-var oracle-system-active bool true)
(define-data-var total-liquidations uint u0)
(define-data-var lending-contract (optional principal) none)
(define-data-var emergency-pause bool false)

;; Default STX price in USD (scaled by 10^6 for precision)
(define-data-var default-stx-price uint u1000000) ;; $1.00 USD

;; ===================
;; DATA MAPS
;; ===================

;; Asset price oracles
(define-map price-oracles
    { asset: (string-ascii 10), oracle: principal }
    {
        is-active: bool,
        last-update: uint,
        update-count: uint,
        reputation: uint
    }
)

;; Latest price data for assets
(define-map asset-prices
    { asset: (string-ascii 10) }
    {
        price: uint, ;; Price in USD (scaled by 10^6)
        timestamp: uint,
        last-updater: principal,
        confidence: uint, ;; Confidence score 0-100
        oracle-count: uint
    }
)

;; Price history for validation
(define-map price-history
    { asset: (string-ascii 10), block: uint }
    {
        price: uint,
        updater: principal,
        deviation: uint
    }
)

;; Liquidation queue and tracking
(define-map liquidation-queue
    { position: uint }
    {
        loan-id: uint,
        borrower: principal,
        collateral-value: uint,
        debt-value: uint,
        health-factor: uint,
        queued-block: uint
    }
)

(define-data-var liquidation-queue-size uint u0)

;; Liquidator statistics
(define-map liquidator-stats
    { liquidator: principal }
    {
        total-liquidations: uint,
        total-reward: uint,
        successful-rate: uint,
        last-liquidation: uint
    }
)

;; Oracle reputation and performance
(define-map oracle-performance
    { oracle: principal, asset: (string-ascii 10) }
    {
        accurate-updates: uint,
        total-updates: uint,
        deviation-score: uint,
        last-penalty: uint
    }
)

;; ===================
;; PRIVATE FUNCTIONS
;; ===================

;; Calculate price deviation percentage
(define-private (calculate-deviation (old-price uint) (new-price uint))
    (let (
        (diff (if (> new-price old-price) 
                 (- new-price old-price)
                 (- old-price new-price)))
        (base-price (if (> old-price new-price) old-price new-price))
    )
    (if (> base-price u0)
        (/ (* diff u100) base-price)
        u0))
)

;; Validate price update
(define-private (is-price-update-valid (asset (string-ascii 10)) (new-price uint) (oracle principal))
    (let (
        (current-price-data (map-get? asset-prices { asset: asset }))
        (oracle-data (map-get? price-oracles { asset: asset, oracle: oracle }))
    )
    (and 
        ;; Oracle must be active
        (match oracle-data
            data (get is-active data)
            false)
        ;; Price must be reasonable (> 0)
        (> new-price u0)
        ;; Check price deviation if previous price exists
        (match current-price-data
            price-data (let (
                            (old-price (get price price-data))
                            (deviation (calculate-deviation old-price new-price))
                        )
                        (<= deviation MAX-PRICE-DEVIATION))
            true)
    ))
)

;; Calculate health factor for a loan
(define-private (calculate-health-factor (collateral-amount uint) (debt-amount uint) (collateral-price uint))
    (let (
        (collateral-value (* collateral-amount collateral-price))
    )
    (if (> debt-amount u0)
        (/ (* collateral-value u100) debt-amount)
        u10000)) ;; Very high health factor if no debt
)

;; Check if loan is liquidatable
(define-private (is-loan-liquidatable (health-factor uint))
    (< health-factor u120) ;; Below 120% health factor
)

;; ===================
;; ORACLE FUNCTIONS
;; ===================

;; Register a new price oracle
(define-public (register-oracle (asset (string-ascii 10)))
    (let (
        (oracle-count (default-to u0 (get oracle-count (map-get? asset-prices { asset: asset }))))
    )
    (asserts! (var-get oracle-system-active) ERR-ORACLE-PAUSED)
    (asserts! (< oracle-count MAX-ORACLES-PER-ASSET) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? price-oracles { asset: asset, oracle: tx-sender })) ERR-UNAUTHORIZED)
    
    ;; Register oracle
    (map-set price-oracles
        { asset: asset, oracle: tx-sender }
        {
            is-active: true,
            last-update: u0,
            update-count: u0,
            reputation: u100
        }
    )
    
    ;; Initialize oracle performance tracking
    (map-set oracle-performance
        { oracle: tx-sender, asset: asset }
        {
            accurate-updates: u0,
            total-updates: u0,
            deviation-score: u0,
            last-penalty: u0
        }
    )
    
    ;; Update oracle count for asset
    (let (
        (current-price (default-to 
            { price: (var-get default-stx-price), timestamp: block-height, last-updater: tx-sender, confidence: u50, oracle-count: u0 }
            (map-get? asset-prices { asset: asset })))
    )
    (map-set asset-prices
        { asset: asset }
        (merge current-price { oracle-count: (+ oracle-count u1) }))
    )
    
    (ok { asset: asset, oracle: tx-sender, total-oracles: (+ oracle-count u1) })
    )
)

;; Update asset price (oracle only)
(define-public (update-price (asset (string-ascii 10)) (new-price uint) (confidence uint))
    (let (
        (oracle tx-sender)
        (oracle-data (unwrap! (map-get? price-oracles { asset: asset, oracle: oracle }) ERR-UNAUTHORIZED))
        (last-update (get last-update oracle-data))
        (current-price-data (map-get? asset-prices { asset: asset }))
    )
    (asserts! (var-get oracle-system-active) ERR-ORACLE-PAUSED)
    (asserts! (not (var-get emergency-pause)) ERR-ORACLE-PAUSED)
    (asserts! (get is-active oracle-data) ERR-UNAUTHORIZED)
    (asserts! (>= (- block-height last-update) ORACLE-COOLDOWN) ERR-COOLDOWN-ACTIVE)
    (asserts! (and (> new-price u0) (<= confidence u100)) ERR-INVALID-PRICE)
    (asserts! (is-price-update-valid asset new-price oracle) ERR-PRICE-DEVIATION-TOO-HIGH)
    
    ;; Calculate deviation if previous price exists
    (let (
        (deviation (match current-price-data
                      price-data (calculate-deviation (get price price-data) new-price)
                      u0))
    )
    
    ;; Update price data
    (map-set asset-prices
        { asset: asset }
        {
            price: new-price,
            timestamp: block-height,
            last-updater: oracle,
            confidence: confidence,
            oracle-count: (match current-price-data
                             price-data (get oracle-count price-data)
                             u1)
        }
    )
    
    ;; Record price history
    (map-set price-history
        { asset: asset, block: block-height }
        {
            price: new-price,
            updater: oracle,
            deviation: deviation
        }
    )
    
    ;; Update oracle statistics
    (map-set price-oracles
        { asset: asset, oracle: oracle }
        (merge oracle-data {
            last-update: block-height,
            update-count: (+ (get update-count oracle-data) u1)
        })
    )
    
    ;; Update oracle performance
    (let (
        (perf-data (default-to 
            { accurate-updates: u0, total-updates: u0, deviation-score: u0, last-penalty: u0 }
            (map-get? oracle-performance { oracle: oracle, asset: asset })))
        (is-accurate (< deviation u10)) ;; Less than 10% deviation is considered accurate
    )
    (map-set oracle-performance
        { oracle: oracle, asset: asset }
        {
            accurate-updates: (if is-accurate (+ (get accurate-updates perf-data) u1) (get accurate-updates perf-data)),
            total-updates: (+ (get total-updates perf-data) u1),
            deviation-score: (+ (get deviation-score perf-data) deviation),
            last-penalty: (get last-penalty perf-data)
        }
    ))
    
    (ok { asset: asset, price: new-price, confidence: confidence, deviation: deviation })
    ))
)

;; ===================
;; LIQUIDATION FUNCTIONS
;; ===================

;; Set lending contract (owner only)
(define-public (set-lending-contract (lending-principal principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set lending-contract (some lending-principal))
        (ok true)
    )
)

;; Add loan to liquidation queue
(define-public (queue-for-liquidation (loan-id uint))
    (let (
        (lending (unwrap! (var-get lending-contract) ERR-INVALID-LENDING-CONTRACT))
        (loan-details (unwrap! (contract-call? .lending-platform get-loan-details loan-id) ERR-LOAN-NOT-LIQUIDATABLE))
        (loan-data (get loan loan-details))
        (collateral-amount (get collateral-amount loan-data))
        (total-debt (get total-debt loan-details))
        (stx-price (get price (default-to 
                               { price: (var-get default-stx-price), timestamp: block-height, last-updater: tx-sender, confidence: u50, oracle-count: u0 }
                               (map-get? asset-prices { asset: "STX" }))))
        (collateral-value (* collateral-amount stx-price))
        (debt-value (* total-debt stx-price))
        (health-factor (calculate-health-factor collateral-amount total-debt stx-price))
        (queue-position (var-get liquidation-queue-size))
    )
    (asserts! (var-get oracle-system-active) ERR-ORACLE-PAUSED)
    (asserts! (not (get is-repaid loan-data)) ERR-LOAN-NOT-LIQUIDATABLE)
    (asserts! (is-loan-liquidatable health-factor) ERR-LOAN-NOT-LIQUIDATABLE)
    (asserts! (>= collateral-value MIN-LIQUIDATION-VALUE) ERR-INSUFFICIENT-REWARD)
    
    ;; Add to liquidation queue
    (map-set liquidation-queue
        { position: queue-position }
        {
            loan-id: loan-id,
            borrower: (get borrower loan-data),
            collateral-value: collateral-value,
            debt-value: debt-value,
            health-factor: health-factor,
            queued-block: block-height
        }
    )
    
    (var-set liquidation-queue-size (+ queue-position u1))
    
    (ok { loan-id: loan-id, queue-position: queue-position, health-factor: health-factor })
    )
)

;; Execute liquidation from queue
(define-public (execute-liquidation (queue-position uint))
    (let (
        (liquidation-data (unwrap! (map-get? liquidation-queue { position: queue-position }) ERR-LOAN-NOT-LIQUIDATABLE))
        (loan-id (get loan-id liquidation-data))
        (borrower (get borrower liquidation-data))
        (lending (unwrap! (var-get lending-contract) ERR-INVALID-LENDING-CONTRACT))
        (liquidator tx-sender)
        (liquidation-reward (/ (* (get collateral-value liquidation-data) LIQUIDATION-REWARD) u100))
    )
    (asserts! (var-get oracle-system-active) ERR-ORACLE-PAUSED)
    (asserts! (not (var-get emergency-pause)) ERR-ORACLE-PAUSED)
    
    ;; Execute liquidation on lending contract
    (match (contract-call? .lending-platform liquidate-loan loan-id)
        success-data (begin
                       ;; Update liquidator statistics
                       (let (
                           (liquidator-data (default-to 
                               { total-liquidations: u0, total-reward: u0, successful-rate: u100, last-liquidation: u0 }
                               (map-get? liquidator-stats { liquidator: liquidator })))
                       )
                       (map-set liquidator-stats
                           { liquidator: liquidator }
                           {
                               total-liquidations: (+ (get total-liquidations liquidator-data) u1),
                               total-reward: (+ (get total-reward liquidator-data) liquidation-reward),
                               successful-rate: u100, ;; Simplified - always successful if we reach here
                               last-liquidation: block-height
                           }
                       ))
                       
                       ;; Update global stats
                       (var-set total-liquidations (+ (var-get total-liquidations) u1))
                       
                       ;; Remove from queue
                       (map-delete liquidation-queue { position: queue-position })
                       
                       (ok {
                           loan-id: loan-id,
                           liquidator: liquidator,
                           reward: liquidation-reward,
                           lending-result: success-data
                       }))
        error-result ERR-LIQUIDATION-FAILED
    )
    )
)

;; ===================
;; READ-ONLY FUNCTIONS
;; ===================

;; Get current price for an asset
(define-read-only (get-price (asset (string-ascii 10)))
    (let (
        (price-data (map-get? asset-prices { asset: asset }))
    )
    (match price-data
        data (if (<= (- block-height (get timestamp data)) MAX-PRICE-AGE)
                (ok {
                    price: (get price data),
                    timestamp: (get timestamp data),
                    confidence: (get confidence data),
                    is-stale: false,
                    age: (- block-height (get timestamp data))
                })
                (ok {
                    price: (get price data),
                    timestamp: (get timestamp data),
                    confidence: (get confidence data),
                    is-stale: true,
                    age: (- block-height (get timestamp data))
                }))
        ERR-ORACLE-NOT-FOUND
    ))
)

;; Get oracle information
(define-read-only (get-oracle-info (asset (string-ascii 10)) (oracle principal))
    (let (
        (oracle-data (map-get? price-oracles { asset: asset, oracle: oracle }))
        (perf-data (map-get? oracle-performance { oracle: oracle, asset: asset }))
    )
    (match oracle-data
        data (ok {
            oracle-data: data,
            performance: perf-data,
            can-update: (>= (- block-height (get last-update data)) ORACLE-COOLDOWN)
        })
        ERR-ORACLE-NOT-FOUND
    ))
)

;; Get liquidation queue status
(define-read-only (get-liquidation-queue-info)
    {
        queue-size: (var-get liquidation-queue-size),
        total-liquidations: (var-get total-liquidations),
        system-active: (var-get oracle-system-active),
        emergency-pause: (var-get emergency-pause)
    }
)

;; Get liquidation data by position
(define-read-only (get-liquidation-by-position (position uint))
    (map-get? liquidation-queue { position: position })
)

;; Get liquidator statistics
(define-read-only (get-liquidator-stats (liquidator principal))
    (default-to 
        { total-liquidations: u0, total-reward: u0, successful-rate: u0, last-liquidation: u0 }
        (map-get? liquidator-stats { liquidator: liquidator }))
)

;; Check if loan is liquidatable by loan ID
(define-read-only (check-loan-liquidatable (loan-id uint))
    (let (
        (lending (unwrap! (var-get lending-contract) ERR-INVALID-LENDING-CONTRACT))
    )
    (match (contract-call? .lending-platform get-loan-details loan-id)
        loan-result (let (
                        (loan-data (get loan loan-result))
                        (total-debt (get total-debt loan-result))
                        (collateral-amount (get collateral-amount loan-data))
                        (stx-price (get price (default-to 
                                               { price: (var-get default-stx-price), timestamp: block-height, last-updater: CONTRACT-OWNER, confidence: u50, oracle-count: u0 }
                                               (map-get? asset-prices { asset: "STX" }))))
                        (health-factor (calculate-health-factor collateral-amount total-debt stx-price))
                    )
                    (ok {
                        is-liquidatable: (and (not (get is-repaid loan-data)) (is-loan-liquidatable health-factor)),
                        health-factor: health-factor,
                        collateral-value: (* collateral-amount stx-price),
                        debt-value: (* total-debt stx-price),
                        current-stx-price: stx-price
                    }))
        error (err error)
    ))
)

;; Get price history for an asset
(define-read-only (get-price-history (asset (string-ascii 10)) (block uint))
    (map-get? price-history { asset: asset, block: block })
)

;; Get system statistics
(define-read-only (get-system-stats)
    {
        oracle-system-active: (var-get oracle-system-active),
        total-liquidations: (var-get total-liquidations),
        liquidation-queue-size: (var-get liquidation-queue-size),
        lending-contract: (var-get lending-contract),
        emergency-pause: (var-get emergency-pause),
        default-stx-price: (var-get default-stx-price)
    }
)

;; ===================
;; ADMIN FUNCTIONS
;; ===================

;; Emergency pause system (owner only)
(define-public (emergency-pause-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set emergency-pause true)
        (ok true)
    )
)

;; Resume system (owner only)
(define-public (resume-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set emergency-pause false)
        (ok true)
    )
)

;; Deactivate oracle (owner only)
(define-public (deactivate-oracle (asset (string-ascii 10)) (oracle principal))
    (let (
        (oracle-data (unwrap! (map-get? price-oracles { asset: asset, oracle: oracle }) ERR-ORACLE-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (map-set price-oracles
        { asset: asset, oracle: oracle }
        (merge oracle-data { is-active: false })
    )
    
    (ok true))
)

;; Update default STX price (owner only - for fallback)
(define-public (update-default-stx-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (> new-price u0) ERR-INVALID-PRICE)
        (var-set default-stx-price new-price)
        (ok new-price)
    )
)

;; Pause oracle system (owner only)
(define-public (pause-oracle-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set oracle-system-active false)
        (ok true)
    )
)

;; Resume oracle system (owner only)
(define-public (resume-oracle-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set oracle-system-active true)
        (ok true)
    )
)
