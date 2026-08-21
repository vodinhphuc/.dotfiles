-- Practising vim motions.

return {
  { -- Drill motions/verbs as a game: :VimBeGood picks an exercise, you race it
    'ThePrimeagen/vim-be-good',
    -- Standalone Lua, no dependencies. Only pulled in when you actually play,
    -- so it costs nothing at startup.
    -- No keymap on purpose: this is a `:VimBeGood` you run deliberately, and the
    -- existing <leader> groups are all Toggle/Search/Markdown/Git.
    cmd = 'VimBeGood',
  },
}
