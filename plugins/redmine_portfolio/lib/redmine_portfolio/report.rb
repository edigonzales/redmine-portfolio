module RedminePortfolio
  class Report
    class ConfigurationError < StandardError; end

    METRICS = %w[all implementation planned critical overdue stale].freeze
    FILTERS = %i[department phase health].freeze
    HEALTH_BUCKETS = [*Definitions::HEALTH_VALUES, nil].freeze

    attr_reader :options, :filters, :metric, :metrics, :distribution, :rows, :visible_count

    def initialize(user:, params: {}, today: Time.find_zone!(Definitions::TIME_ZONE).today)
      @user = user
      @today = today
      root = Project.find_by(identifier: Definitions::ROOT_IDENTIFIER)
      raise ConfigurationError, I18n.t("ppm.missing_root", identifier: Definitions::ROOT_IDENTIFIER) unless root

      @fields = resolve_fields
      @list_options = @fields.filter_map do |key, field|
        next unless field.field_format == 'list'

        values = field.possible_values
        values &= Definitions::FIELDS.fetch(key).last unless key == :department
        [key, values]
      end.to_h
      projects = ProjectScope.call(root: root, user: user).preload(:custom_values).to_a
      @visible_count = projects.size
      @roles_by_project = roles_by_project if !user.admin? && @fields.values.any? { |field| !field.visible? }
      visible_rows = projects.map { |project| read_project(project) }
      @options = FILTERS.to_h do |key|
        field = @fields.fetch(key)
        options = @list_options.fetch(key) if field.visible? || user.admin? || visible_rows.any? { |row| row.key?(key) }
        [key, options || []]
      end
      @filters = FILTERS.filter_map do |key|
        value = params[key]
        [key, value] if value.is_a?(String) && @options.fetch(key).include?(value)
      end.to_h
      @metric = params[:metric] if METRICS.include?(params[:metric])

      filtered = visible_rows.select { |row| @filters.all? { |key, value| row[key] == value } }
      @metrics = METRICS.index_with { |key| filtered.count { |row| matches?(row, key) } }
      @rows = @metric ? filtered.select { |row| matches?(row, @metric) } : filtered
      @distribution = HEALTH_BUCKETS.index_with do |health|
        @rows.count { |row| row.key?(:health) && row[:health] == health }
      end
      load_leads
    end

    private

    def resolve_fields
      names = Definitions::FIELDS.values.map(&:first)
      found = ProjectCustomField.where(name: names).preload(:roles).group_by(&:name)
      Definitions::FIELDS.transform_values do |name, format, values|
        matches = found.fetch(name, [])
        field = matches.first
        unless matches.one? && field.field_format == format && !field.multiple?
          raise ConfigurationError, I18n.t("ppm.invalid_field", name: name)
        end
        if values && name != Definitions::FIELDS.fetch(:department).first &&
           (values - field.possible_values).any?
          raise ConfigurationError, I18n.t("ppm.invalid_options", name: name)
        end

        field
      end
    end

    # Use Redmine’s bulk role lookup to avoid a membership query for each restricted field row.
    def roles_by_project
      @user.project_ids_by_role.each_with_object(Hash.new { |hash, id| hash[id] = [] }) do |(role, ids), roles|
        ids.each { |id| roles[id] << role }
      end
    end

    def read_project(project)
      stored = project.custom_values.index_by(&:custom_field_id)
      roles = @roles_by_project&.fetch(project.id, nil)
      # Redmine uses its built-in role on public projects without a membership or role override.
      roles ||= [@user.builtin_role] if @roles_by_project && project.is_public?
      @fields.each_with_object({project: project}) do |(key, field), row|
        next unless field.visible? || @user.admin? || field.roles.intersect?(roles || [])

        value = stored[field.id]&.value.presence
        row[key] = case field.field_format
                   when 'list' then value if @list_options.fetch(key).include?(value)
                   when 'date' then parse_date(value)
                   else value
                   end
      end
    end

    def parse_date(value)
      Date.iso8601(value) if value&.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    rescue Date::Error
      nil
    end

    def matches?(row, metric)
      case metric
      when 'all' then true
      when 'implementation' then row[:phase] == 'Umsetzung'
      when 'planned' then row[:phase] == 'Geplant'
      when 'critical' then row.key?(:phase) && row[:phase] != 'Abgeschlossen' && row[:health] == 'Rot'
      when 'overdue' then row.key?(:phase) && row[:phase] != 'Abgeschlossen' && row[:due_date] && row[:due_date] < @today
      when 'stale'
        %w[Umsetzung Pausiert].include?(row[:phase]) && row.key?(:status_date) &&
          (row[:status_date].nil? || row[:status_date] < @today - Definitions::STATUS_STALE_AFTER_DAYS)
      end
    end

    def load_leads
      ids = @rows.map { |row| row.fetch(:project).id }
      return if ids.empty?

      leads = Member.visible(@user).where(project_id: ids, user_id: User.active.visible(@user).select(:id))
                    .joins(:roles).where(roles: {name: Definitions::LEAD_ROLE}).preload(:user)
                    .group_by(&:project_id)
      @rows.each do |row|
        row[:leads] = leads.fetch(row.fetch(:project).id, []).map { |member| member.user.name }.sort
      end
    end
  end
end
