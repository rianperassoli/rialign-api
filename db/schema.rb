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

ActiveRecord::Schema[8.0].define(version: 2026_09_02_163325) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "account_type", default: "checking", null: false
    t.decimal "initial_balance", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "exclude_from_total", default: false, null: false
    t.index ["archived_at"], name: "index_accounts_on_archived_at"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "color"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_categories_on_archived_at"
    t.index ["user_id", "kind"], name: "index_categories_on_user_id_and_kind"
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "credit_cards", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.decimal "credit_limit", precision: 14, scale: 2, default: "0.0", null: false
    t.integer "closing_day", default: 1, null: false
    t.integer "due_day", default: 10, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "payment_account_id"
    t.index ["archived_at"], name: "index_credit_cards_on_archived_at"
    t.index ["payment_account_id"], name: "index_credit_cards_on_payment_account_id"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
  end

  create_table "imports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "filename", null: false
    t.string "file_path", null: false
    t.jsonb "report", default: {}, null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "preview", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.index ["user_id", "created_at"], name: "index_imports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id"
    t.bigint "account_id"
    t.bigint "credit_card_id"
    t.string "description", null: false
    t.string "kind", null: false
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.date "date", null: false
    t.boolean "paid", null: false
    t.text "notes"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "transfer_id"
    t.uuid "series_id"
    t.integer "installment_number"
    t.integer "installment_total"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["archived_at"], name: "index_transactions_on_archived_at"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["credit_card_id"], name: "index_transactions_on_credit_card_id"
    t.index ["series_id"], name: "index_transactions_on_series_id"
    t.index ["transfer_id"], name: "index_transactions_on_transfer_id"
    t.index ["user_id", "date"], name: "index_transactions_on_user_id_and_date"
    t.index ["user_id", "kind"], name: "index_transactions_on_user_id_and_kind"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "credit_cards", "accounts", column: "payment_account_id"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "imports", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "credit_cards"
  add_foreign_key "transactions", "users"
end
