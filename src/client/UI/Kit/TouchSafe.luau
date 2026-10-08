--!strict
-- Keeps our right-hand touch buttons (abilities, Strike) clear of Roblox's
-- own touch Jump button (PlayerModule TouchJump), phase 6.5:
--   short side <= 500 px: 70 px at (1, -95, 1, -90)    (phones)
--   otherwise           : 120 px at (1, -170, 1, -210) (tablets)
-- Pure functions of the viewport (real pixels) and the HUD scale, shared by
-- UI (scale), Hud (ability cluster), BossHud (Strike) and the overlap tests.

local TouchSafe = {}

-- Logical offset from the bottom used since phase 4 (clears the phone jump).
TouchSafe.DefaultBottom = 150
TouchSafe.Margin = 10

-- HUD scale for a viewport (the UIScale of the HUD, modal and overlay layers).
function TouchSafe.scaleFor(viewport: Vector2, touch: boolean): number
	if touch then
		return math.clamp(math.min(viewport.Y / 560, viewport.X / 900), 0.62, 1.1)
	end
	return math.clamp(math.min(viewport.Y / 900, viewport.X / 1440), 0.72, 1.3)
end

-- Roblox's Jump button in real pixels: (minX, minY, maxX, maxY).
function TouchSafe.jumpRect(viewport: Vector2): (number, number, number, number)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 70 else 120
	local x = viewport.X - (size * 1.5 - 10)
	local y = viewport.Y - (if small then size + 20 else size * 1.75)
	return x, y, x + size, y + size
end

-- Logical (scaled HUD) offset from the bottom the right-hand buttons sit on.
function TouchSafe.bottomOffset(viewport: Vector2, scale: number): number
	local _, top = TouchSafe.jumpRect(viewport)
	return math.max(TouchSafe.DefaultBottom, math.ceil((viewport.Y - top) / scale) + TouchSafe.Margin)
end

return TouchSafe
