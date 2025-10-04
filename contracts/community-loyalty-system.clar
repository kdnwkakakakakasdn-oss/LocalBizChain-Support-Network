;; Community Loyalty System Smart Contract
;; Cross-business loyalty program encouraging shopping local with reward point accumulation

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_CUSTOMER_NOT_FOUND (err u201))
(define-constant ERR_BUSINESS_NOT_FOUND (err u202))
(define-constant ERR_INSUFFICIENT_POINTS (err u203))
(define-constant ERR_INVALID_PARAMETERS (err u204))
(define-constant ERR_ALREADY_EXISTS (err u206))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Point multipliers and thresholds
(define-constant BASE_POINTS_PER_STX u100) ;; 100 points per 1 STX spent
(define-constant REVIEW_BONUS_POINTS u50)
(define-constant REFERRAL_BONUS_POINTS u200)

;; Loyalty tiers and thresholds
(define-constant TIER_BRONZE u0)
(define-constant TIER_SILVER u1)
(define-constant TIER_GOLD u2)
(define-constant TIER_PLATINUM u3)

(define-constant SILVER_THRESHOLD u1000)
(define-constant GOLD_THRESHOLD u5000)
(define-constant PLATINUM_THRESHOLD u15000)

;; Tier multipliers (in percentage)
(define-constant BRONZE_MULTIPLIER u100) ;; 1.0x
(define-constant SILVER_MULTIPLIER u110) ;; 1.1x
(define-constant GOLD_MULTIPLIER u125)   ;; 1.25x
(define-constant PLATINUM_MULTIPLIER u150) ;; 1.5x

;; Data structures
(define-map customers
  { customer: principal }
  {
    name: (string-ascii 100),
    email: (string-ascii 100),
    registration-date: uint,
    total-points: uint,
    available-points: uint,
    points-spent: uint,
    total-spent: uint,
    tier: uint,
    last-activity: uint,
    referral-count: uint,
    review-count: uint,
    is-active: bool
  }
)

(define-map businesses
  { business: principal }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    points-rate: uint,
    bonus-multiplier: uint,
    registration-date: uint,
    total-points-awarded: uint,
    total-transactions: uint,
    is-verified: bool,
    is-active: bool,
    last-activity: uint
  }
)

(define-map loyalty-transactions
  { transaction-id: uint }
  {
    customer: principal,
    business: principal,
    amount: uint,
    points-awarded: uint,
    transaction-type: (string-ascii 50),
    timestamp: uint,
    bonus-applied: uint,
    tier-at-time: uint
  }
)

;; Global counters
(define-data-var next-transaction-id uint u1)
(define-data-var total-customers uint u0)
(define-data-var total-businesses uint u0)
(define-data-var total-points-issued uint u0)

;; Register a new customer
(define-public (register-customer 
  (name (string-ascii 100))
  (email (string-ascii 100))
  (referrer (optional principal)))
  (let (
    (existing-customer (map-get? customers { customer: tx-sender }))
  )
    ;; Check if customer doesn't already exist
    (asserts! (is-none existing-customer) ERR_ALREADY_EXISTS)
    
    ;; Create customer record
    (map-set customers
      { customer: tx-sender }
      {
        name: name,
        email: email,
        registration-date: stacks-block-height,
        total-points: u0,
        available-points: u0,
        points-spent: u0,
        total-spent: u0,
        tier: TIER_BRONZE,
        last-activity: stacks-block-height,
        referral-count: u0,
        review-count: u0,
        is-active: true
      }
    )
    
    ;; Update global counter
    (var-set total-customers (+ (var-get total-customers) u1))
    
    (print { event: "customer-registered", customer: tx-sender, referrer: referrer })
    (ok true)
  )
)

;; Register a business
(define-public (register-business 
  (name (string-ascii 100))
  (category (string-ascii 50))
  (points-rate uint)
  (bonus-multiplier uint))
  (let (
    (existing-business (map-get? businesses { business: tx-sender }))
  )
    ;; Check if business doesn't already exist
    (asserts! (is-none existing-business) ERR_ALREADY_EXISTS)
    
    ;; Validate parameters
    (asserts! (>= points-rate BASE_POINTS_PER_STX) ERR_INVALID_PARAMETERS)
    (asserts! (and (>= bonus-multiplier u100) (<= bonus-multiplier u200)) ERR_INVALID_PARAMETERS)
    
    ;; Create business record
    (map-set businesses
      { business: tx-sender }
      {
        name: name,
        category: category,
        points-rate: points-rate,
        bonus-multiplier: bonus-multiplier,
        registration-date: stacks-block-height,
        total-points-awarded: u0,
        total-transactions: u0,
        is-verified: false,
        is-active: true,
        last-activity: stacks-block-height
      }
    )
    
    ;; Update global counter
    (var-set total-businesses (+ (var-get total-businesses) u1))
    
    (print { event: "business-registered", business: tx-sender })
    (ok true)
  )
)

;; Award points for a purchase
(define-public (award-points
  (customer principal)
  (amount uint)
  (transaction-type (string-ascii 50)))
  (let (
    (customer-data (unwrap! (map-get? customers { customer: customer }) ERR_CUSTOMER_NOT_FOUND))
    (business-data (unwrap! (map-get? businesses { business: tx-sender }) ERR_BUSINESS_NOT_FOUND))
    (transaction-id (var-get next-transaction-id))
  )
    ;; Check if business is authorized
    (asserts! (get is-active business-data) ERR_NOT_AUTHORIZED)
    
    ;; Calculate base points
    (let (
      (base-points (* amount (get points-rate business-data)))
      (tier-multiplier (get-tier-multiplier (get tier customer-data)))
      (business-bonus (get bonus-multiplier business-data))
      (total-multiplier (* tier-multiplier business-bonus))
      (final-points (/ (* base-points total-multiplier) u10000))
    )
      ;; Update customer points
      (map-set customers
        { customer: customer }
        (merge customer-data {
          total-points: (+ (get total-points customer-data) final-points),
          available-points: (+ (get available-points customer-data) final-points),
          total-spent: (+ (get total-spent customer-data) amount),
          last-activity: stacks-block-height,
          tier: (calculate-customer-tier (+ (get total-points customer-data) final-points))
        })
      )
      
      ;; Update business stats
      (map-set businesses
        { business: tx-sender }
        (merge business-data {
          total-points-awarded: (+ (get total-points-awarded business-data) final-points),
          total-transactions: (+ (get total-transactions business-data) u1),
          last-activity: stacks-block-height
        })
      )
      
      ;; Record transaction
      (map-set loyalty-transactions
        { transaction-id: transaction-id }
        {
          customer: customer,
          business: tx-sender,
          amount: amount,
          points-awarded: final-points,
          transaction-type: transaction-type,
          timestamp: stacks-block-height,
          bonus-applied: (- total-multiplier u100),
          tier-at-time: (get tier customer-data)
        }
      )
      
      ;; Update counters
      (var-set next-transaction-id (+ transaction-id u1))
      (var-set total-points-issued (+ (var-get total-points-issued) final-points))
      
      (print { event: "points-awarded", customer: customer, business: tx-sender, points: final-points })
      (ok final-points)
    )
  )
)

;; Award review bonus
(define-public (award-review-bonus (customer principal))
  (let (
    (customer-data (unwrap! (map-get? customers { customer: customer }) ERR_CUSTOMER_NOT_FOUND))
    (business-data (unwrap! (map-get? businesses { business: tx-sender }) ERR_BUSINESS_NOT_FOUND))
  )
    ;; Check if business is active
    (asserts! (get is-active business-data) ERR_NOT_AUTHORIZED)
    
    ;; Award review bonus points
    (map-set customers
      { customer: customer }
      (merge customer-data {
        available-points: (+ (get available-points customer-data) REVIEW_BONUS_POINTS),
        total-points: (+ (get total-points customer-data) REVIEW_BONUS_POINTS),
        review-count: (+ (get review-count customer-data) u1),
        last-activity: stacks-block-height,
        tier: (calculate-customer-tier (+ (get total-points customer-data) REVIEW_BONUS_POINTS))
      })
    )
    
    ;; Update global counter
    (var-set total-points-issued (+ (var-get total-points-issued) REVIEW_BONUS_POINTS))
    
    (print { event: "review-bonus-awarded", customer: customer, business: tx-sender })
    (ok true)
  )
)

;; Get customer details
(define-read-only (get-customer (customer principal))
  (map-get? customers { customer: customer })
)

;; Get business details
(define-read-only (get-business (business principal))
  (map-get? businesses { business: business })
)

;; Get transaction details
(define-read-only (get-transaction (transaction-id uint))
  (map-get? loyalty-transactions { transaction-id: transaction-id })
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-customers: (var-get total-customers),
    total-businesses: (var-get total-businesses),
    total-points-issued: (var-get total-points-issued),
    next-transaction-id: (var-get next-transaction-id)
  }
)

;; Calculate customer tier based on total points
(define-read-only (calculate-customer-tier (total-points uint))
  (if (>= total-points PLATINUM_THRESHOLD)
    TIER_PLATINUM
    (if (>= total-points GOLD_THRESHOLD)
      TIER_GOLD
      (if (>= total-points SILVER_THRESHOLD)
        TIER_SILVER
        TIER_BRONZE
      )
    )
  )
)

;; Get tier multiplier
(define-read-only (get-tier-multiplier (tier uint))
  (if (is-eq tier TIER_PLATINUM)
    PLATINUM_MULTIPLIER
    (if (is-eq tier TIER_GOLD)
      GOLD_MULTIPLIER
      (if (is-eq tier TIER_SILVER)
        SILVER_MULTIPLIER
        BRONZE_MULTIPLIER
      )
    )
  )
)

;; Verify business (admin only)
(define-public (verify-business (business principal))
  (let (
    (business-data (unwrap! (map-get? businesses { business: business }) ERR_BUSINESS_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set businesses
      { business: business }
      (merge business-data { is-verified: true })
    )
    
    (print { event: "business-verified", business: business })
    (ok true)
  )
)

