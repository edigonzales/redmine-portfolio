require_relative '../../../config/environment'

unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'redmine_test'
  abort 'Run the tests in the isolated redmine_test database'
end

# The isolated Compose runner has already migrated this database.
ActiveRecord.maintain_test_schema = false
require 'rails/test_help'

load Rails.root.join('scripts/bootstrap.rb')

class PortfolioTest < ActionDispatch::IntegrationTest

  setup do
    @admin = User.find_by!(login: 'admin')
    @reader = User.find_by!(login: 'reader_geo')
    @lead = User.find_by!(login: 'lead_geo')
    @root = Project.find_by!(identifier: 'portfolio')
    @project = Project.find_by!(identifier: 'datenportal')
    @fields = RedminePortfolio::Definitions::FIELDS.transform_values do |name, *|
      ProjectCustomField.find_by!(name: name)
    end
    @today = Time.find_zone!('Europe/Zurich').today
  end

  test 'demo fields, expected counts and role scopes' do
    RedminePortfolio::Definitions::FIELDS.each do |key, (_name, format, values)|
      assert_equal format, @fields[key].field_format
      assert_equal values, @fields[key].possible_values if values
    end
    assert_equal [15, 8, 3, 3, 3, 4], report.metrics.values
    assert_equal [5, 3, 3, 4], report.distribution.values
    {'lead_geo' => 7, 'member_geo' => 4, 'reader_geo' => 5, 'lead_it' => 3, 'nonmember' => 0}.each do |login, count|
      assert_equal count, report(User.find_by!(login: login)).metrics.fetch('all'), login
    end
    assert_equal [@lead.name], report(@reader).rows.find { |row| row[:project] == @project }.fetch(:leads)
  end

  test 'active descendants, including nested projects, use Redmine visibility' do
    nested = Project.new(name: 'Nested', identifier: 'nested-test', parent: @project, is_public: false)
    set_fields(nested, phase: 'Geplant')
    Project.create!(name: 'Outside', identifier: 'outside-test', is_public: true)
    Project.find_by!(identifier: 'archiv-integration').archive
    assert_equal 15, report.rows.size
    assert_includes report.rows.map { |row| row[:project] }, nested
    refute_includes report(@reader).rows.map { |row| row[:project] }, nested
    refute_includes report.rows.map { |row| row[:project] }, @root
    assert_includes report.rows.map { |row| row[:project].identifier }, 'meldesystem'
    refute_includes report.rows.map { |row| row[:project].identifier }, 'archiv-integration'
    refute_includes report.rows.map { |row| row[:project].identifier }, 'outside-test'
  end

  test 'date boundaries, absent dates and completed projects' do
    [[-1, -31, true, true], [0, -30, false, false], [1, -29, false, false], [nil, nil, false, true]].each do |due, update, overdue, stale|
      set_fields(@project, due_date: due && (@today + due).iso8601,
                           status_date: update && (@today + update).iso8601)
      assert_equal overdue, contains_project?(report(metric: 'overdue'))
      assert_equal stale, contains_project?(report(metric: 'stale'))
    end
    set_fields(@project, phase: 'Abgeschlossen', due_date: (@today - 1).iso8601, health: 'Rot')
    %w[overdue stale critical].each { |metric| refute contains_project?(report(metric: metric)) }
  end

  test 'filters are independent of metric counts and use native department options' do
    @fields[:department].update!(possible_values: @fields[:department].possible_values + ['Kultur'])
    assert_includes report.options[:department], 'Kultur'
    params = {department: 'Geoinformation', phase: 'Umsetzung', health: 'Rot'}
    filtered = report(**params, metric: 'critical')
    assert_equal ['interlis-compiler'], filtered.rows.map { |row| row[:project].identifier }
    assert_equal report(**params).metrics, filtered.metrics
    assert_equal [0, 0, 1, 0], filtered.distribution.values
    assert_empty report(department: [], phase: 'invalid', health: {bad: 'Rot'}).filters
  end

  test 'field visibility controls options, project rows, chart and derived counts' do
    @fields[:health].update!(visible: false, role_ids: [Role.find_by!(name: 'Projektleitung').id])
    @fields[:status_date].update!(visible: false)
    restricted = report(@reader, health: 'Rot')
    assert_empty restricted.options[:health]
    assert_empty restricted.filters
    assert restricted.rows.none? { |row| row.key?(:health) || row.key?(:status_date) }
    assert_equal 0, restricted.metrics.fetch('critical')
    assert_equal [0, 0, 0, 0], restricted.distribution.values
    assert_equal 1, report(@lead).metrics.fetch('critical')
    assert_equal 0, report(@lead).metrics.fetch('stale')
    assert_equal 3, report.metrics.fetch('critical')
  end

  test 'public projects respect built-in and overridden roles for restricted fields' do
    project = Project.find_by!(identifier: 'identity-management')
    project.update!(is_public: true)
    user = User.find_by!(login: 'nonmember')
    @fields[:health].update!(visible: false, role_ids: [Role.non_member.id])
    assert report(user).rows.find { |row| row[:project] == project }.key?(:health)
    project.memberships.create!(principal: GroupNonMember.first, roles: [Role.find_by!(name: 'Portfolio-Leser')])
    refute report(User.find(user.id)).rows.find { |row| row[:project] == project }.key?(:health)
  end

  test 'malformed stored values and invalid configuration' do
    @project.custom_values.find_by!(custom_field: @fields[:due_date]).update_column(:value, '2026-02-30')
    @project.custom_values.find_by!(custom_field: @fields[:health]).update_column(:value, 'Unbekannt')
    row = report.rows.find { |entry| entry[:project] == @project }
    assert_nil row[:due_date]
    assert_nil row[:health]
    @fields[:priority].update_column(:field_format, 'int')
    assert_raises(RedminePortfolio::Report::ConfigurationError) { report }
    @fields[:priority].destroy!
    assert_raises(RedminePortfolio::Report::ConfigurationError) { report }
    @root.update_column(:identifier, 'renamed-portfolio')
    assert_raises(RedminePortfolio::Report::ConfigurationError) { report }
  end

  test 'dashboard is authenticated, read-only, role-scoped and renders filter links' do
    get '/portfolio'
    assert_redirected_to(/\/login/)
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path('/portfolio', method: :post) }
    log_in('reader_geo')
    get '/portfolio', params: {department: 'Geoinformation', metric: 'critical'}
    assert_response :success
    assert_select '.ppm-kpi-value', text: '5'
    assert_select '.ppm-table tbody tr', count: 1
    assert_select 'a[href="/projects/interlis-compiler"]', count: 1
    assert_select 'a[href="/projects/identity-management"]', count: 0
    assert_select 'a[data-metric=critical][href="/portfolio?department=Geoinformation"]', count: 1
    get '/portfolio', params: {phase: ['Umsetzung'], metric: {bad: 1}}
    assert_response :success
    assert_select '.ppm-table tbody tr', count: 5
    get '/projects/identity-management'
    assert_response :forbidden
  end

  test 'renders project data as text and diagnoses missing configuration only for administrators' do
    @project.update!(name: '<b>Projekt</b>')
    set_fields(@project, next_step: '<em>Schritt</em>')
    log_in('admin')
    get '/portfolio'
    assert_response :success
    assert_select '.ppm-table b, .ppm-table em', count: 0
    assert_includes response.body, '&lt;b&gt;Projekt&lt;/b&gt;'
    assert_includes response.body, '&lt;em&gt;Schritt&lt;/em&gt;'
    @fields[:phase].destroy!
    get '/portfolio'
    assert_includes response.body, 'PPM: Phase'
    reset!
    log_in('reader_geo')
    get '/portfolio'
    assert_response :success
    refute_includes response.body, 'PPM: Phase'
  end

  test 'repeat bootstrap preserves native edits, counts and passwords' do
    set_fields(@project, phase: 'Geplant')
    snapshot = [Project.count, User.count, Role.count, ProjectCustomField.count, Member.count, Issue.count, @admin.hashed_password]
    load Rails.root.join('scripts/bootstrap.rb')
    assert_equal snapshot, [Project.count, User.count, Role.count, ProjectCustomField.count, Member.count, Issue.count, @admin.reload.hashed_password]
    assert_equal 'Geplant', @project.reload.custom_field_value(@fields[:phase])
  end

  test 'report loads restricted fields and leads in bulk for a hundred projects' do
    @fields[:health].update!(visible: false, role_ids: [Role.find_by!(name: 'Projektleitung').id])
    lead_role = Role.find_by!(name: 'Projektleitung')
    100.times do |index|
      project = Project.new(name: "Bulk #{index}", identifier: "bulk-#{index}", parent: @root, is_public: false)
      set_fields(project, phase: 'Geplant', health: 'Gelb')
      project.memberships.create!(user: @lead, roles: [lead_role])
    end

    query_count = 0
    count_queries = ->(_name, _start, _finish, _id, payload) do
      query_count += 1 if payload[:sql].start_with?('SELECT') && !payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(count_queries, 'sql.active_record') do
      result = report(User.find(@lead.id))
      assert_equal 107, result.rows.size
      assert_equal 100, result.rows.count { |row| row[:project].identifier.start_with?('bulk-') && row[:health] == 'Gelb' }
    end
    assert_operator query_count, :<, 30
  end

  private

  def report(user = @admin, **params)
    RedminePortfolio::Report.new(user: user, today: @today, params: params)
  end

  def set_fields(project, **values)
    project.custom_field_values = values.to_h { |key, value| [@fields.fetch(key).id, value] }
    project.save!
  end

  def contains_project?(result)
    result.rows.any? { |row| row[:project] == @project }
  end

  def log_in(login)
    post '/login', params: {username: login, password: ENV.fetch("PORTFOLIO_#{login.upcase}_PASSWORD")}
    assert_response :redirect
  end
end
