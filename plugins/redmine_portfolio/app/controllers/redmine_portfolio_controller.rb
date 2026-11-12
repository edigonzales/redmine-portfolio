class RedminePortfolioController < ApplicationController
  before_action :require_login

  def index
    @report = RedminePortfolio::Report.new(user: User.current, params: params)
  rescue RedminePortfolio::Report::ConfigurationError => error
    @configuration_error = error.message if User.current.admin?
    render :index
  end
end
