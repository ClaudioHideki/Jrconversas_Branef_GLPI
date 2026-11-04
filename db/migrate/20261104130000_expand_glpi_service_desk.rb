# frozen_string_literal: true

class ExpandGlpiServiceDesk < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_glpi_connections, :primary_source, :boolean, default: false, null: false
    create_table :jrc_service_desk_glpi_sync_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :glpi_connection, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections }
      t.references :account_user, null: false, foreign_key: true
      t.integer :connection_version, null: false
      t.string :state, default: 'running', null: false
      t.jsonb :coverage, default: {}, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :jrc_service_desk_glpi_sync_runs, [:glpi_connection_id, :created_at], name: 'idx_sd_glpi_sync_history'
    add_index :jrc_service_desk_glpi_sync_runs, :glpi_connection_id, unique: true,
              where: "state = 'running'", name: 'idx_sd_glpi_sync_running'
    add_check_constraint :jrc_service_desk_glpi_sync_runs, "state IN ('running', 'complete', 'partial', 'failed')",
                         name: 'sd_glpi_sync_state'
    create_table :jrc_service_desk_glpi_ticket_snapshots do |t|
      t.references :account, null: false, foreign_key: true
      t.references :glpi_connection, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections }
      t.references :unit, null: false, foreign_key: { to_table: :jrc_service_desk_units }
      t.references :glpi_sync_run, foreign_key: { to_table: :jrc_service_desk_glpi_sync_runs }, index: false
      t.bigint :remote_id, null: false
      t.bigint :entity_id, null: false
      t.integer :connection_version, null: false
      t.jsonb :payload, default: {}, null: false
      t.boolean :active, default: true, null: false
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :jrc_service_desk_glpi_ticket_snapshots, [:glpi_connection_id, :remote_id], unique: true, name: 'idx_sd_glpi_ticket_remote'
    add_index :jrc_service_desk_glpi_ticket_snapshots, [:account_id, :glpi_connection_id, :entity_id], name: 'idx_sd_glpi_ticket_scope'
  end
end
