local Container = require "ink.container" 

local M ={}

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

local function find(root, path, parent)

	local parts = split(path, ".")
	local container = root
	
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

M.create = function(s)
	local data = json.decode(s)
	local story = {variables = {}}

	local root = Container.create(data.root)
	local container = nil
	local choices = {}

	story.continue = function(answer)

		--todo check answer
		if #choices > 0 then
			assert(type(answer) == "number" and answer > 0 and answer <= #choices, "answer required")
			container = find(root, choices[answer].path, choices[answer].container)
		end
		choices = {}

		local tags = {}
		local stack = nil
		local output = {}
		local paragraphs = {}
		local answers = {}
		
		while true do
			local item = container.next()

			if type(item) == "string" then
				if item == "\n" then
					local p = {text = table.concat(output), tags = tags}
					table.insert(paragraphs, p)
					output = {}
					tags = {}
					
				elseif item:sub(1, 1) == "^" then --string value
					table.insert(output, item:sub(2))

				elseif item == "done" then
					break
				elseif item == "end" then
					break
				elseif item == "ev" then --  start evaluation mode, objects are added to an evaluation stack
					stack = {}
				elseif item == "/ev" then 
					--assert(#stack == 0, "stack is not empty")
					--stack = nil
				elseif item == "str" then 
					--todo
				elseif item == "/str" then 
					--todo
				elseif item == "out" then 
					table.insert(output, pop(stack))
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
						text = table.concat(output), 
						path = item["*"],
						flag = item["flg"],
						container = container
					}
					table.insert(choices, choice)
					table.insert(answers, choice.text)
					output = {}
					
				elseif item["#"] then --tag
					table.insert(tags, item["#"])
				elseif item["->"] then --divert
					if (item["c"] == nil) or (item["c"] and pop(stack)) then
						local path = item["var"] and story.variables[item["->"]] or item["->"]
						container = find(root, path, container)
					end
				elseif item["^->"] then --variable divert target -- only in stack?
					table.insert(stack, item["^->"])
				elseif item["VAR?"] then --variable
					table.insert(stack, story.variables[item["VAR?"]])
				elseif item["VAR="] then --variable assignment
					story.variables[item["VAR="]] = pop(stack)
				elseif item["temp="] then --variable assignment //todo: temporary
					story.variables[item["temp="]] = pop(stack)
				end
			end

			if container.is_end() then
				if not container.parent then
					break
				end
				container = container.parent
			end
		end
		return paragraphs, answers
	end

	container = root.attributes["global decl"]
	if container then --init global variables
		story.continue()
	end
	
	container = root
	
	return story
end

return M