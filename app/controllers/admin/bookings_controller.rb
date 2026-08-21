class Admin::BookingsController < Admin::BaseController
  before_action :set_booking_group, only: [ :show, :cancel, :change_slot ]

  def index
    scope = policy_scope(BookingGroup)
      .includes(:dentist, :bookings, :payment)
      .order(created_at: :desc)

    if params[:status].present?
      scope = scope.where(status: params[:status])
    else
      # Por padrão a listagem mostra apenas reservas pagas/confirmadas.
      # Expiradas, pendentes e canceladas não aparecem como reserva.
      scope = scope.where(status: "confirmed")
    end

    # Três modos de visualização: dia (padrão), mês ou todos.
    @view = %w[day month all].include?(params[:view]) ? params[:view] : "day"

    case @view
    when "all"
      # Sem filtro de data — todas as reservas, mais recentes primeiro.
    when "month"
      @month = parse_month(params[:month]) || Date.current.beginning_of_month
      range  = @month.beginning_of_month..@month.end_of_month
      scope  = scope.joins(bookings: :availability)
                    .where(availabilities: { date: range })
    else # "day"
      @date = (Date.parse(params[:date]) rescue Date.current)
      scope = scope.joins(bookings: :availability)
                   .where(availabilities: { date: @date })
    end

    @pagy, @booking_groups = pagy(scope.distinct)

    # Meses que possuem reservas (para o select), do mais recente ao mais antigo.
    @available_months = current_clinic.availabilities
      .joins(:booking).distinct.pluck(:date)
      .map(&:beginning_of_month).uniq.sort.reverse
    @available_months = [ Date.current.beginning_of_month ] if @available_months.empty?

    # Turnos livres (e ainda não passados) para alteração manual de reserva
    @available_slots = current_clinic.availabilities.available
      .where("date >= ?", Date.current)
      .order(:date, :starts_at)
      .limit(60)
      .reject(&:past?)
  end

  def show
    @versions = @booking_group.versions + @booking_group.bookings.flat_map(&:versions)
    @versions.sort_by!(&:created_at).reverse!
  end

  def create
    availability = current_clinic.availabilities.find(params[:availability_id])
    dentist      = User.dentists.where(clinic: current_clinic).find(params[:dentist_id])

    result = AdminBookingCreator.call(availability: availability, dentist: dentist)

    if result.success?
      redirect_to admin_booking_path(result.value), notice: "Reserva criada com sucesso."
    else
      redirect_to admin_availabilities_path(date: availability.date), alert: result.error
    end
  end

  def change_slot
    booking = @booking_group.bookings.first
    new_av  = current_clinic.availabilities.available.find_by(id: params[:availability_id])

    result = AdminBookingSlotChanger.call(booking: booking, new_availability: new_av)

    if result.success?
      notice = if result.value[:charge_created]
        "Turno alterado. Cobrança da diferença gerada — o cliente deve pagar na reserva."
      else
        "Turno alterado com sucesso."
      end
      redirect_to admin_bookings_path(date: new_av.date), notice: notice
    else
      redirect_to admin_bookings_path, alert: result.error
    end
  end

  def cancel
    if @booking_group.cancelled?
      return redirect_to admin_booking_path(@booking_group), alert: "Reserva já cancelada."
    end

    @booking_group.cancel!
    # Reembolso como crédito (CreditIssuer só emite se o pagamento estava pago)
    CreditIssuer.call(booking_group: @booking_group, reason: "Cancelamento pelo administrador")

    redirect_to admin_booking_path(@booking_group), notice: "Reserva cancelada. Crédito gerado para o cliente, se aplicável."
  rescue => e
    redirect_to admin_booking_path(@booking_group), alert: "Erro ao cancelar: #{e.message}"
  end

  private

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end

  def set_booking_group
    @booking_group = policy_scope(BookingGroup).find(params[:id])
  end
end
