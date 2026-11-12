module RedminePortfolio
  class Report
    class ConfigurationError < StandardError; end

    METRICS = %w[all implementation planned critical overdue stale].freeze
    FILTERS = %i[department phase health].freeze
    COLUMNS = %w[project department phase health priority leads due_date next_step].freeze
    HEALTH_CODES = {'Grün' => 'green', 'Gelb' => 'yellow', 'Rot' => 'red', nil => 'unassessed'}.freeze
    DEFAULT_SORT = {sort: 'project', direction: 'asc'}.freeze

    attr_reader :options, :filters, :metric, :metrics, :distribution, :rows, :visible_count, :sort, :direction

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
      @distribution = HEALTH_CODES.keys.index_with do |health|
        @rows.count { |row| row.key?(:health) && row[:health] == health }
      end
      load_leads
      @sort, @direction = DEFAULT_SORT.values
      if COLUMNS.include?(params[:sort]) && (params[:direction].nil? || %w[asc desc].include?(params[:direction]))
        @sort = params[:sort]
        @direction = params[:direction] || 'asc'
      end
      sort_rows
    end

    def sort_params
      sort == 'project' && direction == 'asc' ? {} : {sort: sort, direction: direction}
    end

    def sort_link_params(column)
      filters.merge(metric: metric, sort: column, direction: sort == column && direction == 'asc' ? 'desc' : 'asc')
    end

    private

    def sort_rows
      entries = @rows.map do |row|
        project = row.fetch(:project)
        [sort_value(row), alphabetic(project.name), project.id, row]
      end
      @rows = entries.sort do |left, right|
        first, second = left[0], right[0]
        comparison = if first.nil? || second.nil?
                       (first.nil? ? 1 : 0) <=> (second.nil? ? 1 : 0)
                     elsif direction == 'desc'
                       second <=> first
                     else
                       first <=> second
                     end
        comparison.zero? ? (left[1, 2] <=> right[1, 2]) : comparison
      end.map(&:last)
    end

    def sort_value(row)
      case sort
      when 'project' then alphabetic(row.fetch(:project).name)
      when 'due_date' then row[:due_date]
      when 'leads' then alphabetic(row.fetch(:leads).join(', '))
      when 'health'
        alphabetic(I18n.t("ppm.health_labels.#{HEALTH_CODES.fetch(row[:health])}")) if row.key?(:health)
      else alphabetic(row[sort.to_sym])
      end
    end

    def alphabetic(text)
      text.presence&.unicode_normalize(:nfd)&.gsub(/\p{Mn}/, '')&.downcase
    end

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
