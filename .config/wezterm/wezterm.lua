-- WezTerm configuration.
--
-- Companion to `scripts/programs/wezterm.sh`. WezTerm is installed alongside
-- Terminator rather than replacing it, so nothing here assumes it owns
-- Ctrl+Alt+T. Drop wallpapers into ~/.config/wezterm/bg to get backgrounds.

local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

-- ---------------------------------------------------------------------------
-- Input method (ibus / Vietnamese)
-- ---------------------------------------------------------------------------
-- `use_ime` already defaults to true; it is spelled out because it is the one
-- setting that decides whether Vietnamese typing works here at all. On Wayland
-- WezTerm needs the compositor's zwp_text_input_v3 (mutter has it) -- it does
-- NOT read GTK_IM_MODULE the way Terminator/VTE does, so ibus behaviour is not
-- guaranteed to match. If composing misbehaves, uncomment `enable_wayland` to
-- fall back to the X11/XIM path, which is the better-trodden route for ibus.
config.use_ime = true
-- config.enable_wayland = false

-- ---------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------
config.color_scheme = 'Catppuccin Mocha' -- same flavour as the nvim colorscheme
config.font = wezterm.font 'JetBrainsMono Nerd Font'
config.font_size = 12.0

-- tmux already supplies tabs and a status line, so WezTerm's own tab bar is
-- mostly redundant on this machine -- keep it only when it says something.
config.hide_tab_bar_if_only_one_tab = true

-- No title bar, to give the terminal the whole window.
--
-- 'RESIZE' rather than 'NONE': the two differ only by the invisible resize
-- border, and the WezTerm docs are explicit that dropping RESIZE breaks
-- resizing and minimising. Note that on Wayland the compositor is still free to
-- impose its own decorations, so treat this as a request, not a guarantee.
-- With no title bar to grab, drag the window with SUPER held down.
config.window_decorations = 'RESIZE'

-- Fill the screen on launch.
--
-- `maximize()` is used instead of `toggle_fullscreen()` deliberately: combined
-- with the borderless setting above it already yields the entire screen minus
-- GNOME's top bar, while leaving the clock, tray and a normal Alt-Tab intact.
-- True fullscreen hides those too -- press F11 (bound below) when you want it,
-- or swap the call here to make it the default.
--
-- `cmd or {}` matters: without it, `wezterm start -- htop` would silently drop
-- the program and just open a shell.
wezterm.on('gui-startup', function(cmd)
  local _, _, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

-- ...and every window after the first.
--
-- `gui-startup` fires once, when the GUI *process* starts. Ctrl+Alt+T asks the
-- already-running wezterm to open a window instead of starting a new process,
-- so the handler above never runs for it and window two onwards opened at the
-- default size. `window-config-reloaded` does fire for each newly spawned
-- window (upstream wezterm#3173), which is what makes this work.
--
-- The seen-set is load-bearing, not defensive: this same event also fires on
-- every `window:set_config_overrides()` call -- which is exactly what
-- CTRL+SHIFT+b does -- so without it, changing wallpaper would yank a window
-- you had deliberately un-maximized back to full size. Keys must be strings;
-- wezterm.GLOBAL round-trips through a serialised form where integer keys do
-- not survive.
wezterm.on('window-config-reloaded', function(window)
  local id = tostring(window:window_id())
  local seen = wezterm.GLOBAL.seen_windows or {}
  if not seen[id] then
    seen[id] = true
    wezterm.GLOBAL.seen_windows = seen
    window:maximize()
  end
end)
config.scrollback_lines = 10000
config.window_close_confirmation = 'NeverPrompt'
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

-- ---------------------------------------------------------------------------
-- Background images
-- ---------------------------------------------------------------------------
-- Any .jpg/.jpeg/.png/.gif in ~/.config/wezterm/bg is a candidate; one is
-- chosen at random per window, and CTRL+SHIFT+b reshuffles without a restart.
-- The images are committed to the dotfiles repo, so they travel with a git pull.
local bg_dir = wezterm.home_dir .. '/.config/wezterm/bg'

-- Dim the picture so foreground text stays readable. Tune `brightness` here
-- rather than editing the source image.
local IMAGE_HSB = { brightness = 0.05, hue = 1.0, saturation = 1.0 }

local function random_background()
  local found = {}
  -- glob yields an empty table for a missing or empty directory, so this stays
  -- safe on a machine where the bg folder was never populated.
  for _, pattern in ipairs { '*.jpg', '*.jpeg', '*.png', '*.gif' } do
    for _, file in ipairs(wezterm.glob(bg_dir .. '/' .. pattern)) do
      table.insert(found, file)
    end
  end
  if #found == 0 then
    return nil
  end
  return found[math.random(#found)]
end

-- Build the layer stack for one wallpaper.
--
-- The explicit `background` form is used instead of `window_background_image`
-- because it *documents* what happens when a picture's aspect ratio does not
-- match the window, where the simpler option leaves it unspecified:
--   Cover     scale to fill the viewport, preserving ratio, cropping the excess
--   NoRepeat  never tile -- tiling is what makes an odd-sized image look wrong
--   Center    crop evenly from both edges rather than favouring one
-- A 4:3 wallpaper among 16:9 ones is exactly the case this pins down.
local function background_layers(image)
  return {
    -- Opaque base so no layer can ever leave a gap showing through to nothing.
    -- Catppuccin Mocha's `base`, to match the colorscheme.
    { source = { Color = '#1e1e2e' }, width = '100%', height = '100%' },
    {
      source = { File = image },
      hsb = IMAGE_HSB,
      width = 'Cover',
      height = 'Cover',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
      horizontal_align = 'Center',
      vertical_align = 'Middle',
    },
  }
end

local initial_bg = random_background()
if initial_bg then
  config.background = background_layers(initial_bg)
else
  -- No wallpapers yet -- degrade to a plainly translucent window rather than
  -- shipping a half-configured image setup.
  config.window_background_opacity = 0.95
end

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------
config.keys = {
  -- True fullscreen on demand -- also on WezTerm's built-in ALT+ENTER, but F11
  -- is what every other application on this desktop uses.
  { key = 'F11', action = wezterm.action.ToggleFullScreen },
  {
    key = 'b',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(window, _)
      local image = random_background()
      if not image then
        window:toast_notification('WezTerm', 'No images in ' .. bg_dir, nil, 4000)
        return
      end
      local overrides = window:get_config_overrides() or {}
      overrides.background = background_layers(image)
      window:set_config_overrides(overrides)
    end),
  },
}

return config
