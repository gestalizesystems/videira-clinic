class CreditPurchaseConfirmer < ApplicationService
  def initialize(credit_purchase:)
    @purchase = credit_purchase
  end

  def call
    return success(:not_found)         unless @purchase
    return success(:already_processed) if @purchase.paid?

    ActiveRecord::Base.transaction do
      credit = Credit.create!(
        user:         @purchase.user,
        clinic:       @purchase.clinic,
        amount_cents: @purchase.amount_cents,
        reason:       "Recarga de crédito"
      )
      @purchase.update!(status: "paid", paid_at: Time.current, credit: credit)
    end

    success(@purchase)
  rescue ActiveRecord::RecordInvalid => e
    log_error("credit_purchase=#{@purchase&.id} error=#{e.message}")
    failure(e.message)
  end

  # Confirma a partir do payload do webhook/retorno InfinitePay.
  def self.call_from_webhook(payload)
    purchase = CreditPurchase.find_by(id: payload["order_nsu"])
    return unless purchase

    result = call(credit_purchase: purchase)

    if result.success? && payload["transaction_nsu"].present?
      purchase.update_columns(gateway_id: payload["transaction_nsu"])
    end

    result
  end
end
