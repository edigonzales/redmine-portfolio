module RedminePortfolio
  module Definitions
    ROOT_IDENTIFIER = 'portfolio'
    PHASES = %w[Idee Geplant Umsetzung Pausiert Abgeschlossen].freeze
    HEALTH_VALUES = %w[Grün Gelb Rot].freeze
    PRIORITIES = %w[Hoch Mittel Niedrig].freeze
    DEPARTMENTS = %w[Geoinformation Informatik Statistik Staatskanzlei].freeze
    STATUS_STALE_AFTER_DAYS = 30
    TIME_ZONE = 'Europe/Zurich'
    LEAD_ROLE = 'Projektleitung'

    FIELDS = {
      phase: ['PPM: Phase', 'list', PHASES],
      health: ['PPM: Ampel', 'list', HEALTH_VALUES],
      priority: ['PPM: Priorität', 'list', PRIORITIES],
      department: ['PPM: Fachstelle', 'list', DEPARTMENTS],
      due_date: ['PPM: Zieltermin', 'date'],
      next_step: ['PPM: Nächster Schritt', 'text'],
      status_date: ['PPM: Letztes Statusupdate', 'date']
    }.freeze
  end
end
