# Protect the upstream administrator and initialise defaults before HTTP starts.
User.transaction do
  admin = User.lock.find_by(login: 'admin', admin: true)
  if admin&.check_password?('admin')
    password = ENV.fetch('PORTFOLIO_ADMIN_PASSWORD')
    abort 'Generate a strong administrator password with scripts/setup-secrets' unless password.match?(/\A[0-9a-f]{64}\z/)

    Redmine::DefaultData::Loader.load('de') unless Role.givable.exists?
    Setting.default_language = 'de'
    Setting.ui_theme = 'shadcn'
    Setting.login_required = '1'
    Setting.self_registration = '0'
    Setting.default_projects_public = '0'
    Setting.rest_api_enabled = '0'
    Setting.webhooks_enabled = '0'
    Setting.notified_events = []

    admin.password = admin.password_confirmation = password
    admin.language = 'de'
    admin.must_change_passwd = false
    admin.save!
  end
end
