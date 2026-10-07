--!strict
-- Top-centre column shared by the event banner, the tutorial objective and
-- toast notifications, so they never overlap.

local Create = require(script.Parent.Parent.Kit.Create)
local Style = require(script.Parent.Parent.Kit.Style)

local TopStack = {}

local stack: Frame? = nil

function TopStack.get(parent: Instance): Frame
	if stack then
		return stack
	end
	local frame: Frame = Create("Frame", {
		Name = "TopStack",
		Size = UDim2.new(0, 520, 1, -20),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Style.list(frame, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	stack = frame
	return frame
end

return TopStack
