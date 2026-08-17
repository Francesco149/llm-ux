-- ui.lua — UI widget helpers, tooltips with hotkey badges, and floating toolbars
local ui = {}
local ig = gb.ig
local theme = require("theme")

function ui.tooltip(title, shortcut, desc)
    if ig.is_item_hovered() then
        ig.begin_tooltip()
        ig.text_colored(title, 1.0, 1.0, 1.0, 1.0)
        if shortcut then
            ig.same_line(0, 6.0)
            ig.text_colored("(" .. shortcut .. ")", theme.accent[1], theme.accent[2], theme.accent[3], 1.0)
        end
        if desc then
            ig.text_colored(desc, 0.7, 0.7, 0.75, 1.0)
        end
        ig.end_tooltip()
    end
end

function ui.undoable_drag3(label, vals, speed, on_change, on_commit)
    local changed, x, y, z = ig.drag_float3(label, vals[1], vals[2], vals[3], speed or 0.1)
    if changed then
        on_change({ x, y, z })
    end
    if ig.is_item_deactivated_after_edit() and on_commit then
        on_commit()
    end
    return changed
end

function ui.undoable_color3(label, col, on_change, on_commit)
    local changed, r, g, b = ig.color_edit3(label, col[1], col[2], col[3])
    if changed then
        on_change({ r, g, b })
    end
    if ig.is_item_deactivated_after_edit() and on_commit then
        on_commit()
    end
    return changed
end

return ui
