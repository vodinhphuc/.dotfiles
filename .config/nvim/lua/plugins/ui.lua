-- What you look at: keybinding hints, file sidebar, colorscheme.

return {
  -- NOTE: Plugins can also be configured to run Lua code when they are loaded.
  --
  -- This is often very useful to both group configuration, as well as handle
  -- lazy loading plugins that don't need to be loaded immediately at startup.
  --
  -- For example, in the following configuration, we use:
  --  event = 'VimEnter'
  --
  -- which loads which-key before all the UI elements are loaded. Events can be
  -- normal autocommands events (`:help autocmd-events`).
  --
  -- Then, because we use the `opts` key (recommended), the configuration runs
  -- after the plugin has been loaded as `require(MODULE).setup(opts)`.

  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter',
    ---@module 'which-key'
    ---@type wk.Opts
    ---@diagnostic disable-next-line: missing-fields
    opts = {
      -- delay between pressing a key and opening which-key (milliseconds)
      delay = 0,
      icons = {
        mappings = vim.g.have_nerd_font,

        -- `mappings = false` only drops the icon beside each description. The
        -- `keys` table below is independent of that flag and defaults to Nerd
        -- Font Private Use Area glyphs (Space is U+F1050), so without a patched
        -- font every special key renders as a tofu box. Fall back to plain text.
        keys = vim.g.have_nerd_font and {} or {
          Space = 'Space ',
          Esc = 'Esc ',
          BS = 'BS ',
          CR = 'CR ',
          NL = 'NL ',
          Tab = 'Tab ',
          Up = 'Up ',
          Down = 'Down ',
          Left = 'Left ',
          Right = 'Right ',
          C = 'C-',
          M = 'M-',
          D = 'D-',
          S = 'S-',
          ScrollWheelDown = 'ScrollDown ',
          ScrollWheelUp = 'ScrollUp ',
          F1 = 'F1',
          F2 = 'F2',
          F3 = 'F3',
          F4 = 'F4',
          F5 = 'F5',
          F6 = 'F6',
          F7 = 'F7',
          F8 = 'F8',
          F9 = 'F9',
          F10 = 'F10',
          F11 = 'F11',
          F12 = 'F12',
        },

        -- U+279C is a dingbat many monospace fonts lack; ASCII is safe everywhere.
        separator = vim.g.have_nerd_font and '➜' or '->',
      },

      -- Document existing key chains
      spec = {
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>m', group = '[M]arkdown', mode = { 'n' } },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } }, -- Enable gitsigns recommended keymaps first
        { 'gr', group = 'LSP Actions', mode = { 'n' } },
      },
    },
  },

  { -- IDE-style file tree in a docked side panel.
    'nvim-neo-tree/neo-tree.nvim',
    version = '*',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    -- Loaded eagerly on purpose. Lazy-loading it would leave netrw in charge of
    -- `nvim .` / `nvim <dir>`, so opening a directory would show netrw's listing
    -- instead of the tree -- which is exactly when you most want the tree.
    lazy = false,
    keys = {
      { '<leader>e', '<cmd>Neotree toggle<CR>', desc = 'File [E]xplorer (toggle)' },
      { '\\', '<cmd>Neotree reveal<CR>', desc = 'File explorer (reveal current file)' },
    },
    opts = {
      close_if_last_window = true, -- don't leave a bare tree behind after closing the last file
      filesystem = {
        -- This repo IS dotfiles: `.config/`, `.local/`, `.github/`. Neo-tree hides
        -- dotfiles by default, which would render the tree here almost empty.
        filtered_items = {
          visible = true, -- show filtered names anyway, dimmed rather than gone
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        follow_current_file = { enabled = true }, -- keep the tree in sync with the buffer
        use_libuv_file_watcher = true, -- pick up files created outside nvim, no manual refresh
        window = {
          mappings = {
            ['\\'] = 'close_window', -- same key in, same key out
          },
        },
      },
      window = { width = 32 },
    },
  },

  { -- The active colorscheme. Preview alternatives without editing this file:
    --   :Telescope colorscheme enable_preview=true
    -- To make a different one stick, change the `colorscheme` call at the bottom.
    'catppuccin/nvim',
    name = 'catppuccin', -- repo is `nvim`; without this the dir would collide
    priority = 1000, -- Make sure to load this before all the other start plugins.
    config = function()
      require('catppuccin').setup {
        flavour = 'mocha', -- 'latte' is the light one; 'frappe'/'macchiato' sit between
        styles = {
          comments = {}, -- Disable italics in comments (catppuccin italicises by default)
        },
        -- No `integrations` block on purpose: this version defaults to
        -- `auto_integrations = true`, which detects the installed plugins
        -- (telescope, which-key, gitsigns, blink.cmp, mason, mini) and themes
        -- their UIs itself. Listing them by hand only risks overriding a
        -- better default -- e.g. `blink_cmp = true` would drop the plugin's
        -- own `{ style = 'bordered' }`.
      }

      -- Load the colorscheme here.
      vim.cmd.colorscheme 'catppuccin-mocha'
    end,
  },

  { -- Kept installed but not loaded, so `:colorscheme tokyonight-night` (or the
    -- Telescope picker above) can switch back to the old theme at any time.
    'folke/tokyonight.nvim',
    lazy = true,
    ---@diagnostic disable-next-line: missing-fields
    opts = { styles = { comments = { italic = false } } },
  },
}
