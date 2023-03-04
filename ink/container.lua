local M = {}

local function testflag(value, flag)
	return bit.band(value, flag) == flag
end

local function clone(obj)
	local copy = {}
	for key, value in pairs(obj) do
		if type(value) == "table" then
			copy[key] = clone(value)
		else
			copy[key] = value
		end
	end
	return copy
end

M.create = function(data, parent, name)
	local container = {
		name = name or "",
		is_container = true,
		index = 1, 
		parent = parent, 
		content = {},
		attributes = {},
		stitch = "__root",
		visits = 0
	}

	local keep_visits = false
	local count_start_only = false

	if parent then
		container.name = #parent.name == 0 and container.name or (parent.name .. "." .. container.name)
		container.stitch = parent.stitch
	end

	container.visit = function(name)
		name = name or ""
		if (not count_start_only) and (name:sub(1, #container.name) == container.name) then return end
		if not keep_visits then return end
		if count_start_only and container.index > 1 then return end -- need to visit parent maybe?
		
		container.visits = container.visits  + 1
		--pprint(container.name .. "|" .. name .. "|" .. container.visits)
		
		if parent then
			parent.visit(name)
		end
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

	data = clone(data)

	--read attributes first
	local attrs = data[#data]
	if type(attrs) == "table" then 
		container.attributes = attrs

		if attrs["#n"] then
			container.name = container.name .. "." .. attrs["#n"]
		end

		if attrs["#f"] then --read container's flags
			keep_visits = testflag(attrs["#f"], 0x1)
			count_start_only = testflag(attrs["#f"], 0x4) 
			
			if parent and keep_visits and not count_start_only then
				container.stitch = container.name
			end

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
				item = M.create(item, container, tostring(i))
			end
			table.insert(container.content, item)
		end
	end

	container.get_state = function()
		local state = {
			index = container.index,
			visits = container.visits,
			children = {}
		}

		for i, item in ipairs(container.content) do
			if type(item) == "table" and item.is_container then
				state.children[i] = item.get_state()
			end
		end

		return state
	end

	return container
end



return M