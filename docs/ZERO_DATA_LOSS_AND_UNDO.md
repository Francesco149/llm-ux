# State Safety, Infinite Undo & Zero Data Loss

> **"A user must never lose a single keystroke, slider drag, or canvas stroke, even across process crashes and system reboots."**

---

## 1. The Continuous Interaction Coalescing Rule

### The Anti-Pattern
Pushing an undo snapshot on every `mouse_move` or frame while dragging a slider or canvas stroke fills the undo buffer with 60 micro-steps. Pressing `Ctrl+Z` then steps backward by $0.1\%$ increments rather than undoing the entire gesture.

### The Correct Pattern
1. Capture starting state on `IsItemActivated()`.
2. Continuously update live preview during the drag.
3. Push the single final snapshot to the undo journal on `IsItemDeactivatedAfterEdit()`.

```lua
function ui.undoable_slider(label, val, min_v, max_v, on_change, on_commit)
    local changed, nv = ig.slider_float(label, val, min_v, max_v)
    if changed then
        on_change(nv) -- Live visual update
    end
    if ig.is_item_deactivated_after_edit() and on_commit then
        on_commit()   -- Push single consolidated undo snapshot
    end
end
```

---

## 2. Multi-Session Undo Journaling (`undo.jsonl`)

Every committed document mutation is recorded to an append-only JSON Lines file:
```jsonl
{"t": 1723901234, "desc": "Add Cube", "state": { ... }}
{"t": 1723901240, "desc": "Extrude Face", "state": { ... }}
```
When reopening a project, the undo stack is reconstructed from the journal, preserving the creator's full historical context across editing sessions.

---

## 3. Debounced 300ms Autosave & Backup Rotation

- **Debounce Timer**: When a mutation occurs, mark `doc.dirty = true` and `doc.dirty_time = current_time()`.
- **Tick**: If `now - doc.dirty_time >= 0.300`, flush state to disk atomically.
- **Backup Rotation**: On save, write to `project.tmp`, rotate `project.backup.1.json` $\to$ `project.backup.2.json`, then rename `project.tmp` $\to$ `project.json`. Power cuts or OS crashes can never corrupt project files.
