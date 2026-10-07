--!nocheck
-- Loads the official Roblox API dump and answers "is this a valid member?"
-- questions so the fake engine rejects typos, wrong value types, read-only
-- writes and non-scriptable members exactly like Roblox would.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Api = {}

local classes = {}

function Api.load(path: string)
	local raw = serde.decode("json", fs.readFile(path))
	for _, class in raw.Classes do
		local members = {}
		for _, member in class.Members do
			local tags = {}
			for _, tag in member.Tags or {} do
				if type(tag) == "string" then
					tags[tag] = true
				end
			end
			local security = member.Security
			local readSecurity, writeSecurity = "None", "None"
			if type(security) == "table" then
				readSecurity, writeSecurity = security.Read, security.Write
			elseif type(security) == "string" then
				readSecurity, writeSecurity = security, security
			end
			members[member.Name] = {
				kind = member.MemberType,
				valueType = member.ValueType,
				tags = tags,
				readSecurity = readSecurity,
				writeSecurity = writeSecurity,
			}
		end
		local classTags = {}
		for _, tag in class.Tags or {} do
			if type(tag) == "string" then
				classTags[tag] = true
			end
		end
		classes[class.Name] = { name = class.Name, superclass = class.Superclass, members = members, tags = classTags }
	end
end

function Api.class(name: string)
	return classes[name]
end

function Api.member(className: string, memberName: string)
	local class = classes[className]
	while class do
		local member = class.members[memberName]
		if member then
			return member, class.name
		end
		class = classes[class.superclass]
	end
	return nil
end

function Api.isA(className: string, ancestor: string): boolean
	local class = classes[className]
	while class do
		if class.name == ancestor then
			return true
		end
		class = classes[class.superclass]
	end
	return false
end

function Api.creatable(className: string): boolean
	local class = classes[className]
	return class ~= nil and not class.tags.NotCreatable and not class.tags.Service
end

return Api
