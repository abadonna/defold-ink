local M = {}

local function testflag(value, flag)
	return bit.band(value, flag) == flag
end

M.create = function(data, parent, name)
	local container = {
		name = name or "",
		is_container = true,
		index = 1, 
		parent = parent, 
		content = {},
		attributes = {},
		stitch = "__root"
	}

	if parent then
		container.name = parent.name .. "." .. container.name
		container.stitch = parent.stitch
	end

	container.is_end = function()
		return container.index > #container.content
	end
	
	container.next = function() 
		if container.is_end() then return nil end
		local item = container.content[container.index]
		container.index = container.index + 1
		return item
	end

	if type(data) ~= "table" then
		return container
	end

	--read attributes first
	local attrs = data[#data]
	if type(attrs) == "table" then 
		container.attributes = attrs

		if attrs["#n"] then
			container.name = container.name .. "." .. attrs["#n"]
		end

		if parent and attrs["#f"] and testflag(attrs["#f"], 0x1) and not testflag(attrs["#f"], 0x4) then
			container.stitch = container.name
		end

		for key, value in pairs(attrs) do
			if type(value) == "table" and #value > 0 then
				container.attributes[key] = M.create(value, container, key)
			end
		end
	end
		
	--read items
	for i, item in ipairs(data) do
		if i < #data then
			if type(item) == "table" and #item > 0 then
				item = M.create(item, container)
			end
			table.insert(container.content, item)
		end
	end

	return container
end

return M