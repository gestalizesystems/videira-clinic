class AddCaptureMethodToPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :payments, :capture_method, :string
  end
end
