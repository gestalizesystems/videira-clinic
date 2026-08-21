require "rails_helper"

RSpec.describe "Booking flow", type: :system do
  let!(:clinic)  { create(:clinic) }
  let!(:dentist) { create(:user, :dentist, clinic: clinic) }
  let!(:av) do
    create(:availability,
      clinic: clinic,
      dentist: dentist,
      date: Date.tomorrow,
      starts_at: "08:00",
      ends_at: "12:00",
      price_cents: 17_000)
  end

  it "shows the home page with availabilities" do
    visit root_path(date: Date.tomorrow.to_s)
    expect(page).to have_content(av.label)
    expect(page).to have_content("R$ 170,00")
  end

  it "adds an availability to the cart" do
    visit root_path(date: Date.tomorrow.to_s)
    click_button "R$ 170,00", match: :first
    expect(page).to have_content("Toque para remover")
  end

  context "as a signed in dentist" do
    before { sign_in dentist }

    it "completes a reservation and shows InfinitePay checkout button" do
      allow(InfinitePay::CheckoutCreator).to receive(:call).and_return(
        ApplicationService::Result.new(
          success: true,
          value: { checkout_url: "https://checkout.infinitepay.io/test", expires_at: 30.minutes.from_now },
          error: nil
        )
      )

      visit root_path(date: Date.tomorrow.to_s)
      click_button "R$ 170,00", match: :first

      click_link "Adicionar ao carrinho", match: :first
      expect(page).to have_content("Meu Carrinho")

      click_link "FINALIZAR PEDIDO"
      expect(page).to have_content("Confirmar reserva")

      click_button "Pagar"
      expect(page).to have_content("Pagamento da Reserva")
      expect(page).to have_content("Pagar no InfinitePay")
    end
  end
end
