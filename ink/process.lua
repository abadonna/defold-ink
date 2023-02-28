local M = {}

local function pop(stack)
	assert(#stack > 0, "empty stack!")
	local item = stack[#stack]
	table.remove(stack, #stack)
	return item
end

local function split(s, sep)
	if sep == nil then
		sep = '%s'
	end 

	local res = {}
	local func = function(w)
		table.insert(res, w)
	end 

	string.gsub(s, '[^'..sep..']+', func)
	return res 
end

M.find = function(path, parent) 

	local parts = split(path, ".")
	local container = parent
	while container.parent do
		container = container.parent
	end

	for _, part in ipairs(parts) do
		local index = tonumber(part)
		if index ~= nil then
			index = index + 1
			if container.content[index].is_container then
				container = container.content[index]
			else --nop?
				container.index = index
				return container
			end
		elseif part == "^" then
			container = parent
			parent = parent.parent
		else
			if container.attributes[part] then
				container = container.attributes[part]
			else
				for i, item in ipairs(container.content) do
					if item.is_container and item.attributes["#n"] == part then
						container.index = i + 1
						container = item
					end
				end
			end
		end
	end	

	container.index = 1
	return container
end

M.run = function(container, output, variables)
	local stack = {}
	while true do
		local item = container.next()

		if type(item) == "string" then
			if item == "\n" then
				local p = {text = table.concat(output.text), tags = output.tags}
				table.insert(output.paragraphs, p)
				output.text = {}
				output.tags = {}

			elseif item:sub(1, 1) == "^" then --string value
				table.insert(output.text, item:sub(2))

			elseif item == "done" then
				break
			elseif item == "end" then
				break
			elseif item == "ev" then --  start evaluation mode, objects are added to an evaluation stack
				--
			elseif item == "/ev" then 
				--assert(#stack == 0, "stack is not empty")
			elseif item == "str" then 
				--todo
			elseif item == "/str" then 
				--todo
			elseif item == "out" then 
				table.insert(output.text, pop(stack))
			elseif item == "+" then
				local value = pop(stack) + pop(stack)
				table.insert(stack, value)
			elseif item == "-" then
				local value = - pop(stack) + pop(stack)
				table.insert(stack, value)
			elseif item == "*" then
				local value = pop(stack) * pop(stack)
				table.insert(stack, value)
			elseif item == "/" then
				local value = 1 / pop(stack) * pop(stack)
				table.insert(stack, value)
			elseif item == "==" then
				local value = pop(stack) == pop(stack)
				table.insert(stack, value)
			elseif item == ">" then
				local value = pop(stack) < pop(stack)
				table.insert(stack, value)
			elseif item == ">=" then
				local value = pop(stack) <= pop(stack)
				table.insert(stack, value)
			elseif item == "<" then
				local value = pop(stack) > pop(stack)
				table.insert(stack, value)
			elseif item == "<=" then
				local value = pop(stack) >= pop(stack)
				table.insert(stack, value)
			elseif item == "!=" then
				local value = pop(stack) ~= pop(stack)
				table.insert(stack, value)
			elseif item == "nop" then
				--No-operation
			elseif item == "void" then
				--No-operation
			elseif item == "->->" then
				break
			else
				assert(false, "unkown command " .. item)
			end

		elseif type(item) == "number" then
			table.insert(stack, item)

		elseif type(item) == "table" then
			if item.is_container then -- inner container, go down hierachy
				container = item

			elseif item["*"] then --choice point
				local choice = {
					text = table.concat(output.text), 
					path = item["*"],
					flag = item["flg"],
					container = container
				}
				table.insert(output.choices, choice)
				output.text = {}

			elseif item["#"] then --tag
				table.insert(output.tags, item["#"])
			elseif item["->"] then --divert
				if (item["c"] == nil) or (item["c"] and pop(stack)) then
					local path = item["var"] and variables[item["->"]] or item["->"]
					container = M.find(path, container)
				end
			elseif item["^->"] then --variable divert target -- only in stack?
				table.insert(stack, item["^->"])
			elseif item["VAR?"] then --variable
				table.insert(stack, variables[item["VAR?"]])
			elseif item["VAR="] then --variable assignment
				variables[item["VAR="]] = pop(stack)
			elseif item["temp="] then --variable assignment //todo: temporary
				variables[item["temp="]] = pop(stack)
			elseif item["->t->"] then --tunnel
				M.run(M.find(item["->t->"], container), output, variables)

			else
				local error = ""
				for key,_ in pairs(item) do
					error = error .. key .. " "
				end
				assert(false, "unkown object " .. error)
			end
		end

		if container.is_end() then
			if not container.parent then
				break
			end
			container = container.parent
		end
	end
end


return M