class AdminBookingSlotChanger < ApplicationService
  def initialize(booking:, new_availability:)
    @booking = booking
    @new_av  = new_availability
  end

  def call
    return failure("Selecione um turno.")   unless @booking && @new_av
    return failure("Turno indisponível.")   unless @new_av.available?
    return failure("Este turno já passou.") if     @new_av.past?

    old_av = @booking.availability
    return failure("Selecione um turno diferente do atual.") if old_av&.id == @new_av.id

    group = @booking.booking_group
    diff  = @new_av.price_cents - @booking.price_cents # > 0 mais caro, < 0 mais barato

    credit_to_consume = 0
    difference_attrs  = nil

    if diff.positive?
      # Usa crédito disponível e cobra o restante via checkout (Pix ou cartão).
      available         = Credit.balance_for(user: group.dentist, clinic: group.clinic)
      credit_to_consume = [ diff, available ].min
      remaining         = diff - credit_to_consume

      if remaining.positive?
        nsu      = SecureRandom.uuid
        checkout = InfinitePay::DifferenceCheckoutCreator.call(
          booking_group: group, amount_cents: remaining, order_nsu: nsu
        )
        return failure(checkout.error) unless checkout.success?

        difference_attrs = {
          id:           nsu,
          clinic:       group.clinic,
          gateway:      "infinitepay",
          status:       "pending",
          amount_cents: remaining,
          checkout_url: checkout.value[:checkout_url],
          expires_at:   checkout.value[:expires_at]
        }
      end
    end

    ActiveRecord::Base.transaction do
      @new_av.update!(status: "booked")
      old_av&.update!(status: "available")
      @booking.update!(availability: @new_av, price_cents: @new_av.price_cents)

      consume_credit(group, credit_to_consume) if credit_to_consume.positive?

      if diff.negative?
        Credit.create!(
          user:                 group.dentist,
          clinic:               group.clinic,
          source_booking_group: group,
          amount_cents:         -diff,
          reason:               "Diferença de alteração de reserva"
        )
      end

      group.payments.create!(**difference_attrs) if difference_attrs

      extras_total   = Array(group.extras).sum { |e| e["price_cents"].to_i * e["quantity"].to_i }
      bookings_total = group.bookings.sum(:price_cents)
      total          = bookings_total + extras_total
      group.update!(subtotal_cents: total, total_cents: total - group.discount_cents.to_i)
    end

    GoogleCalendarSyncJob.perform_later("update_slot", @booking.id)
    BookingMailer.admin_slot_change_notification(@booking, old_av).deliver_later
    success({ group: group, charge_created: difference_attrs.present? })
  rescue ActiveRecord::RecordInvalid => e
    log_error(e.message)
    failure("Erro ao alterar turno.")
  end

  private

  # Consome crédito do cliente até cobrir `amount`. Crédito parcial vira "troco".
  def consume_credit(group, amount)
    remaining = amount
    Credit.available
      .where(user: group.dentist, clinic: group.clinic)
      .lock("FOR UPDATE")
      .order(:created_at)
      .each do |credit|
        break if remaining <= 0
        credit.update!(used_at: Time.current, used_on_booking_group: group)
        if credit.amount_cents > remaining
          Credit.create!(
            user:         group.dentist,
            clinic:       group.clinic,
            amount_cents: credit.amount_cents - remaining,
            reason:       "Troco de crédito"
          )
          remaining = 0
        else
          remaining -= credit.amount_cents
        end
      end
  end
end
