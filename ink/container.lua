local M = {}

M.create = function(data, parent)
	local container = {
		is_container = true,
		index = 1, 
		parent = parent, 
		content = {},
		attributes = {},
	}

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
	
	for i, item in ipairs(data) do
		if i < #data then
			if type(item) == "table" and #item > 0 then
				item = M.create(item, container)
			end
			table.insert(container.content, item)
		elseif type(item) == "table" then
			container.attributes = item
			for key, value in pairs(item) do
				if type(value) == "table" and #value > 0 then
					container.attributes[key] = M.create(value, container)
				end
			end
		end
	end
	return container
end

return M