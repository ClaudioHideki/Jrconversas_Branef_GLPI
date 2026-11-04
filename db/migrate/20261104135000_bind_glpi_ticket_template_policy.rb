class BindGlpiTicketTemplatePolicy < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_glpi_commands, :template_version, :string
    add_column :jrc_service_desk_glpi_commands, :template_policy, :text
  end
end
