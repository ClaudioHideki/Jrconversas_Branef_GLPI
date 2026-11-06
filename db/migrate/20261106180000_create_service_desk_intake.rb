# The migration is a linear declaration of two tables and their constraints.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class CreateServiceDeskIntake < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_intake_configurations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :created_by_account_user, null: false, foreign_key: { to_table: :account_users }
      t.integer :revision, null: false
      t.jsonb :catalogue, null: false
      t.jsonb :responses, null: false, default: []
      t.jsonb :mappings, null: false, default: {}
      t.string :mode, null: false, default: 'on_handoff'
      t.boolean :enabled, null: false, default: false
      t.boolean :current, null: false, default: false
      t.boolean :remote_writes_enabled, null: false, default: false
      t.timestamps
    end
    add_index :jrc_service_desk_intake_configurations, [:account_id, :inbox_id, :revision],
              unique: true, name: 'idx_intake_configuration_revision'
    add_index :jrc_service_desk_intake_configurations, :inbox_id, unique: true,
                                                                  where: 'current = true', name: 'idx_current_intake_configuration'
    add_check_constraint :jrc_service_desk_intake_configurations, 'revision > 0', name: 'intake_positive_revision'
    add_check_constraint :jrc_service_desk_intake_configurations,
                         "mode IN ('on_handoff','on_qualification')", name: 'intake_creation_mode'

    create_table :jrc_service_desk_intake_demands do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.references :intake_configuration, null: false, foreign_key: { to_table: :jrc_service_desk_intake_configurations }
      t.uuid :episode_key, null: false
      t.string :fingerprint, null: false, limit: 64
      t.text :normalized_input, null: false
      t.jsonb :source_context, null: false, default: {}
      t.jsonb :delivery_receipts, null: false, default: {}
      t.string :state, null: false, default: 'qualified'
      t.bigint :remote_id
      t.string :error_code
      t.timestamps
    end
    add_index :jrc_service_desk_intake_demands, [:account_id, :episode_key], unique: true, name: 'idx_intake_episode_identity'
    add_index :jrc_service_desk_intake_demands, [:account_id, :conversation_id, :created_at], name: 'idx_intake_conversation_history'
    add_check_constraint :jrc_service_desk_intake_demands,
                         "state IN ('qualified','queued','sending','confirmed','partial','rejected','indeterminate','test_only')",
                         name: 'intake_demand_state'
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
