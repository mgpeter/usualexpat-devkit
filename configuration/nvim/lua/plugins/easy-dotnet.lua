return {
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("easy-dotnet").setup()

    -- Convenience keymaps (all under <leader>d for "dotnet")
    local dotnet = require("easy-dotnet")
    local map = vim.keymap.set
    map("n", "<leader>db", dotnet.build,        { desc = "Dotnet: build" })
    map("n", "<leader>dr", dotnet.run,          { desc = "Dotnet: run" })
    map("n", "<leader>dt", dotnet.testrunner,   { desc = "Dotnet: test runner" })
    map("n", "<leader>dw", dotnet.watch,        { desc = "Dotnet: watch" })
    map("n", "<leader>dn", dotnet.new,          { desc = "Dotnet: new from template" })
    map("n", "<leader>ds", dotnet.secrets,      { desc = "Dotnet: user secrets" })
    map("n", "<leader>do", dotnet.outdated,     { desc = "Dotnet: outdated packages" })
  end,
}
