-- ============================================================
-- Tendly DataSphere - schema.sql (PostgreSQL)
-- ============================================================

BEGIN;

-- -------------------------
-- 0) Helpful extensions (optional)
-- -------------------------
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- if you later want gen_random_uuid()

-- ============================================================
-- 1) USER DOMAIN
-- ============================================================

CREATE TABLE app_user (
  user_id        BIGSERIAL PRIMARY KEY,
  name           TEXT NOT NULL,
  email          TEXT UNIQUE,
  phone          TEXT UNIQUE,
  status         TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','inactive','suspended','deleted')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE user_profile (
  profile_id              BIGSERIAL PRIMARY KEY,
  user_id                 BIGINT NOT NULL UNIQUE REFERENCES app_user(user_id) ON DELETE CASCADE,
  bio                     TEXT,
  notification_preferences JSONB,
  user_favourites         JSONB,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Address as a shared entity (roommates can share same address)
CREATE TABLE address (
  address_id   BIGSERIAL PRIMARY KEY,
  line1        TEXT NOT NULL,
  line2        TEXT,
  city         TEXT NOT NULL,
  state        TEXT,
  country      TEXT NOT NULL DEFAULT 'US',
  pin_code     TEXT,
  latitude     NUMERIC(9,6),
  longitude    NUMERIC(9,6),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User <-> Address association (stores user-specific label/default)
CREATE TABLE user_address (
  user_id     BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  address_id  BIGINT NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
  label       TEXT NOT NULL DEFAULT 'other'
             CHECK (label IN ('home','work','other')),
  is_default  BOOLEAN NOT NULL DEFAULT FALSE,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, address_id)
);

CREATE TABLE auth_session (
  session_id   BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  device_info  TEXT,
  login_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  logout_time  TIMESTAMPTZ,
  ip_address   TEXT,
  CHECK (logout_time IS NULL OR logout_time >= login_time)
);

-- ============================================================
-- 2) MERCHANT DOMAIN
-- ============================================================

CREATE TABLE merchant (
  merchant_id    BIGSERIAL PRIMARY KEY,
  user_id        BIGINT UNIQUE REFERENCES app_user(user_id) ON DELETE SET NULL, -- if merchant account tied to a user
  business_name  TEXT NOT NULL,
  business_type  TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','inactive','suspended','deleted')),
  rating_avg     NUMERIC(3,2) NOT NULL DEFAULT 0 CHECK (rating_avg >= 0 AND rating_avg <= 5),
  rating_count   INTEGER NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE merchant_location (
  location_id   BIGSERIAL PRIMARY KEY,
  merchant_id   BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  address_id    BIGINT NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
  is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE merchant_settings (
  merchant_id      BIGINT PRIMARY KEY REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  settings_json    JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE merchant_payout (
  payout_id     BIGSERIAL PRIMARY KEY,
  merchant_id   BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  amount        NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  currency      TEXT NOT NULL DEFAULT 'USD',
  status        TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','processing','paid','failed')),
  provider_ref  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paid_at       TIMESTAMPTZ
);

CREATE TABLE merchant_analytics (
  merchant_id     BIGINT PRIMARY KEY REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  total_orders    BIGINT NOT NULL DEFAULT 0 CHECK (total_orders >= 0),
  total_sales     NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_sales >= 0),
  last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 3) CATALOG DOMAIN
-- ============================================================

CREATE TABLE category (
  category_id        BIGSERIAL PRIMARY KEY,
  name               TEXT NOT NULL,
  parent_category_id BIGINT REFERENCES category(category_id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (parent_category_id, name)
);

CREATE TABLE listing (
  listing_id     BIGSERIAL PRIMARY KEY,
  merchant_id    BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  category_id    BIGINT REFERENCES category(category_id) ON DELETE SET NULL,
  title          TEXT NOT NULL,
  description    TEXT,
  listing_type   TEXT NOT NULL
               CHECK (listing_type IN ('food','product','service','spot','experience')),
  status         TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('active','inactive','draft','archived')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE tag (
  tag_id   BIGSERIAL PRIMARY KEY,
  name     TEXT NOT NULL UNIQUE
);

CREATE TABLE listing_tag (
  listing_id BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  tag_id     BIGINT NOT NULL REFERENCES tag(tag_id) ON DELETE CASCADE,
  PRIMARY KEY (listing_id, tag_id)
);

CREATE TABLE listing_media (
  media_id     BIGSERIAL PRIMARY KEY,
  listing_id   BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  media_url    TEXT NOT NULL,
  media_type   TEXT NOT NULL CHECK (media_type IN ('image','video')),
  uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pricing (
  pricing_id      BIGSERIAL PRIMARY KEY,
  listing_id      BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  base_price      NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
  discount_price  NUMERIC(12,2) CHECK (discount_price IS NULL OR discount_price >= 0),
  currency        TEXT NOT NULL DEFAULT 'USD',
  effective_from  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  effective_to    TIMESTAMPTZ,
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  CHECK (discount_price IS NULL OR discount_price <= base_price)
);

CREATE TABLE inventory (
  inventory_id           BIGSERIAL PRIMARY KEY,
  listing_id             BIGINT NOT NULL UNIQUE REFERENCES listing(listing_id) ON DELETE CASCADE,
  quantity_available     INTEGER NOT NULL DEFAULT 0 CHECK (quantity_available >= 0),
  quantity_reserved      INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  slots_available_per_day INTEGER CHECK (slots_available_per_day IS NULL OR slots_available_per_day >= 0),
  last_updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (quantity_available >= quantity_reserved)
);

-- -------- Multi-dimensional Variants --------

CREATE TABLE variant (
  variant_id   BIGSERIAL PRIMARY KEY,
  listing_id   BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  sku          TEXT,
  base_price   NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
  stock        INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  UNIQUE (listing_id, sku)
);

CREATE TABLE variant_attribute (
  attribute_id  BIGSERIAL PRIMARY KEY,
  listing_id    BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  UNIQUE (listing_id, name)
);

CREATE TABLE variant_attribute_value (
  value_id          BIGSERIAL PRIMARY KEY,
  attribute_id      BIGINT NOT NULL REFERENCES variant_attribute(attribute_id) ON DELETE CASCADE,
  value_name        TEXT NOT NULL,
  additional_price  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (additional_price >= 0),
  UNIQUE (attribute_id, value_name)
);

-- Bridge: Variant <-> Variant_Attribute_Value
CREATE TABLE variant_option (
  variant_option_id BIGSERIAL PRIMARY KEY,
  variant_id        BIGINT NOT NULL REFERENCES variant(variant_id) ON DELETE CASCADE,
  value_id          BIGINT NOT NULL REFERENCES variant_attribute_value(value_id) ON DELETE RESTRICT,
  UNIQUE (variant_id, value_id)
);

-- ============================================================
-- 4) ORDER DOMAIN
-- ============================================================

CREATE TABLE "order" (
  order_id        BIGSERIAL PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE RESTRICT,
  merchant_id     BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE RESTRICT,
  order_type      TEXT NOT NULL CHECK (order_type IN ('delivery','pickup','booking','service')),
  order_status    TEXT NOT NULL DEFAULT 'created'
                 CHECK (order_status IN ('created','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded')),
  subtotal_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
  tax_amount      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  delivery_fee    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
  discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  total_amount    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE order_item (
  order_item_id           BIGSERIAL PRIMARY KEY,
  order_id                BIGINT NOT NULL REFERENCES "order"(order_id) ON DELETE CASCADE,
  listing_id              BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE RESTRICT,
  variant_id              BIGINT REFERENCES variant(variant_id) ON DELETE SET NULL,
  quantity                INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_at_purchase  NUMERIC(12,2) NOT NULL CHECK (unit_price_at_purchase >= 0),
  line_total              NUMERIC(12,2) NOT NULL CHECK (line_total >= 0)
);

CREATE TABLE order_address (
  order_address_id       BIGSERIAL PRIMARY KEY,
  order_id               BIGINT NOT NULL UNIQUE REFERENCES "order"(order_id) ON DELETE CASCADE,
  address_id             BIGINT REFERENCES address(address_id) ON DELETE SET NULL,
  address_snapshot_text  TEXT,
  label_snapshot         TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (address_id IS NOT NULL OR address_snapshot_text IS NOT NULL)
);

CREATE TABLE order_payment (
  payment_id       BIGSERIAL PRIMARY KEY,
  order_id         BIGINT NOT NULL REFERENCES "order"(order_id) ON DELETE CASCADE,
  payment_method   TEXT NOT NULL CHECK (payment_method IN ('card','wallet','upi','cash','bank_transfer')),
  payment_status   TEXT NOT NULL DEFAULT 'initiated'
                  CHECK (payment_status IN ('initiated','authorized','paid','failed','refunded')),
  amount           NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  provider_txn_id  TEXT,
  paid_at          TIMESTAMPTZ
);

CREATE TABLE order_status_history (
  history_id   BIGSERIAL PRIMARY KEY,
  order_id     BIGINT NOT NULL REFERENCES "order"(order_id) ON DELETE CASCADE,
  old_status   TEXT,
  new_status   TEXT NOT NULL,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  changed_by   TEXT
);

-- ============================================================
-- 5) DELIVERY DOMAIN
-- ============================================================

CREATE TABLE delivery (
  delivery_id      BIGSERIAL PRIMARY KEY,
  order_id         BIGINT NOT NULL UNIQUE REFERENCES "order"(order_id) ON DELETE CASCADE,
  delivery_status  TEXT NOT NULL DEFAULT 'queued'
                  CHECK (delivery_status IN ('queued','assigned','picked_up','in_transit','delivered','failed','cancelled')),
  pickup_time      TIMESTAMPTZ,
  delivered_time   TIMESTAMPTZ,
  delivery_fee     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (delivered_time IS NULL OR pickup_time IS NULL OR delivered_time >= pickup_time)
);

CREATE TABLE delivery_agent (
  agent_id      BIGSERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  phone         TEXT UNIQUE,
  vehicle_type  TEXT,
  status        TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('active','inactive','suspended')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE delivery_assignment (
  assignment_id      BIGSERIAL PRIMARY KEY,
  delivery_id        BIGINT NOT NULL REFERENCES delivery(delivery_id) ON DELETE CASCADE,
  agent_id           BIGINT NOT NULL REFERENCES delivery_agent(agent_id) ON DELETE RESTRICT,
  assignment_status  TEXT NOT NULL DEFAULT 'assigned'
                    CHECK (assignment_status IN ('assigned','accepted','rejected','completed','cancelled')),
  assigned_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unassigned_at      TIMESTAMPTZ,
  CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)
);

CREATE TABLE delivery_tracking_event (
  event_id     BIGSERIAL PRIMARY KEY,
  delivery_id  BIGINT NOT NULL REFERENCES delivery(delivery_id) ON DELETE CASCADE,
  event_type   TEXT NOT NULL,
  latitude     NUMERIC(9,6),
  longitude    NUMERIC(9,6),
  event_time   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6) BOOKING DOMAIN
-- ============================================================

CREATE TABLE booking (
  booking_id      BIGSERIAL PRIMARY KEY,
  order_id        BIGINT UNIQUE REFERENCES "order"(order_id) ON DELETE SET NULL,
  user_id         BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE RESTRICT,
  merchant_id     BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE RESTRICT,
  listing_id      BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE RESTRICT,
  booking_status  TEXT NOT NULL DEFAULT 'requested'
                 CHECK (booking_status IN ('requested','confirmed','rescheduled','cancelled','completed','no_show')),
  party_size      INTEGER CHECK (party_size IS NULL OR party_size > 0),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE time_slot (
  slot_id          BIGSERIAL PRIMARY KEY,
  merchant_id      BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  listing_id       BIGINT NOT NULL REFERENCES listing(listing_id) ON DELETE CASCADE,
  start_time       TIMESTAMPTZ NOT NULL,
  end_time         TIMESTAMPTZ NOT NULL,
  capacity         INTEGER NOT NULL DEFAULT 1 CHECK (capacity > 0),
  slots_available  INTEGER NOT NULL DEFAULT 1 CHECK (slots_available >= 0),
  slot_status      TEXT NOT NULL DEFAULT 'open'
                  CHECK (slot_status IN ('open','blocked','fully_booked','cancelled')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_time > start_time),
  CHECK (slots_available <= capacity)
);

-- Bridge: Booking <-> Time_Slot
CREATE TABLE booking_slot (
  booking_slot_id  BIGSERIAL PRIMARY KEY,
  booking_id       BIGINT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
  slot_id          BIGINT NOT NULL REFERENCES time_slot(slot_id) ON DELETE RESTRICT,
  reserved_count   INTEGER NOT NULL DEFAULT 1 CHECK (reserved_count > 0),
  UNIQUE (booking_id, slot_id)
);

CREATE TABLE booking_status_history (
  history_id   BIGSERIAL PRIMARY KEY,
  booking_id   BIGINT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
  old_status   TEXT,
  new_status   TEXT NOT NULL,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  changed_by   TEXT
);

-- ============================================================
-- 7) REVIEW & RATING DOMAIN
-- ============================================================

CREATE TABLE review (
  review_id      BIGSERIAL PRIMARY KEY,
  user_id        BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  listing_id     BIGINT REFERENCES listing(listing_id) ON DELETE CASCADE,
  merchant_id    BIGINT REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  order_id       BIGINT REFERENCES "order"(order_id) ON DELETE SET NULL,
  rating         INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_title   TEXT,
  review_text    TEXT,
  is_verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
  review_status  TEXT NOT NULL DEFAULT 'active'
               CHECK (review_status IN ('active','hidden','reported','removed')),
  helpful_count  INTEGER NOT NULL DEFAULT 0 CHECK (helpful_count >= 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (listing_id IS NOT NULL OR merchant_id IS NOT NULL)
);

CREATE TABLE review_media (
  media_id     BIGSERIAL PRIMARY KEY,
  review_id    BIGINT NOT NULL REFERENCES review(review_id) ON DELETE CASCADE,
  media_url    TEXT NOT NULL,
  media_type   TEXT NOT NULL CHECK (media_type IN ('image','video')),
  uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1:0..1 response enforced by making review_id the PK (and FK)
CREATE TABLE review_response (
  review_id     BIGINT PRIMARY KEY REFERENCES review(review_id) ON DELETE CASCADE,
  merchant_id   BIGINT NOT NULL REFERENCES merchant(merchant_id) ON DELETE CASCADE,
  response_text TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE review_report (
  report_id            BIGSERIAL PRIMARY KEY,
  review_id            BIGINT NOT NULL REFERENCES review(review_id) ON DELETE CASCADE,
  reported_by_user_id  BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  reason               TEXT NOT NULL
                       CHECK (reason IN ('spam','abuse','fake','irrelevant','other')),
  report_status        TEXT NOT NULL DEFAULT 'open'
                       CHECK (report_status IN ('open','under_review','resolved','dismissed')),
  admin_notes          TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at          TIMESTAMPTZ
);

-- ============================================================
-- Indexes (minimal, high impact)
-- ============================================================

CREATE INDEX idx_listing_merchant ON listing(merchant_id);
CREATE INDEX idx_listing_category ON listing(category_id);

CREATE INDEX idx_order_user_created ON "order"(user_id, created_at DESC);
CREATE INDEX idx_order_merchant_created ON "order"(merchant_id, created_at DESC);

CREATE INDEX idx_order_item_order ON order_item(order_id);
CREATE INDEX idx_delivery_status ON delivery(delivery_status);

CREATE INDEX idx_time_slot_listing_time ON time_slot(listing_id, start_time);
CREATE INDEX idx_booking_user_created ON booking(user_id, created_at DESC);

CREATE INDEX idx_review_listing ON review(listing_id);
CREATE INDEX idx_review_merchant ON review(merchant_id);

COMMIT;
