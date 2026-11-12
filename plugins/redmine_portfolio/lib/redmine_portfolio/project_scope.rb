module RedminePortfolio
  module ProjectScope
    def self.call(root:, user:)
      root.descendants.active.visible(user).reorder(:name, :id)
    end
  end
end
