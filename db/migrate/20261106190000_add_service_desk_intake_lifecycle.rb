# A linear additive declaration; existing tickets and delivery receipts are retained.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class AddServiceDeskIntakeLifecycle < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_intake_notifications do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.references :intake_demand, null: false, foreign_key: { to_table: :jrc_service_desk_intake_demands }
      t.uuid :request_key, null: false
      t.uuid :generation, null: false
      t.string :kind, null: false
      t.string :channel, null: false
      t.string :template_code, null: false
      t.string :state, null: false, default: 'blocked'
      t.string :reason_code
      t.text :rendered_payload, null: false
      t.string :recipient_digest, null: false, limit: 64
      t.jsonb :source_snapshot, null: false, default: {}
      t.references :message, foreign_key: true
      t.string :payload_digest, limit: 64
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :jrc_service_desk_intake_notifications, [:account_id, :intake_demand_id, :kind, :request_key],
              unique: true, name: 'idx_intake_notice_request'
    add_index :jrc_service_desk_intake_notifications, :intake_demand_id, unique: true,
              where: "kind = 'survey'", name: 'idx_intake_single_survey'
    add_check_constraint :jrc_service_desk_intake_notifications, "kind IN ('pending_information','survey')", name: 'intake_notice_kind'
    add_check_constraint :jrc_service_desk_intake_notifications,
                         "state IN ('blocked','queued','sending','sent','delivered','read','failed','unknown')", name: 'intake_notice_state'

    add_column :jrc_service_desk_intake_demands, :lifecycle_state, :string, null: false, default: 'active'
    add_column :jrc_service_desk_intake_demands, :waiting_generation, :uuid
    add_reference :jrc_service_desk_intake_demands, :pending_notice, foreign_key: { to_table: :jrc_service_desk_intake_notifications }
    add_column :jrc_service_desk_intake_demands, :waiting_deadline, :datetime
    add_column :jrc_service_desk_intake_demands, :waiting_control, :jsonb, null: false, default: {}
    add_column :jrc_service_desk_intake_demands, :lifecycle_receipts, :jsonb, null: false, default: {}
    add_column :jrc_service_desk_intake_demands, :completion_cause, :string
    add_column :jrc_service_desk_intake_demands, :completed_at, :datetime
    add_column :jrc_service_desk_intake_demands, :lifecycle_error_code, :string
    add_check_constraint :jrc_service_desk_intake_demands,
                         "lifecycle_state IN ('active','awaiting_delivery','awaiting_information','closing','closed_no_response'," \
                         "'completed_human','cancelled','needs_attention')", name: 'intake_lifecycle_state'
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
