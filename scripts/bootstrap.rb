definitions = RedminePortfolio::Definitions

# Serialise first-time initialisation across application starts and manual runners.
User.transaction do
  User.lock.find(User.anonymous.id)
  Setting.check_cache
  admin = User.lock.find_by(login: 'admin', admin: true)

  if admin&.check_password?('admin')
    password = ENV.fetch('PORTFOLIO_ADMIN_PASSWORD')
    abort 'Generate a strong administrator password with scripts/setup-secrets' unless password.match?(/\A[0-9a-f]{64}\z/)

    admin.password = admin.password_confirmation = password
    admin.language = 'de'
    admin.must_change_passwd = false
    admin.save!
  end

  Redmine::DefaultData::Loader.load('de') if Redmine::DefaultData::Loader.no_data?
  {
    default_language: 'de', ui_theme: 'shadcn', login_required: '1',
    self_registration: '0', default_projects_public: '0', rest_api_enabled: '0',
    webhooks_enabled: '0', notified_events: []
  }.each do |name, value|
    Setting[name.to_s] = value unless Setting.exists?(name: name.to_s)
  end

  unless Setting.plugin_redmine_portfolio['demo_seeded']
    fields = definitions::FIELDS.transform_values do |name, format, values|
      abort "Projektfeld existiert bereits: #{name}" if ProjectCustomField.exists?(name: name)

      attributes = {name: name, field_format: format, visible: true, multiple: false}
      attributes[:possible_values] = values if values
      ProjectCustomField.create!(attributes)
    end

    root = Project.create!(identifier: definitions::ROOT_IDENTIFIER, name: 'Projektportfolio',
                           is_public: false, inherit_members: false, enabled_module_names: [])
    ticket_permissions = %i[view_issues add_issues edit_issues add_issue_notes]
    lead = Role.create!(name: definitions::LEAD_ROLE, issues_visibility: 'all',
                        permissions: ticket_permissions + %i[edit_project delete_issues view_private_notes])
    contributor = Role.create!(name: 'Projektmitarbeiter', permissions: ticket_permissions)
    reader = Role.create!(name: 'Portfolio-Leser', permissions: [:view_issues])
    lead.copy_workflow_rules(Role.find_by!(name: I18n.t(:default_role_manager, locale: :de)))
    contributor.copy_workflow_rules(Role.find_by!(name: I18n.t(:default_role_developer, locale: :de)))

    users = {
      'lead_geo' => ['Lara', 'Muster', 'LEAD_GEO'],
      'member_geo' => ['Milo', 'Beispiel', 'MEMBER_GEO'],
      'reader_geo' => ['Ria', 'Testa', 'READER_GEO'],
      'lead_it' => ['Lea', 'Demo', 'LEAD_IT'],
      'nonmember' => ['Nino', 'Fiktiv', 'NONMEMBER']
    }.to_h do |login, (first_name, last_name, password_key)|
      password = ENV.fetch("PORTFOLIO_#{password_key}_PASSWORD")
      abort "Generate a strong password for #{login}" unless password.match?(/\A[0-9a-f]{64}\z/)

      [login, User.create!(login: login, firstname: first_name, lastname: last_name,
                           mail: "#{login}@example.invalid", language: 'de',
                           password: password, password_confirmation: password)]
    end

    today = Time.find_zone!(definitions::TIME_ZONE).today
    demo_projects = [
      ['datenportal', 'Datenportal', 'Geoinformation', 'Umsetzung', 'Grün', 90, -5, 'Prototyp mit der Fachstelle prüfen.'],
      ['gretl-runtime', 'GRETL Runtime', 'Geoinformation', 'Umsetzung', 'Gelb', 30, -12, 'Laufzeitmessung wiederholen.'],
      ['interlis-compiler', 'INTERLIS Compiler', 'Geoinformation', 'Umsetzung', 'Rot', -7, -10, 'Offene Validierungsfehler priorisieren.'],
      ['web-gis-client', 'Web GIS Client', 'Geoinformation', 'Umsetzung', 'Grün', 120, -3, 'Kartenwerkzeuge im Pilotbetrieb prüfen.'],
      ['geodaten-api', 'Geodaten-API', 'Geoinformation', 'Geplant', nil, 180, nil, 'Schnittstellenentwurf abstimmen.'],
      ['gebaeudeadressen', 'Gebäudeadressen', 'Geoinformation', 'Pausiert', 'Gelb', -15, -40, 'Abhängigkeiten mit den Gemeinden klären.'],
      ['datenqualitaet', 'Datenqualität', 'Geoinformation', 'Umsetzung', 'Grün', 45, -31, 'Qualitätsregeln an Stichproben erproben.'],
      ['digitales-archiv', 'Digitales Archiv', 'Informatik', 'Geplant', nil, 200, nil, 'Ablagekonzept abstimmen.'],
      ['identity-management', 'Identity Management', 'Informatik', 'Umsetzung', 'Gelb', 60, -18, 'Pilotgruppe festlegen.'],
      ['entwicklungsplattform', 'Entwicklungsplattform', 'Informatik', 'Umsetzung', 'Grün', 100, -7, 'Vorlagen für Teams bereitstellen.'],
      ['personalkennzahlen', 'Personalkennzahlen', 'Statistik', 'Umsetzung', 'Rot', -2, -45, 'Datenlieferung mit der Fachstelle klären.'],
      ['abstimmungsportal', 'Abstimmungsportal', 'Statistik', 'Geplant', nil, 130, nil, 'Anforderungen an den Testbetrieb sammeln.'],
      ['archiv-integration', 'Archiv-Integration', 'Staatskanzlei', 'Idee', nil, nil, nil, 'Machbarkeit mit dem Archiv besprechen.'],
      ['meldesystem', 'Meldesystem', 'Staatskanzlei', 'Abgeschlossen', 'Grün', -60, -60, 'Betriebsübergabe dokumentiert.'],
      ['workflow-automation', 'Workflow-Automation', 'Staatskanzlei', 'Pausiert', 'Rot', 60, -35, 'Ausstehende Prozessentscheidung klären.']
    ]

    projects = demo_projects.each_with_index.to_h do |(identifier, name, department, phase, health, due, updated, next_step), index|
      project = Project.new(identifier: identifier, name: name, parent: root,
                            is_public: false, inherit_members: false, enabled_module_names: ['issue_tracking'])
      values = {
        department: department, phase: phase, health: health, next_step: next_step,
        priority: definitions::PRIORITIES[index % definitions::PRIORITIES.length],
        due_date: due && (today + due).iso8601, status_date: updated && (today + updated).iso8601
      }
      project.custom_field_values = values.to_h { |key, value| [fields.fetch(key).id, value] }
      project.save!
      if department == 'Geoinformation'
        project.memberships.create!(user: users.fetch('lead_geo'), roles: [lead])
        project.memberships.create!(user: users.fetch('member_geo'), roles: [contributor]) if index < 4
        project.memberships.create!(user: users.fetch('reader_geo'), roles: [reader]) if index < 5
      elsif department == 'Informatik'
        project.memberships.create!(user: users.fetch('lead_it'), roles: [lead])
      end
      [identifier, project]
    end

    # Root membership alone must grant no access to descendants.
    root.memberships.create!(user: users.fetch('reader_geo'), roles: [reader])
    [
      ['datenportal', 'Feature', 'Metadaten für den Pilotbetrieb ergänzen'],
      ['interlis-compiler', 'Fehler', 'Validierung optionaler Attribute korrigieren'],
      ['gretl-runtime', 'Unterstützung', 'Zeitpunkt der Testmigration klären']
    ].each do |identifier, tracker_name, subject|
      Issue.create!(project: projects.fetch(identifier), tracker: Tracker.find_by!(name: tracker_name),
                    author: users.fetch('lead_geo'), subject: subject)
    end

    Setting.plugin_redmine_portfolio = {'demo_seeded' => true}
  end
end
