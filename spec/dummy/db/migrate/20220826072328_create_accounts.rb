class CreateAccounts < ActiveRecord::Migration[7.0]
  def change
    create_table :accounts do |t|
      t.string :name, index: {unique: true}, null: false
      t.timestamps
    end
  end
end
