local M = {}

local function testflag(value, flag)
	return bit.band(value, flag) == flag
end

local function get_variable(variables, container, name)
	local value = variables["__globals"][name] 
	if value then return value end

	value = variables[container.stitch][name]
	if value then return value end

	value = variables["__root"][name]
	return value
end

local function pop(stack)
	assert(#stack > 0, "empty stack!")
	local item = stack[#stack]
	table.remove(stack, #stack)
	return item
end

local function glue_paragraph(output)
	if #output.text == 0 and #output.paragraphs > 0 then
		local p = pop(output.paragraphs)
		table.insert(output.text, p.text)
		for i, tag in ipairs(p.tags) do
			table.insert(output.tags, i, tag)
		end
	end
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

M.find = function(path, parent, keep_index) 

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
					if type(item) == "table" and item.is_container and item.attributes["#n"] == part then
						if not keep_index then
							container.index = i + 1
						end
						container = item
					end
				end
			end
		end
	end	

	if not keep_index then
		container.index = 1
	end
	return container
end

M.run = function(container, output, variables, stack)
	local string_eval_mode = false
	local glue_mode = false
	container.visit("")
	stack = stack or {}
	while true do
		local item = container.next()

		if type(item) == "string" then
			if item == "\n" then
				if not glue_mode then
					local p = {text = table.concat(output.text), tags = output.tags}
					table.insert(output.paragraphs, p)
					output.text = {}
					output.tags = {}
				end

			elseif item:sub(1, 1) == "^" then --string value
				glue_mode = false
				if string_eval_mode then
					table.insert(stack, item:sub(2))
				else
					table.insert(output.text, item:sub(2))
				end

			elseif item == "done" then
				break
			elseif item == "end" then
				break
			elseif item == "ev" then --  start evaluation mode, objects are added to an evaluation stack
				--
			elseif item == "/ev" then 
				--
			elseif item == "str" then 
				string_eval_mode = true
				--
			elseif item == "/str" then 
				string_eval_mode = false
				--
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
			elseif item == "<>" then -- glue
				glue_mode = true
				glue_paragraph(output)

			elseif item == "nop" then
				--No-operation
			elseif item == "void" then
				--
			elseif item == "->->" then
				break
			elseif item == "~ret" then
				glue_paragraph(output) -- ??? not sure
				break
			else
				assert(false, "unkown command " .. item)
			end

		elseif type(item) == "number" then
			table.insert(stack, item)

		elseif type(item) == "table" then
			if item.is_container then -- inner container, go down hierachy
				item.index = 1
				item.visit(container.name)
				container = item

			elseif item["*"] then --choice point
				local choice = {
					text = "",
					path = item["*"],
					container = container
				}
				local flags = item["flg"]
				local valid = true
				if testflag(flags, 0x1) then -- check condition
					valid = pop(stack)
				end

				if testflag(flags, 0x4) then -- read choice-only content
					choice.text = pop(stack)
				end
				
				if testflag(flags, 0x2) then -- read start content
					choice.text = pop(stack) .. choice.text
				end
				
				if valid and testflag(flags, 0x10) then --once only
					valid = M.find(choice.path, container, true).visits == 0
				end
				if valid and testflag(flags, 0x8) then --is fallback
					valid = #output.choices == 0
					choice.fallback = true
				end
				if valid then
					table.insert(output.choices, choice)
				end
				output.text = {}

			elseif item["#"] then --tag
				table.insert(output.tags, item["#"])

			elseif item["->"] then --divert
				if (item["c"] == nil) or (item["c"] and pop(stack)) then --checking condition
					local path = item["var"] and get_variable(variables, container, item["->"]) or item["->"]
					local prev = container.name
					container = M.find(path, container)
					container.visit(prev)
				end

			elseif item["^->"] then --variable divert target -- only in stack?
				table.insert(stack, item["^->"])

			elseif item["VAR?"] then --variable
				table.insert(stack, get_variable(variables, container, item["VAR?"]))

			elseif item["VAR="] then --variable assignment
				local name = item["VAR="]
				if not item["re"] or variables["__globals"][name] ~= nil then
					variables["__globals"][name] = pop(stack)
				elseif variables[container.stitch] and variables[container.stitch][name] ~= nil then
					variables[container.stitch][name] = pop(stack)
				else
					variables["__root"][name] = pop(stack)
				end

			elseif item["temp="] then --temp variable assignment
				local name = item["temp="]
				if variables[container.stitch] == nil then
					variables[container.stitch] = {}
				end
				variables[container.stitch][name] = pop(stack)

			elseif item["CNT?"] then --visits count
				local target = M.find(item["CNT?"], container, true)
				--pprint(item["CNT?"], target.visits)
				table.insert(stack, target.visits)
				
			elseif item["->t->"] then --tunnel
				M.run(M.find(item["->t->"], container), output, variables)

			elseif item["f()"] then --function
				M.run(M.find(item["f()"], container), output, variables, stack)
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