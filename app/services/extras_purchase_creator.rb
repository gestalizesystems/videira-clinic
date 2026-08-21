# Compra de insumos (Videira Shop) vinculada a uma reserva confirmada já
# existente. Cria um pagamento avulso (Pix ou cartão); os insumos só são anexados à reserva
# quando o pagamento é confirmado (guardados no próprio pagamento até lá).
class ExtrasPurchaseCreator < ApplicationService
  def initialize(booking_group:, extras:)
    @group  = booking_group
    @extras = extras # [[Extra, qty], ...]
    @total  = @extras.sum { |extra, qty| extra.price_cents * qty }
  end

  def call
    return failure("Selecione ao menos um insumo.") if @extras.empty? || @total <= 0
    return failure("Reserva inválida.")              unless @group

    nsu = SecureRandom.uuid
    checkout = InfinitePay::DifferenceCheckoutCreator.call(
      booking_group: @group, amount_cents: @total, order_nsu: nsu,
      description: item_names, items: checkout_items
    )
    return failure(checkout.error) unless checkout.success?

    payment = @group.payments.create!(
      id:           nsu,
      clinic:       @group.clinic,
      gateway:      "infinitepay",
      status:       "pending",
      amount_cents: @total,
      extras:       serialized_extras,
      checkout_url: checkout.value[:checkout_url],
      expires_at:   checkout.value[:expires_at]
    )

    success(payment)
  rescue ActiveRecord::RecordInvalid => e
    failure(e.message)
  end

  private

  # Item por insumo, para a InfinitePay mostrar nome e quantidade reais no
  # pedido (em vez de um item genérico "Insumos — Videira Clinic").
  def checkout_items
    @extras.map do |extra, qty|
      { quantity: qty, price: extra.price_cents, description: "Insumo: #{extra.name}" }
    end
  end

  def item_names
    @extras.map { |extra, qty| "#{extra.name} x#{qty}" }.join(", ")
  end

  def serialized_extras
    @extras.map do |extra, qty|
      { "id" => extra.id, "name" => extra.name, "price_cents" => extra.price_cents, "quantity" => qty }
    end
  end
end
