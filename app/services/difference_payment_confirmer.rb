class DifferencePaymentConfirmer < ApplicationService
  def initialize(payment:)
    @payment = payment
  end

  def call
    return success(:not_found)         unless @payment
    return success(:already_processed) if @payment.paid?

    ActiveRecord::Base.transaction do
      @payment.update!(status: "paid", paid_at: Time.current)
      attach_extras_to_group! if @payment.extras.present?
    end
    BookingMailer.admin_extras_notification(@payment).deliver_later if @payment.extras.present?
    success(@payment)
  rescue ActiveRecord::RecordInvalid => e
    log_error("payment=#{@payment&.id} error=#{e.message}")
    failure(e.message)
  end

  # Anexa os insumos pagos à reserva e atualiza os totais do grupo.
  def attach_extras_to_group!
    group = @payment.booking_group
    added = Array(@payment.extras).sum { |e| e["price_cents"].to_i * e["quantity"].to_i }
    group.update!(
      extras:         Array(group.extras) + Array(@payment.extras),
      subtotal_cents: group.subtotal_cents.to_i + added,
      total_cents:    group.total_cents.to_i + added
    )
  end

  # Confirma a partir do payload do webhook/retorno (order_nsu = payment.id).
  def self.call_from_webhook(payload)
    payment = Payment.find_by(id: payload["order_nsu"])
    return unless payment

    result = call(payment: payment)

    if result.success?
      updates = {}
      updates[:capture_method] = payload["capture_method"] if Payment::CAPTURE_METHODS.include?(payload["capture_method"])
      updates[:gateway_id]     = payload["transaction_nsu"] if payload["transaction_nsu"].present?
      payment.update_columns(**updates) if updates.present?
    end

    result
  end
end
