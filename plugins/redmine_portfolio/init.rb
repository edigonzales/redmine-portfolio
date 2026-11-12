Redmine::Plugin.register :redmine_portfolio do
  name 'Projektportfolio'
  version '0.1.0'
  settings default: {}
  requires_redmine version_or_higher: '7.0.3'
end

Project.include RedminePortfolio::ProjectPhaseValidation
