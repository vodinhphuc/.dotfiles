-- ============================================================================
-- Neovim entry point.
--
-- Originally a single vendored copy of https://github.com/nvim-lua/kickstart.nvim;
-- split into modules so each concern has an obvious home. This file does four
-- things and nothing else: leader key, editor config, lazy.nvim bootstrap, and
-- the plugin import.
--
-- WHERE THINGS LIVE
--   lua/config/options.lua      editor options (numbers, clipboard, splits, …)
--   lua/config/keymaps.lua      standalone keymaps
--   lua/config/diagnostics.lua  how LSP diagnostics are rendered
--   lua/config/autocmds.lua     autocommands (yank highlight, IME-by-mode)
--   lua/plugins/*.lua           one file per concern, each returning a lazy spec
--
-- COMMON EDITS
--   Add an LSP server   -> lua/plugins/lsp.lua        (`servers` table)
--   Add a formatter     -> lua/plugins/format.lua     (`formatters_by_ft`)
--   Add a parser        -> lua/plugins/treesitter.lua (`ensure_installed`)
--   Add a plugin        -> drop a new file in lua/plugins/ returning { spec }
--                          -- it is picked up automatically, no import needed
--
-- Keybinding reference: docs/guides/nvim.md
-- Learning entry points: :Tutor, :checkhealth, :help lazy.nvim
-- ============================================================================


-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Set to true if you have a Nerd Font installed and selected in the terminal.
-- Both halves matter: `scripts/programs/nerd_font.sh` installs JetBrainsMono,
-- and the terminal must actually be pointed at it. Flipping this while the
-- terminal still uses an unpatched font renders every icon as a tofu box.
vim.g.have_nerd_font = true

-- Editor configuration. Order matters: these run before any plugin loads.
require 'config.options'
require 'config.keymaps'
require 'config.diagnostics'
require 'config.autocmds'

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then error('Error cloning lazy.nvim:\n' .. out) end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  You can press `?` in this menu for help. Use `:q` to close the window
--
--  To update plugins you can run
--    :Lazy update
--
-- NOTE: Here is where you install your plugins.
require('lazy').setup({
  -- Every file under lua/plugins/ is imported automatically.
  { import = 'plugins' },
}, { ---@diagnostic disable-line: missing-fields
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
