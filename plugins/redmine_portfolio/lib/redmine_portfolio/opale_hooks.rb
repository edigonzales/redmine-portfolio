module RedminePortfolio
  class OpaleHooks < Redmine::Hook::ViewListener

    def view_layouts_base_html_head(context)
      return unless Setting.ui_theme == 'opale'

      context.fetch(:hook_caller).stylesheet_link_tag('portfolio_opale', plugin: 'redmine_portfolio')
    end
  end
end
