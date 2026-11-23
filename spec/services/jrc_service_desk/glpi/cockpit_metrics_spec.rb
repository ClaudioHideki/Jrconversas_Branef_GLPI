require 'rails_helper'

RSpec.describe JrcServiceDesk::Glpi::CockpitMetrics do
  subject(:metrics) { described_class.call(account: account, user: user, account_user: membership, period: '7_days') }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:membership) { account.account_users.find_by!(user: user) }
  let(:unit) { create(:jrc_sd_unit, account: account, operator_company: create(:jrc_sd_operator_company, account: account)) }
  let(:connection) do
    JrcServiceDesk::GlpiConnection.create!(
      account: account, base_url: 'https://glpi.example.invalid/apirest.php',
      user_token: 'synthetic-user', app_token: 'synthetic-app', enabled: true, primary_source: true, timezone: 'America/Sao_Paulo',
      entity_mappings: [{ entity_id: 0, unit_id: unit.id }], user_mappings: [{ account_user_id: membership.id, glpi_user_id: 77 }]
    )
  end
  let(:run) do
    JrcServiceDesk::GlpiSyncRun.create!(account: account, glpi_connection: connection, account_user: membership,
                                        connection_version: connection.lock_version, state: 'complete', finished_at: Time.utc(2026, 11, 13, 14),
                                        coverage: { '0' => { 'state' => 'complete', 'indexed' => 3, 'observed' => 3 } })
  end

  before do
    account.enable_features!('jrc_service_desk')
    travel_to Time.utc(2026, 11, 13, 15)
  end

  it 'does not attach source metrics to an account using the native source' do
    expect(metrics).to be_nil
  end

  context 'with a GLPI projection' do
    before do
      [[11, '2026-11-13 09:00:00', '1', [77]], [12, '2026-11-12 09:00:00', '5', [88]],
       [13, '2026-11-01 09:00:00', '4', [77]]].each do |id, opened, status, actors|
        JrcServiceDesk::GlpiTicketSnapshot.create!(
          account: account, glpi_connection: connection, glpi_sync_run: run, unit: unit, remote_id: id, entity_id: 0,
          connection_version: connection.lock_version, active: true, observed_at: run.finished_at,
          payload: { title: 'Fixture', status: status, priority: '3', opened_at: opened, actor_scope_available: true,
                     actor_user_ids: actors, assigned_user_ids: actors, solution_deadline: '2026-11-14 10:00:00', solution_exceeded: id == 11 }
        )
      end
    end

    it 'uses the filtered authorized projection without a remote client or synchronization' do
      expect(JrcServiceDesk::Glpi::Client).not_to receive(:new)
      expect(metrics).to include(source: 'GLPI', state: 'complete', total: 2, active: 1, exceeded: 1,
                                 filters: { 'from' => '2026-11-07', 'to' => '2026-11-13' }, route_name: 'jrc_service_desk_glpi')
    end

    it 'counts only tickets involving a restricted operator' do
      membership.update!(role: :agent)
      create(:jrc_sd_membership, account: account, account_user: membership, unit: unit)
      expect(metrics).to include(total: 1, active: 1)
    end

    it 'does not turn a missing identity into zero tickets' do
      membership.update!(role: :agent)
      create(:jrc_sd_membership, account: account, account_user: membership, unit: unit)
      connection.update!(user_mappings: [])
      expect(metrics).to include(state: 'forbidden', total: nil)
    end

    it 'marks partial coverage without declaring it complete' do
      run.update!(state: 'partial', coverage: { '0' => { 'state' => 'partial', 'indexed' => 3 } })
      expect(metrics).to include(state: 'partial', total: 2)
    end

    it 'represents a complete empty result as zero' do
      run.update!(state: 'complete', coverage: { '0' => { 'state' => 'complete', 'indexed' => 0 } })
      JrcServiceDesk::GlpiTicketSnapshot.where(glpi_connection: connection).delete_all
      expect(metrics).to include(state: 'complete', total: 0)
    end

    it 'represents a missing projection as unavailable without numeric totals' do
      JrcServiceDesk::GlpiTicketSnapshot.where(glpi_connection: connection).delete_all
      run.destroy!
      expect(metrics).to include(state: 'unavailable', total: nil, active: nil, exceeded: nil)
    end

    it 'does not leak an aggregate when the module is disabled after configuration' do
      account.disable_features!('jrc_service_desk')
      expect(metrics).to be_nil
    end
  end
end
