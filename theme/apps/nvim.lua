-- Rutile Shell's colors for Neovim, from matugen: `:colorscheme rutile`. Written by tools/apptheme.py.
vim.cmd("highlight clear")
vim.g.colors_name = "rutile"
vim.o.background = "{{mode}}"
local c = {
  bg = "{{colors.surface.default.hex}}", fg = "{{colors.on_surface.default.hex}}",
  low = "{{colors.surface_container_low.default.hex}}", mid = "{{colors.surface_container.default.hex}}",
  high = "{{colors.surface_container_high.default.hex}}", muted = "{{colors.on_surface_variant.default.hex}}",
  outline = "{{colors.outline.default.hex}}", line = "{{colors.outline_variant.default.hex}}",
  primary = "{{colors.primary.default.hex}}", secondary = "{{colors.secondary.default.hex}}",
  tertiary = "{{colors.tertiary.default.hex}}", error = "{{colors.error.default.hex}}",
  pc = "{{colors.primary_container.default.hex}}", onpc = "{{colors.on_primary_container.default.hex}}",
  sc = "{{colors.secondary_container.default.hex}}", onsc = "{{colors.on_secondary_container.default.hex}}",
}
local hl = function(group, spec) vim.api.nvim_set_hl(0, group, spec) end
hl("Normal", { fg = c.fg, bg = c.bg })
hl("NormalFloat", { fg = c.fg, bg = c.high })
hl("FloatBorder", { fg = c.outline, bg = c.high })
hl("CursorLine", { bg = c.low })
hl("CursorLineNr", { fg = c.primary, bold = true })
hl("LineNr", { fg = c.outline })
hl("Visual", { bg = c.sc, fg = c.onsc })
hl("Search", { bg = c.pc, fg = c.onpc })
hl("IncSearch", { bg = c.primary, fg = c.bg })
hl("StatusLine", { fg = c.fg, bg = c.mid })
hl("StatusLineNC", { fg = c.muted, bg = c.low })
hl("WinSeparator", { fg = c.line })
hl("Pmenu", { fg = c.fg, bg = c.high })
hl("PmenuSel", { fg = c.onpc, bg = c.pc })
hl("Comment", { fg = c.outline, italic = true })
hl("Constant", { fg = c.tertiary })
hl("String", { fg = c.secondary })
hl("Identifier", { fg = c.fg })
hl("Function", { fg = c.primary })
hl("Statement", { fg = c.primary, bold = true })
hl("Type", { fg = c.tertiary })
hl("Special", { fg = c.secondary })
hl("Error", { fg = c.error })
hl("DiagnosticError", { fg = c.error })
hl("MatchParen", { fg = c.primary, bold = true, underline = true })
