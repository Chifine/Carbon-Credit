;; Carbon Credit Exchange Platform
;; Marketplace for trading verified carbon offset credits

;; Constants
(define-constant PLATFORM_OPERATOR tx-sender)
(define-constant ERR_UNAUTHORIZED_OPERATION (err u400))
(define-constant ERR_CREDIT_NOT_FOUND (err u401))
(define-constant ERR_INSUFFICIENT_CREDITS (err u402))
(define-constant ERR_INVALID_PROJECT (err u403))
(define-constant ERR_VERIFICATION_FAILED (err u404))
(define-constant ERR_INVALID_PRICE (err u405))
(define-constant ERR_CREDIT_RETIRED (err u406))

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var next-credit-batch-id uint u1)
(define-data-var platform-fee-percentage uint u200) ;; 2% in basis points

;; Data Maps
(define-map carbon-projects
  { project-id: uint }
  {
    project-developer: principal,
    project-name: (string-ascii 150),
    project-type: uint, ;; 1=reforestation, 2=renewable-energy, 3=methane-capture, 4=direct-air-capture
    location: (string-ascii 100),
    methodology: (string-ascii 80),
    verification-standard: (string-ascii 50),
    project-start-date: uint,
    estimated-annual-credits: uint,
    project-status: uint, ;; 1=development, 2=validation, 3=active, 4=completed
    verification-body: (string-ascii 100),
    is-verified: bool
  }
)

(define-map credit-batches
  { batch-id: uint }
  {
    project-id: uint,
    vintage-year: uint,
    total-credits: uint,
    available-credits: uint,
    retired-credits: uint,
    verification-date: uint,
    serial-number: (string-ascii 50),
    co2-equivalent-tons: uint,
    price-per-credit: uint,
    batch-status: uint ;; 1=available, 2=partially-sold, 3=sold-out, 4=retired
  }
)

(define-map credit-ownership
  { batch-id: uint, owner: principal }
  {
    credits-owned: uint,
    purchase-date: uint,
    purchase-price: uint,
    is-retired: bool
  }
)

(define-map verified-organizations
  { organization: principal }
  {
    organization-name: (string-ascii 120),
    organization-type: uint, ;; 1=corporation, 2=ngo, 3=government, 4=individual
    verification-level: uint, ;; 1-5 scale
    carbon-footprint: uint,
    offset-target: uint,
    credits-purchased: uint,
    credits-retired: uint,
    registration-date: uint
  }
)

(define-map marketplace-orders
  { order-id: uint }
  {
    buyer: principal,
    seller: principal,
    batch-id: uint,
    credit-quantity: uint,
    price-per-credit: uint,
    order-timestamp: uint,
    order-status: uint, ;; 1=pending, 2=filled, 3=cancelled
    expiry-block: uint
  }
)

;; Validation Functions
(define-private (is-valid-methodology (method (string-ascii 80)))
  (and (> (len method) u0) (<= (len method) u80)))

(define-private (is-valid-verification-standard (standard (string-ascii 50)))
  (and (> (len standard) u0) (<= (len standard) u50)))

(define-private (is-valid-project-start-date (start-date uint))
  (and (> start-date u0) (<= start-date stacks-block-height)))

(define-private (is-valid-verification-body (body (string-ascii 100)))
  (and (> (len body) u0) (<= (len body) u100)))

(define-private (is-valid-project-id-input (project-id uint))
  (and (> project-id u0) (< project-id (var-get next-project-id))))

(define-private (is-valid-vintage-year (year uint))
  (and (>= year u2000) (<= year u2030))) ;; Reasonable vintage year range

(define-private (is-valid-serial-number (serial (string-ascii 50)))
  (and (> (len serial) u0) (<= (len serial) u50)))

(define-private (is-valid-co2-equivalent (tons uint))
  (and (> tons u0) (<= tons u1000000))) ;; Max 1M tons per batch

;; Project Registration
(define-public (register-carbon-project
  (project-name (string-ascii 150))
  (project-type uint)
  (location (string-ascii 100))
  (methodology (string-ascii 80))
  (verification-standard (string-ascii 50))
  (project-start-date uint)
  (estimated-annual-credits uint)
  (verification-body (string-ascii 100)))
  (let ((project-id (var-get next-project-id)))
    (asserts! (> (len project-name) u0) ERR_INVALID_PROJECT)
    (asserts! (and (>= project-type u1) (<= project-type u4)) ERR_INVALID_PROJECT)
    (asserts! (> (len location) u0) ERR_INVALID_PROJECT)
    (asserts! (is-valid-methodology methodology) ERR_INVALID_PROJECT)
    (asserts! (is-valid-verification-standard verification-standard) ERR_INVALID_PROJECT)
    (asserts! (is-valid-project-start-date project-start-date) ERR_INVALID_PROJECT)
    (asserts! (> estimated-annual-credits u0) ERR_INVALID_PROJECT)
    (asserts! (is-valid-verification-body verification-body) ERR_INVALID_PROJECT)
    
    (map-set carbon-projects
      { project-id: project-id }
      {
        project-developer: tx-sender,
        project-name: project-name,
        project-type: project-type,
        location: location,
        methodology: methodology,
        verification-standard: verification-standard,
        project-start-date: project-start-date,
        estimated-annual-credits: estimated-annual-credits,
        project-status: u1,
        verification-body: verification-body,
        is-verified: false
      }
    )
    
    (var-set next-project-id (+ project-id u1))
    (ok project-id)
  )
)

(define-public (issue-credit-batch
  (project-id uint)
  (vintage-year uint)
  (total-credits uint)
  (serial-number (string-ascii 50))
  (co2-equivalent-tons uint)
  (price-per-credit uint))
  (let ((batch-id (var-get next-credit-batch-id))
        (validated-project-id (begin 
                                (asserts! (is-valid-project-id-input project-id) ERR_INVALID_PROJECT)
                                project-id))
        (validated-vintage-year (begin 
                                  (asserts! (is-valid-vintage-year vintage-year) ERR_INVALID_PROJECT)
                                  vintage-year))
        (validated-serial-number (begin 
                                   (asserts! (is-valid-serial-number serial-number) ERR_INVALID_PROJECT)
                                   serial-number))
        (validated-co2-tons (begin 
                              (asserts! (is-valid-co2-equivalent co2-equivalent-tons) ERR_INVALID_PROJECT)
                              co2-equivalent-tons))
        (project (unwrap! (map-get? carbon-projects { project-id: validated-project-id }) ERR_INVALID_PROJECT)))
    (asserts! (is-eq tx-sender (get project-developer project)) ERR_UNAUTHORIZED_OPERATION)
    (asserts! (get is-verified project) ERR_VERIFICATION_FAILED)
    (asserts! (> total-credits u0) ERR_INVALID_PROJECT)
    (asserts! (> price-per-credit u0) ERR_INVALID_PRICE)
    
    (map-set credit-batches
      { batch-id: batch-id }
      {
        project-id: validated-project-id,
        vintage-year: validated-vintage-year,
        total-credits: total-credits,
        available-credits: total-credits,
        retired-credits: u0,
        verification-date: stacks-block-height,
        serial-number: validated-serial-number,
        co2-equivalent-tons: validated-co2-tons,
        price-per-credit: price-per-credit,
        batch-status: u1
      }
    )
    
    (var-set next-credit-batch-id (+ batch-id u1))
    (ok batch-id)
  )
)

;; Query Functions
(define-read-only (get-project-details (project-id uint))
  (map-get? carbon-projects { project-id: project-id })
)

(define-read-only (get-credit-batch-info (batch-id uint))
  (map-get? credit-batches { batch-id: batch-id })
)

(define-read-only (get-credit-ownership (batch-id uint) (owner principal))
  (map-get? credit-ownership { batch-id: batch-id, owner: owner })
)

(define-read-only (calculate-carbon-offset (credits uint) (co2-per-credit uint))
  (* credits co2-per-credit)
)
