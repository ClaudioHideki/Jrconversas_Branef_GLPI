class CreateServiceDeskGlpiIntegration < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_glpi_connections do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :base_url, null: false
      t.text :user_token, null: false
      t.text :app_token, null: false
      t.boolean :enabled, default: false, null: false
      t.string :timezone, default: 'America/Sao_Paulo', null: false
      t.jsonb :entity_mappings, default: [], null: false
      t.jsonb :user_mappings, default: [], null: false
      t.jsonb :categories, default: [], null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    create_table :jrc_service_desk_glpi_commands do |t|
      t.references :account, null: false, foreign_key: true
      t.references :glpi_connection, null: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections }, index: false
      t.references :account_user, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: { to_table: :jrc_service_desk_units }
      t.bigint :entity_id, null: false
      t.string :idempotency_key, limit: 120, null: false
      t.string :fingerprint, limit: 64, null: false
      t.uuid :correlation_id, default: -> { 'gen_random_uuid()' }, null: false
      t.string :state, default: 'pending', null: false
      t.bigint :remote_id
      t.string :error_code
      t.timestamps
    end
    add_index :jrc_service_desk_glpi_commands, [:glpi_connection_id, :account_user_id, :idempotency_key],
              unique: true, name: 'idx_sd_glpi_command_idempotency'
    add_check_constraint :jrc_service_desk_glpi_commands, "state IN ('pending', 'sending', 'succeeded', 'rejected', 'indeterminate')",
                         name: 'sd_glpi_command_state'
  end
end
