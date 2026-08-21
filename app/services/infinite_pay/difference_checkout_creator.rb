module InfinitePay
  # Cria um checkout (Pix ou cartão) para a DIFERENÇA de valor ao alterar uma reserva.
  # order_nsu = id do Payment de diferença (passado explicitamente).
  class DifferenceCheckoutCreator < ApplicationService
    BASE_URL = "https://api.checkout.infinitepay.io".freeze

    def initialize(booking_group:, amount_cents:, order_nsu:, description: "Diferença de alteração de reserva", items: nil)
      @group        = booking_group
      @amount_cents = amount_cents
      @order_nsu    = order_nsu
      @description  = description
      @items        = items
    end

    def call
      expires_at = ENV.fetch("PAYMENT_EXPIRY_MINUTES", 30).to_i.minutes.from_now

      response = post_to_infinitepay(build_payload)
      body     = JSON.parse(response.body)

      if response.code.to_i.in?([ 200, 201 ])
        url = body["url"] || body["checkout_url"] || body["link"] || body["payment_link"]
        if url.present?
          success({ checkout_url: url, expires_at: expires_at })
        else
          Rails.logger.error("[InfinitePay::DifferenceCheckoutCreator] URL ausente: #{body.inspect}")
          failure("Pagamento criado mas URL não foi retornada. Contate o suporte.")
        end
      else
        Rails.logger.error("[InfinitePay::DifferenceCheckoutCreator] status=#{response.code} body=#{body.inspect}")
        failure("Serviço de pagamento indisponível. Tente novamente.")
      end
    rescue => e
      Rails.logger.error("[InfinitePay::DifferenceCheckoutCreator] #{e.class}: #{e.message}")
      failure("Erro ao conectar ao serviço de pagamento.")
    end

    private

    def build_payload
      user = @group.dentist
      payload = {
        handle:       ENV.fetch("INFINITEPAY_HANDLE"),
        items:        @items.presence || [ { quantity: 1, price: @amount_cents, description: @description } ],
        order_nsu:    @order_nsu,
        redirect_url: "#{app_base_url}/pagamento/retorno",
        webhook_url:  "#{app_base_url}/webhooks/infinitepay"
      }
      customer = { name: user.name, email: user.email }
      customer[:phone_number] = "+55#{user.phone.gsub(/\D/, '')}" if user.phone.present?
      payload[:customer] = customer
      payload
    end

    def app_base_url
      host     = ENV.fetch("APP_HOST", "localhost:3000")
      protocol = Rails.env.production? ? "https" : "http"
      "#{protocol}://#{host}"
    end

    def post_to_infinitepay(payload)
      require "net/http"
      uri  = URI("#{BASE_URL}/links")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = payload.to_json
      http.request(req)
    end
  end
end
