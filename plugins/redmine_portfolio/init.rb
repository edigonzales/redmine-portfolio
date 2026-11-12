Redmine::Plugin.register :redmine_portfolio do
  name 'Projektportfolio'
  version '0.1.0'
  author "Stefan Ziegler"
  description "Portfolio-Kennzahlen für Redmine-Projekte"
  menu :top_menu, :portfolio, {controller: "redmine_portfolio", action: "index"},
       caption: :label_ppm_portfolio, if: ->(*) { User.current.logged? }
  settings default: {}
  requires_redmine version_or_higher: '7.0.3'
end

Project.include RedminePortfolio::ProjectPhaseValidation
