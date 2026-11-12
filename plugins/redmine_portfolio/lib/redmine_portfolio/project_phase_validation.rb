module RedminePortfolio
  module ProjectPhaseValidation
    extend ActiveSupport::Concern

    included do
      validate :require_portfolio_phase
    end

    private

    def require_portfolio_phase
      return unless parent && parent.self_and_ancestors.exists?(identifier: Definitions::ROOT_IDENTIFIER)

      name = Definitions::FIELDS.fetch(:phase).first
      phase = custom_field_values.find { |value| value.custom_field.name == name }
      errors.add(:base, "#{name} #{I18n.t('errors.messages.blank')}") if phase && phase.value.blank?
    end
  end
end
