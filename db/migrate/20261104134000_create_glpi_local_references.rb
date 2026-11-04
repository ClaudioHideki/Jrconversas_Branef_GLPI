class CreateGlpiLocalReferences < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_glpi_references do |t|
      t.references :account, null: false, foreign_key: true
      t.references :glpi_connection, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_connections }
      t.references :unit, null: false, foreign_key: { to_table: :jrc_service_desk_units }
      t.string :itemtype, null: false
      t.bigint :remote_id, null: false
      t.bigint :entity_id, null: false
      t.timestamps
    end
    add_index :jrc_service_desk_glpi_references, [:glpi_connection_id, :itemtype, :remote_id, :entity_id], unique: true,
      name: 'idx_sd_glpi_reference_identity'
    create_table :jrc_service_desk_glpi_reference_links do |t|
      t.references :account, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: { to_table: :jrc_service_desk_units }
      t.references :glpi_reference, null: false, index: false, foreign_key: { to_table: :jrc_service_desk_glpi_references }
      # Immutable audit identity survives native conversation/inbox deletion.
      # Live target ownership is proved/locked by LinkLocalReference, and readers
      # require the live authorized target before exposing any retained reference.
      t.references :conversation
      t.references :incident, foreign_key: { to_table: :jrc_service_desk_incidents }
      t.references :account_user, null: false, foreign_key: true
      t.timestamps
    end
    add_check_constraint :jrc_service_desk_glpi_reference_links,
      '(conversation_id IS NULL) <> (incident_id IS NULL)', name: 'sd_glpi_link_one_local_target'
    add_index :jrc_service_desk_glpi_reference_links, [:glpi_reference_id, :conversation_id],
      unique: true, where: 'conversation_id IS NOT NULL', name: 'idx_sd_glpi_conversation_link'
    add_index :jrc_service_desk_glpi_reference_links, [:glpi_reference_id, :incident_id],
      unique: true, where: 'incident_id IS NOT NULL', name: 'idx_sd_glpi_case_link'
  end
end
