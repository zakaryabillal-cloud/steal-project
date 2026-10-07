--!strict
-- Server-driven onboarding steps (the client only displays them):
--   0 grab a relic at the Rift
--   1 bring it back to your Sanctuary
--   2 collect Essence at your Core
--   3 buy an upgrade
--   4 done

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)

type Session = Types.Session

local TutorialService = {}

TutorialService.Steps = {
	Claim = 0,
	Return = 1,
	Collect = 2,
	Upgrade = 3,
	Done = 4,
}

-- Moves the tutorial forward when `action` completes the current step.
function TutorialService.progress(session: Session, action: string)
	local step = session.data.tutorial
	local nextStep = step
	if action == "claim" and step == 0 then
		nextStep = 1
	elseif action == "deposit" and step <= 1 then
		nextStep = 2
	elseif action == "collect" and step == 2 then
		nextStep = 3
	elseif action == "purchase" and step >= 2 and step < 4 then
		nextStep = 4
	end
	if nextStep ~= step then
		session.data.tutorial = nextStep
		Sessions.markDirty(session)
	end
end

function TutorialService.markTip(session: Session, tip: string)
	if type(tip) ~= "string" or #tip > 32 then
		return
	end
	if not session.data.tips[tip] then
		session.data.tips[tip] = true
		Sessions.markDirty(session)
	end
end

return TutorialService
