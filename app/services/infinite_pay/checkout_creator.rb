module InfinitePay
  class CheckoutCreator < ApplicationService
    BASE_URL = "https://api.checkout.infinitepay.io".freeze

    def initialize(booking_group:, amount_cents: nil)
      @group        = booking_group
      @amount_cents = amount_cents || booking_group.total_cents
    end

    def call
      expires_at = ENV.fetch("PAYMENT_EXPIRY_MINUTES", 30).to_i.minutes.from_now
      payload    = build_payload

      response = post_to_infinitepay(payload)
      body     = JSON.parse(response.body)

      if response.code.to_i.in?([ 200, 201 ])
        # NOTA: confirmar o campo exato com suporte InfinitePay se retornar nil
        # Candidatos documentados: "url", "checkout_url", "link", "payment_link"
        url = body["url"] || body["checkout_url"] || body["link"] || body["payment_link"]

        if url.present?
          success({ checkout_url: url, expires_at: expires_at })
        else
          Rails.logger.error("[InfinitePay::CheckoutCreator] campo URL ausente: #{body.inspect}")
          failure("Pagamento criado mas URL não foi retornada. Contate o suporte.")
        end
      else
        Rails.logger.error("[InfinitePay::CheckoutCreator] status=#{response.code} body=#{body.inspect}")
        failure("Serviço de pagamento indisponível. Tente novamente.")
      end
    rescue => e
      Rails.logger.error("[InfinitePay::CheckoutCreator] #{e.class}: #{e.message}")
      failure("Erro ao conectar ao serviço de pagamento.")
    end

    private

    def build_payload
      items = @group.bookings.includes(:availability).map do |b|
        {
          quantity:    1,
          price:       b.price_cents,
          description: "#{b.availability.label} — #{l(b.availability.date)}"
        }
      end

      Array(@group.extras).each do |extra|
        items << {
          quantity:    extra["quantity"].to_i,
          price:       extra["price_cents"].to_i,
          description: "Insumo: #{extra["name"]}"
        }
      end

      # A InfinitePay cobra a SOMA dos itens. Se há crédito/desconto aplicado
      # (valor a pagar < soma dos itens), consolida num único item com o valor
      # a pagar — senão o checkout cobraria o total cheio.
      items_sum = items.sum { |i| i[:price].to_i * i[:quantity].to_i }
      if @amount_cents != items_sum
        items = [ { quantity: 1, price: @amount_cents, description: "Reserva — Videira Clinic" } ]
      end

      payload = {
        handle:       ENV.fetch("INFINITEPAY_HANDLE"),
        items:        items,
        order_nsu:    @group.id,
        redirect_url: return_url,
        webhook_url:  webhook_url
      }

      # Dados do cliente são opcionais mas melhoram a experiência no checkout
      dentist = @group.dentist
      customer = { name: dentist.name, email: dentist.email }
      customer[:phone_number] = "+55#{dentist.phone.gsub(/\D/, '')}" if dentist.phone.present?
      payload[:customer] = customer

      payload
    end

    def return_url
      "#{app_base_url}/pagamento/retorno"
    end

    def webhook_url
      "#{app_base_url}/webhooks/infinitepay"
    end

    def app_base_url
      host     = ENV.fetch("APP_HOST", "localhost:3000")
      protocol = Rails.env.production? ? "https" : "http"
      "#{protocol}://#{host}"
    end

    def l(date)
      I18n.l(date, format: :default)
    end

    def post_to_infinitepay(payload)
      require "net/http"
      uri     = URI("#{BASE_URL}/links")
      http    = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = payload.to_json
      http.request(req)
    end
  end
end
