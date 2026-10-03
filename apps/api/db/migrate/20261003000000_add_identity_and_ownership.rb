class AddIdentityAndOwnership < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :login, :string, limit: 254
    add_column :users, :password_digest, :string
    add_column :users, :role, :string, default: "member", null: false
    add_index :users, "lower(login)", unique: true, where: "login IS NOT NULL", name: "index_users_on_lower_login"
    add_check_constraint :users, "role IN ('member', 'operator')", name: "users_valid_role"
    add_check_constraint :users, "(login IS NULL) = (password_digest IS NULL)", name: "users_credential_pair"

    add_reference :auctions, :seller, null: true, foreign_key: { to_table: :users }, index: true
    add_check_constraint :auctions, "seller_id IS NULL OR seller_id IS DISTINCT FROM current_leader_id", name: "auctions_seller_not_leader"
    add_check_constraint :auctions, "seller_id IS NULL OR seller_id IS DISTINCT FROM winner_id", name: "auctions_seller_not_winner"

    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, limit: 64, null: false
      t.datetime :expires_at, null: false
      t.timestamps
      t.index :token_digest, unique: true
      t.check_constraint "expires_at > created_at", name: "user_sessions_positive_lifetime"
    end
  end
end
