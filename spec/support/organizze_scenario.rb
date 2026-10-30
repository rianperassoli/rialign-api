# Drives the API the way the web app does — every step is an HTTP call — so a
# scenario reads as what the user did and what Organizze would show after it.
#
# Used by spec/requests/organizze_parity: each spec builds a situation with
# made-up data and checks the figures Organizze shows for the same situation.
# Where Rialign deliberately differs from Organizze, the spec says so.
module OrganizzeScenario
  def api(verb, path, body = nil, expect: nil)
    send(verb, "/api/v1#{path}", params: body&.to_json, headers: auth_headers(user))
    expect(response).to have_http_status(expect) if expect
    response.body.present? ? json : {}
  end

  def money(value)
    BigDecimal(value.to_s)
  end

  def account(name, initial_balance: 0, **attrs)
    api(:post, "/accounts", { account: { name:, initial_balance:, **attrs } }, expect: :created).dig("data", "id")
  end

  def category(name, kind: "expense", parent: nil)
    api(:post, "/categories", { category: { name:, kind:, parent_id: parent } }, expect: :created).dig("data", "id")
  end

  def card(name, limit:, closing_day:, due_day:, payment_account: nil)
    body = { credit_card: { name:, credit_limit: limit, closing_day:, due_day:, payment_account_id: payment_account } }
    api(:post, "/credit_cards", body, expect: :created).dig("data", "id")
  end

  # An expense or income on an account or a card. Takes category:, transaction
  # fields (kind:, paid:) and the web form's series options (installments:,
  # fixed_months:, fixed:).
  def entry(description, amount, on:, date:, **options)
    source = on.is_a?(Hash) ? on : { account_id: on }
    series = options.extract!(:installments, :fixed_months, :fixed)
    category_id = options.delete(:category)
    body = { transaction: { description:, kind: "expense", amount:, date:, category_id:, **options, **source },
             **series }
    api(:post, "/transactions", body, expect: :created)["data"]
  end

  def income(description, amount, **)
    entry(description, amount, kind: "income", **)
  end

  def transfer(from, to, amount, date:, **extra)
    body = { transfer: { from_account_id: from, to_account_id: to, amount:, date:, **extra } }
    api(:post, "/transfers", body, expect: :created)
  end

  def dashboard(month)
    api(:get, "/dashboard?month=#{month}", expect: :ok)["data"]
  end

  def balance_of(account_id, month: Date.current.strftime("%Y-%m"))
    money(dashboard(month)["accounts"].find { |a| a["id"] == account_id }["current_balance"])
  end

  def card_summary(card_id)
    api(:get, "/credit_cards/#{card_id}", expect: :ok)["data"]
  end

  def invoice(card_id, month)
    api(:get, "/credit_cards/#{card_id}/invoice?month=#{month}", expect: :ok)["data"]
  end

  def pay_invoice(card_id, month, account_id:, date:, amount: nil)
    body = { payment: { month:, account_id:, date:, amount: }.compact }
    api(:post, "/credit_cards/#{card_id}/pay_invoice", body, expect: :created)["data"]
  end

  def transactions(**filters)
    query = filters.merge(items: 100).to_query
    api(:get, "/transactions?#{query}", expect: :ok)["data"]
  end
end
