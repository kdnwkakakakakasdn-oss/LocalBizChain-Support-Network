;; Local Business Registry Smart Contract
;; Verifies locally-owned businesses with ownership details and community contribution tracking

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_BUSINESS_NOT_FOUND (err u101))
(define-constant ERR_INVALID_PARAMETERS (err u104))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Registration fee
(define-constant REGISTRATION_FEE u1000000) ;; 1 STX

;; Business verification levels
(define-constant VERIFICATION_PENDING u0)
(define-constant VERIFICATION_BASIC u1)
(define-constant VERIFICATION_VERIFIED u2)

;; Data structures
(define-map businesses
  { business-id: uint }
  {
    owner: principal,
    name: (string-ascii 100),
    category: (string-ascii 50),
    address: (string-ascii 200),
    phone: (string-ascii 20),
    email: (string-ascii 100),
    website: (optional (string-ascii 100)),
    description: (string-ascii 500),
    verification-level: uint,
    registration-date: uint,
    local-employees: uint,
    local-suppliers: uint,
    community-score: uint,
    is-active: bool,
    total-revenue-reported: uint,
    last-updated: uint
  }
)

(define-map owner-businesses
  { owner: principal }
  { business-ids: (list 10 uint) }
)

;; Global counters
(define-data-var next-business-id uint u1)
(define-data-var total-businesses uint u0)
(define-data-var total-verified-businesses uint u0)

;; Authorization map for verifiers
(define-map authorized-verifiers principal bool)

;; Initialize contract owner as verifier
(map-set authorized-verifiers CONTRACT_OWNER true)

;; Register a new business
(define-public (register-business 
  (name (string-ascii 100))
  (category (string-ascii 50))
  (address (string-ascii 200))
  (phone (string-ascii 20))
  (email (string-ascii 100))
  (website (optional (string-ascii 100)))
  (description (string-ascii 500))
  (local-employees uint)
  (local-suppliers uint))
  (let (
    (business-id (var-get next-business-id))
  )
    ;; Create business record
    (map-set businesses
      { business-id: business-id }
      {
        owner: tx-sender,
        name: name,
        category: category,
        address: address,
        phone: phone,
        email: email,
        website: website,
        description: description,
        verification-level: VERIFICATION_PENDING,
        registration-date: stacks-block-height,
        local-employees: local-employees,
        local-suppliers: local-suppliers,
        community-score: (+ (* local-employees u10) (* local-suppliers u5)),
        is-active: true,
        total-revenue-reported: u0,
        last-updated: stacks-block-height
      }
    )
    
    ;; Update counters
    (var-set next-business-id (+ business-id u1))
    (var-set total-businesses (+ (var-get total-businesses) u1))
    
    (print { event: "business-registered", business-id: business-id, owner: tx-sender })
    (ok business-id)
  )
)

;; Update business information (owner only)
(define-public (update-business-info
  (business-id uint)
  (name (string-ascii 100))
  (category (string-ascii 50))
  (address (string-ascii 200))
  (phone (string-ascii 20))
  (email (string-ascii 100))
  (website (optional (string-ascii 100)))
  (description (string-ascii 500)))
  (let (
    (business (unwrap! (map-get? businesses { business-id: business-id }) ERR_BUSINESS_NOT_FOUND))
  )
    ;; Only business owner can update
    (asserts! (is-eq (get owner business) tx-sender) ERR_NOT_AUTHORIZED)
    
    ;; Update business record
    (map-set businesses
      { business-id: business-id }
      (merge business {
        name: name,
        category: category,
        address: address,
        phone: phone,
        email: email,
        website: website,
        description: description,
        last-updated: stacks-block-height
      })
    )
    
    (print { event: "business-updated", business-id: business-id })
    (ok true)
  )
)

;; Update community metrics (owner only)
(define-public (update-community-metrics
  (business-id uint)
  (local-employees uint)
  (local-suppliers uint)
  (total-revenue-reported uint))
  (let (
    (business (unwrap! (map-get? businesses { business-id: business-id }) ERR_BUSINESS_NOT_FOUND))
  )
    ;; Only business owner can update
    (asserts! (is-eq (get owner business) tx-sender) ERR_NOT_AUTHORIZED)
    
    ;; Update business metrics
    (map-set businesses
      { business-id: business-id }
      (merge business {
        local-employees: local-employees,
        local-suppliers: local-suppliers,
        total-revenue-reported: total-revenue-reported,
        community-score: (+ (* local-employees u10) (* local-suppliers u5)),
        last-updated: stacks-block-height
      })
    )
    
    (print { event: "community-metrics-updated", business-id: business-id })
    (ok true)
  )
)

;; Verify business (authorized verifiers only)
(define-public (verify-business 
  (business-id uint) 
  (verification-level uint)
  (verification-notes (string-ascii 200)))
  (let (
    (business (unwrap! (map-get? businesses { business-id: business-id }) ERR_BUSINESS_NOT_FOUND))
    (current-verified-count (var-get total-verified-businesses))
  )
    ;; Only authorized verifiers can verify
    (asserts! (default-to false (map-get? authorized-verifiers tx-sender)) ERR_NOT_AUTHORIZED)
    
    ;; Update verification level
    (map-set businesses
      { business-id: business-id }
      (merge business {
        verification-level: verification-level,
        last-updated: stacks-block-height
      })
    )
    
    ;; Update verified business count if upgrading from pending
    (if (is-eq (get verification-level business) VERIFICATION_PENDING)
      (var-set total-verified-businesses (+ current-verified-count u1))
      true
    )
    
    (print { 
      event: "business-verified", 
      business-id: business-id, 
      verification-level: verification-level,
      verifier: tx-sender,
      notes: verification-notes
    })
    (ok true)
  )
)

;; Get business details
(define-read-only (get-business (business-id uint))
  (map-get? businesses { business-id: business-id })
)

;; Get businesses owned by a principal
(define-read-only (get-owner-businesses (owner principal))
  (map-get? owner-businesses { owner: owner })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-businesses: (var-get total-businesses),
    total-verified-businesses: (var-get total-verified-businesses),
    next-business-id: (var-get next-business-id)
  }
)

;; Check if business is verified
(define-read-only (is-business-verified (business-id uint))
  (match (map-get? businesses { business-id: business-id })
    business (> (get verification-level business) VERIFICATION_PENDING)
    false
  )
)

;; Add authorized verifier
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set authorized-verifiers verifier true)
    (print { event: "verifier-added", verifier: verifier })
    (ok true)
  )
)

