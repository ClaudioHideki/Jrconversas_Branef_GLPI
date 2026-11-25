# frozen_string_literal: true

class CreateGlpiSentimentBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_glpi_sentiment_batches do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :glpi_connection, null: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections, on_delete: :cascade },
                  index: { unique: true, where: "state IN ('queued', 'running', 'cancelling')", name: 'idx_glpi_sentiment_active_batch' }
      t.integer :connection_version, null: false
      t.string :state, null: false, default: 'queued'
      t.jsonb :filters, null: false, default: {}
      t.jsonb :entity_ids, null: false, default: []
      t.jsonb :coverage, null: false, default: {}
      t.integer :total, null: false
      t.string :error
      t.timestamps
    end

    create_table :jrc_service_desk_glpi_sentiment_items do |t|
      t.references :batch, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_sentiment_batches, on_delete: :cascade }
      t.bigint :remote_id, null: false
      t.bigint :entity_id, null: false
      t.string :state, null: false, default: 'queued'
      t.jsonb :result
      t.string :error
      t.timestamps
      t.index %i[batch_id remote_id], unique: true, name: 'idx_glpi_sentiment_ticket'
      t.index %i[batch_id state id], name: 'idx_glpi_sentiment_work'
    end
  end
end
