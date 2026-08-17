# Direct Manipulation & Interaction Physics for Creation Tools

> **"The quality of a creative tool is defined by the physical immediacy between the creator's hand and the viewport."**

---

## 1. Theoretical Grounding in Human-Computer Interaction (HCI)

1. **Shneiderman's Direct Manipulation (1983)**:
   - **Continuous Representation**: Objects of interest are visually represented at all times, rather than queried via textual syntax.
   - **Physical Actions Instead of Complex Syntax**: Direct grasping, dragging, and resizing replace modal commands.
   - **Rapid, Incremental, Reversible Operations**: Every operation produces instantaneous visual feedback and can be undone with zero penalty.

2. **Fitts's Law & Target Acquisition**:
   $$T = a + b \log_2 \left(1 + \frac{D}{W}\right)$$
   Where $D$ is distance to the target and $W$ is the effective target width.
   - **Implication**: Small 16px buttons far across a 4K display require immense cognitive and motor effort.
   - **Remedy**:
     - Right-click contextual menus spawn directly at the cursor ($D \to 0$).
     - Single-key hotkeys (`V`, `H`, `B`, `E`, `F`, `Z`) eliminate motor travel entirely ($D = 0$).
     - Minimum click target dimensions $\ge 24\text{px}$ to $32\text{px}$.

3. **Buxton's 3-State Model of Graphical Input**:
   - **State 0 (Out of Range)**: Cursor absent or offscreen.
   - **State 1 (Tracking)**: Hovering with visual affordance (subtle 1px border highlight, cursor icon change).
   - **State 2 (Dragging)**: Direct manipulation active (transformation in progress, ghost outline).

---

## 2. The Mathematics of Cursor-Anchored Zoom

When a user scrolls the wheel at screen position $(S_x, S_y)$, that exact point in world coordinates $(W_x, W_y)$ must remain stationary beneath the cursor.

$$\text{World Position:} \quad W_x = \frac{S_x - P_x}{Z}, \quad W_y = \frac{S_y - P_y}{Z}$$

When the zoom changes from $Z$ to $Z'$, the new pan offset $(P_x', P_y')$ must satisfy:

$$P_x' = S_x - W_x \times Z', \quad P_y' = S_y - W_y \times Z'$$

### The Drag Deadzone Law
Rapid clicking often introduces micro-jitters ($\sim 1\text{px}$ to $2\text{px}$). Without a deadzone, clicking a button or shape accidentally triggers an in-flight transform.

$$\Delta_{\text{mouse}} = \sqrt{(x - x_0)^2 + (y - y_0)^2}$$

- If $\Delta_{\text{mouse}} < 3.0\text{px}$ upon mouse release $\to$ **Click**.
- If $\Delta_{\text{mouse}} \ge 3.0\text{px} \to$ **Initiate Drag**.

---

## 3. Smooth Camera Inertia (Critical Damping Physics)

Instead of linear interpolation (which is frame-rate dependent) or raw step assignment (which causes jarring jump-cuts), use exponential smoothing:

$$\text{pos}_{t + \Delta t} = \text{pos}_t + (\text{target} - \text{pos}_t) \times \left(1 - e^{-k \Delta t}\right)$$

Where $k \approx 20.0 \text{ to } 25.0$ provides instantaneous responsiveness with smooth sub-pixel settle.
