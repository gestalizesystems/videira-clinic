class Payments::PaymentsController < ApplicationController
  def show
    @payment = policy_scope(Payment)
      .includes(booking_group: [ :bookings, :dentist ])
      .find(params[:id])
    authorize @payment
  end

  # Página de espera — redireciona para o checkout InfinitePay se ainda pendente
  def pending
    @payment = policy_scope(Payment).find(params[:id])
    authorize @payment, :show?

    if @payment.pending? && @payment.checkout_url.present?
      redirect_to @payment.checkout_url, allow_other_host: true
    end
  end

  # Retorno após pagamento no InfinitePay
  # InfinitePay redireciona para /pagamento/retorno?order_nsu=...&transaction_nsu=...&slug=...
  def return
    group = BookingGroup.find_by(id: params[:order_nsu])
    return handle_non_booking_return if group.nil?

    @payment = group.payment
    authorize @payment, :show?

    # Se ainda pendente, consulta diretamente o InfinitePay como fallback (webhook pode demorar)
    if @payment.pending? && params[:transaction_nsu].present? && params[:slug].present?
      result = InfinitePay::PaymentChecker.call(
        order_nsu:       params[:order_nsu],
        transaction_nsu: params[:transaction_nsu],
        slug:            params[:slug]
      )

      if result.success? && result.value["paid"]
        PaymentConfirmer.call_from_webhook(
          "order_nsu"       => params[:order_nsu],
          "transaction_nsu" => params[:transaction_nsu],
          "capture_method"  => result.value["capture_method"],
          "paid_amount"     => result.value["paid_amount"]
        )
        @payment.reload
      end
    end
  end

  def cancel
    @payment = policy_scope(Payment).find(params[:id])
    authorize @payment, :show?

    group = @payment.booking_group
    return redirect_to pagamento_path(@payment), alert: "Pagamento já processado." unless group.pending?

    ActiveRecord::Base.transaction do
      @payment.update!(status: "cancelled")
      group.cancel!
    end

    redirect_to reservas_path, notice: "Reserva cancelada."
  rescue => e
    redirect_to pagamento_path(@payment), alert: "Não foi possível cancelar: #{e.message}"
  end

  private

  def handle_non_booking_return
    if (purchase = CreditPurchase.find_by(id: params[:order_nsu]))
      return handle_credit_return(purchase)
    end
    if (payment = Payment.find_by(id: params[:order_nsu]))
      return handle_difference_return(payment)
    end
    redirect_to root_path, alert: "Pagamento não encontrado."
  end

  # Retorno do InfinitePay para a diferença de uma alteração de reserva (order_nsu = payment.id)
  def handle_difference_return(payment)
    group = payment.booking_group
    unless group&.dentist_id == current_user.id
      return redirect_to root_path, alert: "Pagamento não encontrado."
    end

    if payment.pending? && params[:transaction_nsu].present? && params[:slug].present?
      result = InfinitePay::PaymentChecker.call(
        order_nsu:       params[:order_nsu],
        transaction_nsu: params[:transaction_nsu],
        slug:            params[:slug]
      )
      if result.success? && result.value["paid"]
        DifferencePaymentConfirmer.call_from_webhook(
          "order_nsu"       => params[:order_nsu],
          "transaction_nsu" => params[:transaction_nsu],
          "capture_method"  => result.value["capture_method"]
        )
        payment.reload
      end
    end

    if payment.paid?
      redirect_to reserva_path(group), notice: "Diferença paga! Reserva atualizada. 🎉"
    else
      redirect_to reserva_path(group), notice: "Pagamento em processamento. Atualizamos assim que confirmar."
    end
  end

  # Retorno do InfinitePay para uma recarga de crédito (order_nsu = credit_purchase.id)
  def handle_credit_return(purchase)
    unless purchase.user_id == current_user.id
      return redirect_to root_path, alert: "Pagamento não encontrado."
    end

    if purchase.pending? && params[:transaction_nsu].present? && params[:slug].present?
      result = InfinitePay::PaymentChecker.call(
        order_nsu:       params[:order_nsu],
        transaction_nsu: params[:transaction_nsu],
        slug:            params[:slug]
      )

      if result.success? && result.value["paid"]
        CreditPurchaseConfirmer.call_from_webhook(
          "order_nsu"       => params[:order_nsu],
          "transaction_nsu" => params[:transaction_nsu]
        )
        purchase.reload
      end
    end

    if purchase.paid?
      redirect_to carteira_path, notice: "Crédito adicionado com sucesso! 🎉"
    else
      redirect_to carteira_path, notice: "Pagamento em processamento. O crédito aparecerá assim que confirmado."
    end
  end
end
