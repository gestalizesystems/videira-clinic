class PaymentConfirmer < ApplicationService
  def initialize(external_reference:)
    @external_reference = external_reference
  end

  def call
    group = BookingGroup.find_by(id: @external_reference)
    return success(:not_found) if group.nil?
    return success(:already_processed) if group.confirmed?
    # Pagamento chegou após a reserva expirar (vaga já liberada):
    # converte o valor pago em crédito na conta, sem confirmar a reserva.
    return credit_late_payment(group) if group.expired?

    ActiveRecord::Base.transaction do
      payment = group.payment

      group.update!(status: "confirmed")
      group.bookings.update_all(status: "confirmed")
      payment.update!(status: "paid", paid_at: Time.current)
    end

    broadcast_confirmed(group.payment.reload)
    BookingMailer.confirmation(group).deliver_later
    BookingMailer.admin_notification(group).deliver_later
    success(group)
  rescue ActiveRecord::RecordInvalid => e
    log_error("ref=#{@external_reference} error=#{e.message}")
    failure(e.message)
  end

  private

  # Pagamento (Pix ou cartão) que chegou depois da expiração: vira crédito na
  # conta da pessoa. Idempotente — não credita duas vezes se o webhook repetir.
  def credit_late_payment(group)
    payment = group.payment
    if payment.nil? || payment.paid? || Credit.exists?(source_booking_group: group)
      return success(:already_processed)
    end

    credit = ActiveRecord::Base.transaction do
      payment.update!(status: "paid", paid_at: Time.current)
      result = CreditIssuer.call(
        booking_group: group,
        reason: "Pagamento recebido após expiração da reserva — convertido em crédito"
      )
      raise ActiveRecord::Rollback unless result.success? && result.value
      result.value
    end

    return success(:already_processed) unless credit

    BookingMailer.credit_issued(group.dentist, credit).deliver_later
    success(:credited)
  rescue ActiveRecord::RecordInvalid => e
    log_error("late credit ref=#{@external_reference} error=#{e.message}")
    failure(e.message)
  end

  def broadcast_confirmed(payment)
    Turbo::StreamsChannel.broadcast_replace_to(
      "payment_#{payment.id}",
      target:  "payment_status",
      partial: "payments/payments/paid",
      locals:  { payment: payment }
    )
  rescue => e
    log_error("broadcast failed: #{e.message}")
  end

  public

  # Confirma a partir do payload do webhook InfinitePay.
  # order_nsu = booking_group.id (passamos ao criar o checkout)
  def self.call_from_webhook(payload)
    order_nsu      = payload["order_nsu"]
    capture_method = payload["capture_method"]
    return unless order_nsu.present? && Payment::CAPTURE_METHODS.include?(capture_method)

    result = call(external_reference: order_nsu)

    # Registra o método (Pix/cartão) e o transaction_nsu retornado pelo webhook
    if result.success?
      group   = BookingGroup.find_by(id: order_nsu)
      updates = { capture_method: capture_method }
      updates[:gateway_id] = payload["transaction_nsu"] if payload["transaction_nsu"].present?
      group&.payment&.update_columns(**updates)
    end

    result
  end
end
