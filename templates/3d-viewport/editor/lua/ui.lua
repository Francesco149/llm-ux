-- ui.lua — Tooltips, widgets, and buttons for lowpoly-painter
local ui = {}
local ig = lp.ig
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

function ui.undoable_slider_float(label, val, min_v, max_v, on_change, on_commit)
    local changed, new_val = ig.slider_float(label, val, min_v, max_v)
    if changed then
        on_change(new_val)
    end
    if ig.is_item_deactivated_after_edit() and on_commit then
        on_commit()
    end
    return changed, new_val
end

function ui.undoable_drag3(label, vals, speed, on_change, on_commit)
    ig.text(label .. ":")
    ig.same_line(70)
    ig.set_next_item_width(55)
    local c1, x = ig.drag_float("##" .. label .. "x", vals[1], speed or 0.1)
    ig.same_line()
    ig.set_next_item_width(55)
    local c2, y = ig.drag_float("##" .. label .. "y", vals[2], speed or 0.1)
    ig.same_line()
    ig.set_next_item_width(55)
    local c3, z = ig.drag_float("##" .. label .. "z", vals[3], speed or 0.1)

    if c1 or c2 or c3 then
        on_change({ x, y, z })
    end
    if ig.is_item_deactivated_after_edit() and on_commit then
        on_commit()
    end
    return c1 or c2 or c3
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
