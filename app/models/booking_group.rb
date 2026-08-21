class BookingGroup < ApplicationRecord
  has_paper_trail

  belongs_to :clinic
  belongs_to :dentist, class_name: "User"
  belongs_to :discount_rule, optional: true
  has_many   :bookings, dependent: :destroy
  has_many   :payments, dependent: :destroy
  # Pagamento principal (o mais antigo) — compatibilidade com o fluxo existente.
  has_one    :payment, -> { order(created_at: :asc) }

  validates :subtotal_cents, :total_cents, presence: true,
    numericality: { greater_than: 0 }
  validates :discount_cents, numericality: { greater_than_or_equal_to: 0 }

  enum :status, {
    pending:   "pending",
    confirmed: "confirmed",
    cancelled: "cancelled",
    expired:   "expired"
  }

  # Ao confirmar, cria os eventos na Google Agenda da owner (assíncrono).
  # Cobre os dois caminhos de confirmação:
  #  - Pix/cartão: grupo criado "pending" e confirmado depois (update, via webhook).
  #  - Crédito / reserva manual do admin: grupo já nasce/vira "confirmed" na
  #    mesma transação (o Rails trata como commit de criação).
  after_commit :sync_google_calendar_on_confirm, on: [ :create, :update ]

  # Valor total dos insumos (Videira Shop) deste pedido, em centavos.
  def extras_total_cents
    Array(extras).sum { |e| e["price_cents"].to_i * e["quantity"].to_i }
  end

  def expire!
    return unless pending?
    release_bookings!(final_status: "expired")
  end

  def cancel!
    return if cancelled?
    booking_ids = bookings.pluck(:id)
    release_bookings!(final_status: "cancelled")
    booking_ids.each { |id| GoogleCalendarSyncJob.perform_later("remove", id) }
  end

  private

  def sync_google_calendar_on_confirm
    return unless confirmed?
    # Dispara quando a reserva acaba de ser criada já confirmada (crédito/admin)
    # ou quando o status muda para confirmada (Pix/cartão). Evita re-sincronizar a cada
    # atualização de um grupo que já estava confirmado.
    return unless id_previously_changed? || saved_change_to_status?

    GoogleCalendarSyncJob.perform_later("create", id)
  end

  def release_bookings!(final_status:)
    was_pending = pending?
    transaction do
      update!(status: final_status)
      bookings.each do |b|
        b.update!(status: "cancelled")
        b.availability.update!(status: "available")
      end
      # Reserva não paga liberada: devolve o crédito que havia sido aplicado
      # (para reservas confirmadas, o reembolso é feito pelo CreditIssuer).
      refund_applied_credit! if was_pending
    end
  end

  # Crédito usado nesta reserva = total − o que faltava pagar por fora (Pix/cartão).
  def refund_applied_credit!
    external_due = payments.where.not(gateway: "credit").sum(:amount_cents)
    applied      = total_cents.to_i - external_due.to_i
    return if applied <= 0

    Credit.create!(
      user:         dentist,
      clinic:       clinic,
      amount_cents: applied,
      reason:       "Estorno de crédito (reserva não paga)"
    )
  end
end
