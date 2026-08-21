-- WezTerm configuration.
--
-- Companion to `scripts/programs/wezterm.sh`. WezTerm is installed alongside
-- Terminator rather than replacing it, so nothing here assumes it owns
-- Ctrl+Alt+T. Drop wallpapers into ~/.config/wezterm/bg to get backgrounds.

local wezterm = require 'wezterm'
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

local initial_bg = random_background()
if initial_bg then
  config.window_background_image = initial_bg
  config.window_background_image_hsb = IMAGE_HSB
else
  -- No wallpapers yet -- degrade to a plainly translucent window rather than
  -- shipping a half-configured image setup.
  config.window_background_opacity = 0.95
end

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------
config.keys = {
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
      overrides.window_background_image = image
      overrides.window_background_image_hsb = IMAGE_HSB
      window:set_config_overrides(overrides)
    end),
  },
}

return config
