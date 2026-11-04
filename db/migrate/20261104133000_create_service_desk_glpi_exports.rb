# frozen_string_literal: true

class CreateServiceDeskGlpiExports < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_glpi_exports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :glpi_connection, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections }
      t.references :account_user, null: false, foreign_key: true
      t.integer :connection_version, null: false
      t.string :state, null: false, default: 'queued'
      t.jsonb :filters, null: false, default: {}
      t.jsonb :scope, null: false, default: {}
      t.jsonb :coverage, null: false, default: {}
      t.jsonb :manifest, null: false, default: []
      t.jsonb :source_identity, null: false, default: {}
      t.bigint :processed, null: false, default: 0
      t.bigint :total
      t.string :error_code
      t.integer :error_http_status
      t.datetime :finished_at
      t.datetime :expires_at
      t.datetime :verified_from
      t.datetime :verified_until
      t.datetime :verification_expires_at
      t.timestamps
    end
    add_index :jrc_service_desk_glpi_exports, [:glpi_connection_id, :account_user_id, :created_at], name: 'idx_sd_glpi_export_receipts'
    add_index :jrc_service_desk_glpi_exports, :expires_at
    add_check_constraint :jrc_service_desk_glpi_exports,
      "state IN ('queued', 'running', 'ready', 'verifying', 'failed', 'cancelled', 'expired')", name: 'sd_glpi_export_state'
    add_check_constraint :jrc_service_desk_glpi_exports, 'processed >= 0 AND (total IS NULL OR total >= 0)', name: 'sd_glpi_export_progress'
  end
end
