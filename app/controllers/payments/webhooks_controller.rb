class Payments::WebhooksController < ActionController::Base
  protect_from_forgery with: :null_session

  def infinitepay
    payload = JSON.parse(request.body.read)

    # InfinitePay não documenta assinatura HMAC — validamos pelo order_nsu existir no banco.
    # NOTA: confirmar com suporte InfinitePay se há header de assinatura a validar.
    order_nsu     = payload["order_nsu"].to_s
    is_booking    = BookingGroup.exists?(id: order_nsu)
    is_credit     = CreditPurchase.exists?(id: order_nsu)
    is_difference = Payment.exists?(id: order_nsu)

    unless is_booking || is_credit || is_difference
      Rails.logger.warn("[Webhook InfinitePay] order_nsu desconhecido: #{order_nsu}")
      return head :ok
    end

    # Processa Pix e cartão de crédito aprovados — o checkout InfinitePay
    # oferece os dois métodos ao pagador, e ambos recebem o mesmo tratamento.
    if Payment::CAPTURE_METHODS.include?(payload["capture_method"]) && payload["paid_amount"].to_i > 0
      if is_booking
        PaymentConfirmer.call_from_webhook(payload)
      elsif is_credit
        CreditPurchaseConfirmer.call_from_webhook(payload)
      else
        DifferencePaymentConfirmer.call_from_webhook(payload)
      end
    end

    head :ok
  rescue JSON::ParserError
    Rails.logger.error("[Webhook InfinitePay] JSON inválido")
    head :bad_request
  rescue => e
    Rails.logger.error("[Webhook InfinitePay] #{e.class}: #{e.message}")
    head :ok  # sempre 200 para InfinitePay não criar loop de retentativas
  end
end
