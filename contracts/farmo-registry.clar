;; farmo-registry
;; 
;; This smart contract implements an agricultural supply chain tracking system that follows 
;; products from farm to table. It creates an immutable record of each product's journey,
;; allowing farmers, distributors, retailers, and consumers to verify agricultural product 
;; authenticity, origins, and handling procedures.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PRODUCT-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-INVALID-TRANSFER (err u103))
(define-constant ERR-INVALID-HANDLER (err u104))
(define-constant ERR-INVALID-PARAMS (err u105))
(define-constant ERR-NOT-CURRENT-HANDLER (err u106))
(define-constant ERR-ALREADY-CERTIFIED (err u107))

;; Constants
(define-constant ROLE-FARMER u1)
(define-constant ROLE-PROCESSOR u2)
(define-constant ROLE-DISTRIBUTOR u3)
(define-constant ROLE-RETAILER u4)
(define-constant ROLE-CERTIFIER u5)

;; Data structures

;; Tracks registered participants in the supply chain
(define-map participants 
  principal
  {
    role: uint,
    name: (string-ascii 100),
    location: (string-ascii 100),
    registration-time: uint,
    active: bool
  }
)

;; Stores product batch information
(define-map products
  {product-id: (string-ascii 36)}
  {
    farmer: principal,
    name: (string-ascii 100),
    description: (string-ascii 500),
    quantity: uint,
    unit: (string-ascii 20),
    harvest-date: uint,
    farming-practices: (string-ascii 200),
    registration-time: uint,
    current-handler: principal,
    is-certified: bool
  }
)

;; Tracks product movement through supply chain
(define-map product-history
  {product-id: (string-ascii 36), entry-index: uint}
  {
    handler: principal,
    handler-role: uint,
    action: (string-ascii 50),
    timestamp: uint,
    location: (string-ascii 100),
    notes: (string-ascii 500)
  }
)

;; Keeps track of certification details when applicable
(define-map product-certifications
  {product-id: (string-ascii 36)}
  {
    certifier: principal,
    certification-type: (string-ascii 100),
    certification-date: uint,
    expiration-date: uint,
    standards-met: (string-ascii 500)
  }
)

;; Counters to track entries for each product
(define-map product-entry-count
  {product-id: (string-ascii 36)}
  {count: uint}
)

;; Private functions

;; Checks if caller is registered with the specified role
(define-private (is-participant-with-role (caller principal) (required-role uint))
  (match (map-get? participants caller)
    participant (and (get active participant) (is-eq (get role participant) required-role))
    false
  )
)

;; Verifies if a principal is the current handler of a product
(define-private (is-current-handler (caller principal) (product-id (string-ascii 36)))
  (match (map-get? products {product-id: product-id})
    product (is-eq (get current-handler product) caller)
    false
  )
)

;; Adds a new entry to the product's history
(define-private (add-history-entry 
  (product-id (string-ascii 36)) 
  (handler principal) 
  (handler-role uint) 
  (action (string-ascii 50)) 
  (location (string-ascii 100)) 
  (notes (string-ascii 500)))
  
  (let ((current-count (default-to {count: u0} (map-get? product-entry-count {product-id: product-id}))))
    (map-set product-history
      {product-id: product-id, entry-index: (get count current-count)}
      {
        handler: handler,
        handler-role: handler-role,
        action: action,
        timestamp: (unwrap-panic (get-block-info? time u0)),
        location: location,
        notes: notes
      }
    )
    ;; Update the entry count
    (map-set product-entry-count
      {product-id: product-id}
      {count: (+ u1 (get count current-count))}
    )
    true
  )
)

;; Read-only functions

;; Retrieve product information
(define-read-only (get-product (product-id (string-ascii 36)))
  (map-get? products {product-id: product-id})
)

;; Retrieve participant information
(define-read-only (get-participant (participant-principal principal))
  (map-get? participants participant-principal)
)

;; Get a specific history entry for a product
(define-read-only (get-history-entry (product-id (string-ascii 36)) (entry-index uint))
  (map-get? product-history {product-id: product-id, entry-index: entry-index})
)

;; Get the total number of history entries for a product
(define-read-only (get-history-entry-count (product-id (string-ascii 36)))
  (default-to {count: u0} (map-get? product-entry-count {product-id: product-id}))
)

;; Get certification information for a product
(define-read-only (get-product-certification (product-id (string-ascii 36)))
  (map-get? product-certifications {product-id: product-id})
)

;; Verify if a product exists
(define-read-only (product-exists (product-id (string-ascii 36)))
  (is-some (map-get? products {product-id: product-id}))
)

;; Public functions

;; Register a new supply chain participant
(define-public (register-participant 
  (role uint) 
  (name (string-ascii 100)) 
  (location (string-ascii 100)))
  
  (begin
    ;; Check that role is valid
    (asserts! (and (>= role ROLE-FARMER) (<= role ROLE-CERTIFIER)) ERR-INVALID-PARAMS)
    
    ;; Register the participant
    (map-set participants tx-sender
      {
        role: role,
        name: name,
        location: location,
        registration-time: (unwrap-panic (get-block-info? time u0)),
        active: true
      }
    )
    (ok true)
  )
)

;; Register a new product batch (farmers only)
(define-public (register-product 
  (product-id (string-ascii 36)) 
  (name (string-ascii 100)) 
  (description (string-ascii 500))
  (quantity uint)
  (unit (string-ascii 20))
  (harvest-date uint)
  (farming-practices (string-ascii 200))
  (location (string-ascii 100))
  (notes (string-ascii 500)))
  
  (begin
    ;; Check if the caller is a registered farmer
    (asserts! (is-participant-with-role tx-sender ROLE-FARMER) ERR-NOT-AUTHORIZED)
    
    ;; Check that the product ID is not already used
    (asserts! (not (product-exists product-id)) ERR-ALREADY-REGISTERED)
    
    ;; Register the product
    (map-set products 
      {product-id: product-id}
      {
        farmer: tx-sender,
        name: name,
        description: description,
        quantity: quantity,
        unit: unit,
        harvest-date: harvest-date,
        farming-practices: farming-practices,
        registration-time: (unwrap-panic (get-block-info? time u0)),
        current-handler: tx-sender,
        is-certified: false
      }
    )
    
    ;; Add the initial history entry
    (add-history-entry 
      product-id 
      tx-sender 
      ROLE-FARMER 
      "product-registered" 
      location 
      notes
    )
    
    ;; Initialize the history entry count
    (map-set product-entry-count {product-id: product-id} {count: u1})
    
    (ok true)
  )
)

;; Transfer product custody to another supply chain participant
(define-public (transfer-product 
  (product-id (string-ascii 36)) 
  (recipient principal) 
  (location (string-ascii 100))
  (notes (string-ascii 500)))
  
  (let (
    (product (unwrap! (get-product product-id) ERR-PRODUCT-NOT-FOUND))
    (recipient-data (unwrap! (get-participant recipient) ERR-INVALID-HANDLER))
  )
    ;; Check that the caller is the current handler
    (asserts! (is-current-handler tx-sender product-id) ERR-NOT-CURRENT-HANDLER)
    
    ;; Check that recipient is a registered participant
    (asserts! (get active recipient-data) ERR-INVALID-HANDLER)
    
    ;; Update the current handler
    (map-set products 
      {product-id: product-id} 
      (merge product {current-handler: recipient})
    )
    
    ;; Add a history entry for the transfer
    (add-history-entry 
      product-id 
      tx-sender 
      (get role (unwrap-panic (get-participant tx-sender)))
      "transfer" 
      location 
      notes
    )
    
    (ok true)
  )
)

;; Add a processing or handling event to a product's history
(define-public (record-handling-event 
  (product-id (string-ascii 36)) 
  (action (string-ascii 50))
  (location (string-ascii 100))
  (notes (string-ascii 500)))
  
  (let ((handler-data (unwrap! (get-participant tx-sender) ERR-NOT-AUTHORIZED)))
    ;; Check that the caller is the current handler
    (asserts! (is-current-handler tx-sender product-id) ERR-NOT-CURRENT-HANDLER)
    
    ;; Add the handling event to history
    (add-history-entry 
      product-id 
      tx-sender 
      (get role handler-data)
      action 
      location 
      notes
    )
    
    (ok true)
  )
)

;; Add certification to a product (certifiers only)
(define-public (certify-product 
  (product-id (string-ascii 36)) 
  (certification-type (string-ascii 100))
  (expiration-date uint)
  (standards-met (string-ascii 500))
  (location (string-ascii 100))
  (notes (string-ascii 500)))
  
  (let ((product (unwrap! (get-product product-id) ERR-PRODUCT-NOT-FOUND)))
    ;; Check that the caller is a certifier
    (asserts! (is-participant-with-role tx-sender ROLE-CERTIFIER) ERR-NOT-AUTHORIZED)
    
    ;; Check that the product isn't already certified
    (asserts! (not (get is-certified product)) ERR-ALREADY-CERTIFIED)
    
    ;; Add certification record
    (map-set product-certifications 
      {product-id: product-id}
      {
        certifier: tx-sender,
        certification-type: certification-type,
        certification-date: (unwrap-panic (get-block-info? time u0)),
        expiration-date: expiration-date,
        standards-met: standards-met
      }
    )
    
    ;; Update the product's certification status
    (map-set products 
      {product-id: product-id} 
      (merge product {is-certified: true})
    )
    
    ;; Add a history entry for the certification
    (add-history-entry 
      product-id 
      tx-sender 
      ROLE-CERTIFIER
      "certification" 
      location 
      notes
    )
    
    (ok true)
  )
)

;; Update participant information
(define-public (update-participant-info 
  (name (string-ascii 100)) 
  (location (string-ascii 100))
  (active bool))
  
  (let ((participant (unwrap! (get-participant tx-sender) ERR-NOT-AUTHORIZED)))
    ;; Update participant information
    (map-set participants 
      tx-sender
      (merge participant {
        name: name,
        location: location,
        active: active
      })
    )
    (ok true)
  )
)