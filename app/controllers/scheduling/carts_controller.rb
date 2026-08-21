class Scheduling::CartsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @cart_availabilities = cart_availabilities
    @linkable_groups     = linkable_groups
  end

  def add
    av = Availability.available.find_by(id: params[:availability_id])

    if av.nil?
      return redirect_back(fallback_location: root_path, alert: "Horário indisponível.")
    end

    cart_ids << av.id unless cart_ids.include?(av.id)
    session[:cart_ids] = cart_ids

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back(fallback_location: root_path) }
    end
  end

  def remove
    cart_ids.delete(params[:availability_id])
    session[:cart_ids] = cart_ids

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back(fallback_location: carrinho_path) }
    end
  end

  def add_extra
    extra = Extra.active.find_by(id: params[:extra_key])
    if extra
      extras = cart_extras
      extras[extra.id] = extras[extra.id].to_i + 1
      session[:cart_extras] = extras
    end

    @cart_availabilities = cart_availabilities
    respond_to do |format|
      format.turbo_stream { render :extras_update }
      format.html do
        flash[:notice] = "#{extra.name} adicionado ao carrinho." if extra
        redirect_back(fallback_location: carrinho_path)
      end
    end
  end

  def remove_extra
    extras = cart_extras
    key = params[:extra_key].to_s
    if extras[key]
      extras[key] = extras[key].to_i - 1
      extras.delete(key) if extras[key] <= 0
      session[:cart_extras] = extras
    end

    @cart_availabilities = cart_availabilities
    respond_to do |format|
      format.turbo_stream { render :extras_update }
      format.html { redirect_back(fallback_location: carrinho_path) }
    end
  end

  # Compra de insumos avulsa: vincula a uma reserva confirmada existente e gera
  # um pagamento (Pix ou cartão) só dos insumos.
  def purchase_extras
    return redirect_to(new_user_session_path, alert: "Faça login para comprar insumos.") unless user_signed_in?

    extras = Extra.from_session(session[:cart_extras])
    return redirect_to(carrinho_path, alert: "Selecione ao menos um insumo.") if extras.empty?

    group = BookingGroup.where(dentist: current_user, status: "confirmed").find_by(id: params[:booking_group_id])
    unless group && future_group?(group)
      return redirect_to carrinho_path, alert: "Selecione uma reserva válida (com turno futuro)."
    end

    result = ExtrasPurchaseCreator.call(booking_group: group, extras: extras)
    if result.success?
      session.delete(:cart_extras)
      redirect_to pagamento_path(result.value), notice: "Insumos vinculados! Conclua o pagamento."
    else
      redirect_to carrinho_path, alert: result.error
    end
  end

  def destroy
    session.delete(:cart_ids)
    session.delete(:cart_extras)
    redirect_back(fallback_location: root_path)
  end

  private

  # Reservas confirmadas do cliente que têm ao menos um turno futuro (para
  # vincular insumos comprados sem turno no carrinho).
  def linkable_groups
    return [] unless user_signed_in?
    BookingGroup.where(dentist: current_user, status: "confirmed")
      .includes(bookings: :availability)
      .order(created_at: :desc)
      .select { |g| future_group?(g) }
  end

  def future_group?(group)
    group.bookings.any? { |b| b.availability && b.availability.date >= Date.current && !b.availability.past? }
  end

  def cart_ids
    @cart_ids ||= Array(session[:cart_ids])
  end

  def cart_extras
    @cart_extras ||= (session[:cart_extras] || {}).to_h
  end

  def cart_availabilities
    return [] if cart_ids.empty?
    Availability.where(id: cart_ids).includes(:service, :dentist)
      .to_a
      .sort_by { |a| [ a.date, a.starts_at.strftime("%H:%M") ] }
  end
end
