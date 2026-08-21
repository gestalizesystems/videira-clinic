require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:clinic)   { create(:clinic) }
  let(:patient)  { create(:user, :dentist, clinic: clinic) }
  let(:group)    { create(:booking_group, clinic: clinic, dentist: patient) }
  let!(:payment) { create(:payment, clinic: clinic, booking_group: group) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(BookingMailer).to receive_message_chain(:confirmation, :deliver_later)
  end

  let(:payload) do
    {
      order_nsu:       group.id,
      transaction_nsu: "txn-abc123",
      invoice_slug:    "slug-abc",
      amount:          payment.amount_cents,
      paid_amount:     payment.amount_cents,
      capture_method:  "pix",
      installments:    1
    }.to_json
  end

  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  describe "POST /webhooks/infinitepay" do
    it "returns 200 OK" do
      post infinitepay_webhook_path, params: payload, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "confirms the booking group" do
      post infinitepay_webhook_path, params: payload, headers: headers
      expect(group.reload.status).to eq("confirmed")
    end

    it "ignores unknown order_nsu" do
      bad_payload = { order_nsu: SecureRandom.uuid, capture_method: "pix", paid_amount: 1000 }.to_json
      post infinitepay_webhook_path, params: bad_payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(group.reload.status).to eq("pending")
    end

    it "confirms credit card payments the same as pix" do
      card_payload = { order_nsu: group.id, capture_method: "credit_card", paid_amount: payment.amount_cents }.to_json
      post infinitepay_webhook_path, params: card_payload, headers: headers
      expect(group.reload.status).to eq("confirmed")
      expect(payment.reload.capture_method).to eq("credit_card")
    end

    it "records the capture method on the payment" do
      post infinitepay_webhook_path, params: payload, headers: headers
      expect(payment.reload.capture_method).to eq("pix")
    end

    it "ignores unrecognized capture methods" do
      bad_payload = { order_nsu: group.id, capture_method: "boleto", paid_amount: payment.amount_cents }.to_json
      post infinitepay_webhook_path, params: bad_payload, headers: headers
      expect(group.reload.status).to eq("pending")
    end
  end
end
