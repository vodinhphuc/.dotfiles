-- Autocommands.

-- Keep the system input method out of Normal mode.
--
-- With a Vietnamese IME active, ibus composes the keystrokes and *commits* the
-- result to the terminal, which forwards it as a bracketed paste. Nvim inserts
-- pasted text at the cursor in ANY mode, so every Normal-mode key lands in the
-- buffer instead of running a command -- `<Space>sf` types "sf" rather than
-- opening Telescope. It is not the keymap layer: `vim.paste({'sf'}, -1)` in
-- Normal mode inserts "sf" too.
--
-- So switch the IME off on the way out of Insert and put it back on the way in.
-- Normal mode then always sees raw keys, and Insert mode still gets the real
-- Unikey engine with its usual Telex behaviour.
--
-- Guarded on ibus being present and a display being attached: over SSH the IME
-- lives on the client and there is nothing here to switch, and WSL has no ibus.
if vim.fn.executable 'ibus' == 1 and (vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY) then
  local IME_OFF = 'xkb:us::eng'
  local saved_engine = nil

  -- Async on purpose: `ibus engine` takes 16-40ms here, which is enough to be
  -- felt on every <Esc> if it blocked the UI. The switch landing a few ms late
  -- is harmless, since you are not typing at that instant.
  local function ibus(args, on_done)
    vim.system(vim.list_extend({ 'ibus' }, args), { text = true }, on_done)
  end

  local function ime_off()
    ibus({ 'engine' }, function(res)
      local current = vim.trim(res.stdout or '')
      if current ~= '' and current ~= IME_OFF then
        saved_engine = current
        ibus { 'engine', IME_OFF }
      end
    end)
  end

  local function ime_restore()
    if saved_engine then ibus { 'engine', saved_engine } end
  end

  local group = vim.api.nvim_create_augroup('ime-normal-mode', { clear = true })
  -- Nvim starts in Normal mode, so the IME has to come off at startup too.
  vim.api.nvim_create_autocmd({ 'VimEnter', 'InsertLeave' }, { group = group, callback = ime_off })
  vim.api.nvim_create_autocmd('InsertEnter', { group = group, callback = ime_restore })
  -- Leaving the IME switched off after quitting would break typing everywhere
  -- else, so this one blocks -- nvim is exiting anyway.
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      if saved_engine then vim.system({ 'ibus', 'engine', saved_engine }):wait() end
    end,
  })
end

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})
