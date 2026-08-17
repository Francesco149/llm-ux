-- theme.lua — Modern dark theme adhering to native-ui-ux master doctrine
local theme = {}
local ig = gb.ig

theme.accent = { 0.96, 0.62, 0.04, 1.0 }        -- Vibrant Amber
theme.accent_hover = { 1.00, 0.70, 0.15, 1.0 }
theme.accent_active = { 0.85, 0.52, 0.02, 1.0 }
theme.bg = { 0.10, 0.10, 0.12, 1.0 }
theme.bg_panel = { 0.12, 0.12, 0.14, 1.0 }
theme.bg_child = { 0.14, 0.14, 0.17, 1.0 }
theme.fg = { 0.92, 0.92, 0.95, 1.0 }
theme.fg_dim = { 0.50, 0.50, 0.56, 1.0 }
theme.selection = { 0.28, 0.32, 0.40, 1.0 }

return theme
