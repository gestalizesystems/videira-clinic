class Scheduling::BookingsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Só reservas confirmadas (reais). Pendentes/expiradas/canceladas não são
    # mostradas — uma reserva que não foi paga nunca existiu de fato.
    base = policy_scope(BookingGroup).where(status: "confirmed").includes(bookings: :availability).includes(:payment)

    @months = base.pluck(:created_at).map { |d| d.strftime("%Y-%m") }.uniq.sort.reverse
    @selected_month = params[:month].presence || @months.first

    scope = base.order(created_at: :desc)

    if @selected_month.present?
      year, month = @selected_month.split("-").map(&:to_i)
      scope = scope.where(created_at: Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month)
    end

    @pagy, @booking_groups = pagy(scope)

    # Turnos livres (futuros) para o cliente trocar a reserva.
    @available_slots = Availability.available
      .where(clinic: current_user.clinic)
      .where("date >= ?", Date.current)
      .to_a
      .reject(&:past?)
      .sort_by { |a| [ a.date, a.starts_at.strftime("%H:%M") ] }
  end

  def show
    @booking_group = policy_scope(BookingGroup).find(params[:id])
    authorize @booking_group
  end

  def new
    cart_ids = Array(session[:cart_ids])

    if cart_ids.empty?
      return redirect_to root_path, alert: "Selecione ao menos um horário antes de continuar."
    end

    clinic = Availability.find_by(id: cart_ids.first)&.clinic

    result = DiscountCalculator.call(
      availability_ids: cart_ids,
      clinic:           clinic,
      dentist:          current_user
    )

    if result.failure?
      return redirect_to root_path, alert: result.error
    end

    @pricing  = result.value
    @extras       = Extra.from_session(session[:cart_extras])
    @extras_total = @extras.sum { |extra, qty| extra.price_cents * qty }
    @order_total_cents = @pricing[:total_cents] + @extras_total
    @dentists = User.dentists.where(clinic: clinic).order(:name) if current_user.owner?
  end

  def create
    cart_ids = Array(session[:cart_ids])

    if cart_ids.empty?
      return redirect_to root_path, alert: "Selecione ao menos um horário antes de continuar."
    end

    if current_user.owner? && params[:dentist_id].present?
      clinic  = Availability.find_by(id: cart_ids.first)&.clinic
      dentist = User.dentists.where(clinic: clinic).find_by(id: params[:dentist_id])

      unless dentist
        return redirect_to confirmar_reservas_path, alert: "Dentista não encontrado."
      end

      result = AdminBookingGroupCreator.call(
        availability_ids: cart_ids,
        dentist:          dentist
      )

      if result.success?
        session.delete(:cart_ids)
        redirect_to admin_booking_path(result.value),
          notice: "Reserva criada para #{dentist.name}."
      else
        redirect_to confirmar_reservas_path, alert: result.error
      end
    else
      credit_cents = if params[:use_credit].blank?
        0 # cliente desmarcou o uso de crédito
      elsif params[:credit_amount].present?
        (params[:credit_amount].to_s.tr(",", ".").to_f * 100).round
      else
        nil # usar todo o crédito disponível
      end

      result = BookingGroupCreator.call(
        user:             current_user,
        availability_ids: cart_ids,
        credit_cents:     credit_cents,
        extras:           session[:cart_extras]
      )

      if result.success?
        session.delete(:cart_ids)
        session.delete(:cart_extras)
        redirect_to pagamento_path(result.value.payment),
          notice: "Reserva criada! Conclua o pagamento."
      else
        redirect_to confirmar_reservas_path, alert: result.error
      end
    end
  end

  def change_slot
    booking = current_user.bookings.find(params[:id])
    group   = booking.booking_group

    unless group.confirmed? || group.pending?
      return redirect_to reservas_path, alert: "Esta reserva não pode ser alterada."
    end

    lead = ENV.fetch("CANCELLATION_LEAD_HOURS", 24).to_i
    unless booking.availability.cancellable?
      return redirect_to reservas_path, alert: "Alterações só são permitidas com #{lead}h de antecedência."
    end

    new_av = Availability.available
      .where(clinic: current_user.clinic)
      .find_by(id: params[:availability_id])

    result = AdminBookingSlotChanger.call(booking: booking, new_availability: new_av)

    if result.success?
      if result.value[:charge_created]
        payment = result.value[:group].payments.order(:created_at).last
        redirect_to pagamento_path(payment), notice: "Turno alterado! Conclua o pagamento da diferença."
      else
        redirect_to reservas_path, notice: "Turno alterado com sucesso."
      end
    else
      redirect_to reservas_path, alert: result.error
    end
  end

  def cancel
    booking = current_user.bookings.find(params[:id])
    authorize booking, :cancel?

    result = BookingCanceller.call(booking: booking)

    if result.success?
      redirect_to reservas_path, notice: "Reserva cancelada com sucesso."
    else
      redirect_to reserva_path(booking.booking_group), alert: result.error
    end
  end
end
