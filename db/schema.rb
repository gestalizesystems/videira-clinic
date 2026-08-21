# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_08_21_025008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "availabilities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.uuid "service_id"
    t.uuid "dentist_id"
    t.date "date", null: false
    t.time "starts_at", null: false
    t.time "ends_at", null: false
    t.string "status", default: "available", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price_cents", default: 0, null: false
    t.uuid "eclipsed_by_id"
    t.index ["clinic_id"], name: "index_availabilities_on_clinic_id"
    t.index ["dentist_id", "date", "starts_at"], name: "idx_availabilities_no_double_booking", unique: true
    t.index ["dentist_id"], name: "index_availabilities_on_dentist_id"
    t.index ["eclipsed_by_id"], name: "index_availabilities_on_eclipsed_by_id"
    t.index ["service_id"], name: "index_availabilities_on_service_id"
    t.check_constraint "status::text = ANY (ARRAY['available'::character varying, 'booked'::character varying, 'cancelled'::character varying, 'blocked'::character varying]::text[])", name: "availabilities_status_check"
  end

  create_table "booking_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.uuid "dentist_id", null: false
    t.uuid "discount_rule_id"
    t.integer "subtotal_cents", null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "total_cents", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "extras", default: [], null: false
    t.index ["clinic_id"], name: "index_booking_groups_on_clinic_id"
    t.index ["dentist_id"], name: "index_booking_groups_on_dentist_id"
    t.index ["discount_rule_id"], name: "index_booking_groups_on_discount_rule_id"
    t.check_constraint "discount_cents >= 0", name: "booking_groups_discount_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'cancelled'::character varying, 'expired'::character varying]::text[])", name: "booking_groups_status_check"
    t.check_constraint "total_cents > 0", name: "booking_groups_total_positive"
  end

  create_table "bookings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.uuid "booking_group_id", null: false
    t.uuid "availability_id", null: false
    t.uuid "dentist_id", null: false
    t.integer "price_cents", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "google_event_id"
    t.index ["availability_id"], name: "idx_bookings_availability_unique_active", unique: true, where: "((status)::text <> 'cancelled'::text)"
    t.index ["availability_id"], name: "index_bookings_on_availability_id"
    t.index ["booking_group_id"], name: "index_bookings_on_booking_group_id"
    t.index ["clinic_id"], name: "index_bookings_on_clinic_id"
    t.index ["dentist_id"], name: "index_bookings_on_dentist_id"
    t.check_constraint "price_cents >= 0", name: "bookings_price_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'cancelled'::character varying]::text[])", name: "bookings_status_check"
  end

  create_table "clinics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "cnpj", null: false
    t.string "phone", null: false
    t.string "email", null: false
    t.string "logo_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "shifts_generated_until"
    t.index ["cnpj"], name: "index_clinics_on_cnpj", unique: true
  end

  create_table "credit_purchases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "clinic_id", null: false
    t.uuid "credit_id"
    t.integer "amount_cents", null: false
    t.string "status", default: "pending", null: false
    t.string "gateway", default: "infinitepay", null: false
    t.string "checkout_url"
    t.string "gateway_id"
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinic_id"], name: "index_credit_purchases_on_clinic_id"
    t.index ["credit_id"], name: "index_credit_purchases_on_credit_id"
    t.index ["status"], name: "index_credit_purchases_on_status"
    t.index ["user_id"], name: "index_credit_purchases_on_user_id"
    t.check_constraint "amount_cents > 0", name: "credit_purchases_amount_positive"
  end

  create_table "credits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "clinic_id", null: false
    t.uuid "source_booking_group_id"
    t.uuid "used_on_booking_group_id"
    t.integer "amount_cents", null: false
    t.string "reason"
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "in_revenue", default: true, null: false
    t.index ["clinic_id"], name: "index_credits_on_clinic_id"
    t.index ["source_booking_group_id"], name: "index_credits_on_source_booking_group_id"
    t.index ["used_on_booking_group_id"], name: "index_credits_on_used_on_booking_group_id"
    t.index ["user_id", "clinic_id", "used_at"], name: "index_credits_on_user_id_and_clinic_id_and_used_at"
    t.index ["user_id"], name: "index_credits_on_user_id"
    t.check_constraint "amount_cents > 0", name: "credits_amount_positive"
  end

  create_table "discount_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.integer "min_slots", null: false
    t.integer "discount_percent"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.index ["clinic_id", "min_slots"], name: "idx_discount_rules_unique_active", unique: true, where: "(active = true)"
    t.index ["clinic_id"], name: "index_discount_rules_on_clinic_id"
    t.check_constraint "discount_percent >= 1 AND discount_percent <= 100", name: "discount_rules_percent_range"
    t.check_constraint "min_slots > 0", name: "discount_rules_min_slots_positive"
  end

  create_table "extras", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinic_id"], name: "index_extras_on_clinic_id"
  end

  create_table "manual_revenue_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.uuid "client_id", null: false
    t.uuid "created_by_id", null: false
    t.integer "amount_cents", null: false
    t.string "category", null: false
    t.date "month", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_manual_revenue_entries_on_client_id"
    t.index ["clinic_id"], name: "index_manual_revenue_entries_on_clinic_id"
    t.index ["created_by_id"], name: "index_manual_revenue_entries_on_created_by_id"
    t.check_constraint "amount_cents > 0", name: "manual_revenue_entries_amount_positive"
    t.check_constraint "category::text = ANY (ARRAY['turno'::character varying, 'insumo'::character varying]::text[])", name: "manual_revenue_entries_category_check"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.uuid "booking_group_id", null: false
    t.integer "amount_cents", null: false
    t.string "status", default: "pending", null: false
    t.string "gateway", default: "infinitepay", null: false
    t.string "gateway_id"
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "checkout_url"
    t.jsonb "extras", default: [], null: false
    t.string "capture_method"
    t.index ["booking_group_id"], name: "index_payments_on_booking_group_id"
    t.index ["clinic_id"], name: "index_payments_on_clinic_id"
    t.index ["gateway_id"], name: "index_payments_on_gateway_id", unique: true, where: "(gateway_id IS NOT NULL)"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'paid'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'expired'::character varying]::text[])", name: "payments_status_check"
  end

  create_table "services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "duration_minutes", null: false
    t.integer "price_cents", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinic_id"], name: "index_services_on_clinic_id"
    t.check_constraint "duration_minutes > 0", name: "services_duration_positive"
    t.check_constraint "price_cents >= 0", name: "services_price_non_negative"
  end

  create_table "shift_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id", null: false
    t.time "starts_at", null: false
    t.time "ends_at", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinic_id"], name: "index_shift_templates_on_clinic_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clinic_id"
    t.string "name", null: false
    t.string "phone"
    t.date "birth_date"
    t.string "cpf"
    t.string "role", default: "dentist", null: false
    t.string "provider"
    t.string "uid"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cro"
    t.string "specialty"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.text "google_refresh_token"
    t.integer "discount_per_slot_cents", default: 0, null: false
    t.index ["clinic_id"], name: "index_users_on_clinic_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["cpf"], name: "index_users_on_cpf", unique: true, where: "(cpf IS NOT NULL)"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying::text, 'dentist'::character varying::text])", name: "users_role_check"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.string "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "availabilities", "clinics"
  add_foreign_key "availabilities", "services"
  add_foreign_key "availabilities", "users", column: "dentist_id"
  add_foreign_key "booking_groups", "clinics"
  add_foreign_key "booking_groups", "discount_rules"
  add_foreign_key "booking_groups", "users", column: "dentist_id"
  add_foreign_key "bookings", "availabilities"
  add_foreign_key "bookings", "booking_groups"
  add_foreign_key "bookings", "clinics"
  add_foreign_key "bookings", "users", column: "dentist_id"
  add_foreign_key "credit_purchases", "clinics"
  add_foreign_key "credit_purchases", "credits"
  add_foreign_key "credit_purchases", "users"
  add_foreign_key "credits", "booking_groups", column: "source_booking_group_id"
  add_foreign_key "credits", "booking_groups", column: "used_on_booking_group_id"
  add_foreign_key "credits", "clinics"
  add_foreign_key "credits", "users"
  add_foreign_key "discount_rules", "clinics"
  add_foreign_key "extras", "clinics"
  add_foreign_key "manual_revenue_entries", "clinics"
  add_foreign_key "manual_revenue_entries", "users", column: "client_id"
  add_foreign_key "manual_revenue_entries", "users", column: "created_by_id"
  add_foreign_key "payments", "booking_groups"
  add_foreign_key "payments", "clinics"
  add_foreign_key "services", "clinics"
  add_foreign_key "shift_templates", "clinics"
  add_foreign_key "users", "clinics"
end
