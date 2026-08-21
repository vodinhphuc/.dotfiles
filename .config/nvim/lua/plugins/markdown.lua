-- Reading markdown: in-buffer rendering and the glow pager (<leader>m…).

return {
  { -- Render markdown inside the buffer: headings, bullets, tables, code blocks
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    ft = { 'markdown' },
    -- Styles the real buffer in place and un-renders the line the cursor is on,
    -- so reading and editing happen in the same window.
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      completions = { lsp = { enabled = true } },
      -- No `latex`/`html` treesitter parsers installed above, so leave those
      -- renderers off rather than let `:checkhealth` warn about them.
      latex = { enabled = false },
      html = { enabled = false },
    },
    keys = {
      { '<leader>mt', '<cmd>RenderMarkdown toggle<CR>', desc = '[M]arkdown [T]oggle render' },
    },
  },

  { -- Preview markdown with glow in a floating window, same as in the terminal
    'ellisonleao/glow.nvim',
    ft = { 'markdown' },
    cmd = 'Glow',
    -- Uses the `glow` binary installed by `scripts/programs/glow.sh`.
    opts = {
      style = 'dark',
      border = 'rounded',
      width_ratio = 0.85,
      height_ratio = 0.85,
    },
    keys = {
      { '<leader>mp', '<cmd>Glow<CR>', desc = '[M]arkdown [P]review (glow)' },
    },
    config = function(_, opts)
      local glow = require 'glow'
      glow.setup(opts)

      -- glow.nvim pipes glow's stdout instead of giving it a PTY, so glow sees
      -- "not a terminal" and drops to a colorless profile -- correct layout, but
      -- none of the colour you get from `glow` in the shell. CLICOLOR_FORCE makes
      -- it emit colour anyway. Set it around the spawn only: exporting it for the
      -- whole session would also force ANSI colour into ripgrep, git and the LSP
      -- servers, whose output nvim parses as plain text.
      vim.api.nvim_create_user_command('Glow', function(cmd_opts)
        local saved = vim.env.CLICOLOR_FORCE
        vim.env.CLICOLOR_FORCE = '1'
        -- glow.execute spawns synchronously, so restoring right after is safe.
        local ok, caught = pcall(glow.execute, cmd_opts)
        vim.env.CLICOLOR_FORCE = saved
        if not ok then error(caught) end
      end, { complete = 'file', nargs = '?', bang = true, desc = 'Preview markdown with glow' })
    end,
  },
}
