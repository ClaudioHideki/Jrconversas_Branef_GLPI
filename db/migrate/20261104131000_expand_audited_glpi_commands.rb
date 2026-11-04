class ExpandAuditedGlpiCommands < ActiveRecord::Migration[7.1]
  def change
    change_table :jrc_service_desk_glpi_commands, bulk: true do |t|
      t.string :operation, default: 'ticket.create', null: false
      t.string :itemtype, default: 'Ticket', null: false
      t.bigint :target_id
      t.bigint :parent_id
      t.string :parent_type
      t.bigint :technical_user_id
      t.integer :connection_version
      t.string :expected_version
      t.text :reason
      t.text :request_payload
      t.text :before_values
      t.jsonb :result, default: {}, null: false
    end
    add_index :jrc_service_desk_glpi_commands, [:glpi_connection_id, :itemtype, :target_id, :state], name: 'idx_sd_glpi_command_target'
  end
end
