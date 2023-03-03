local List = require "ink.list"
local M = {}

local function testflag(value, flag)
	return bit.band(value, flag) == flag
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

local function get_variable(context, container, name)
	local value = context["__globals"][name] 
	if value then return value end

	--check if temp variable
	value = context[container.stitch] and context[container.stitch][name] or nil
	if value then return value end

	value = context["__root"][name] -- temp without stitch
	if value then return value end

	-- check if list item
	local parts = split(name, ".") 
	if #parts == 2 then
		local list = context["__lists"][parts[1]]
		if list[parts[2]] then
			value = List.create()
			value[name] = list[parts[2]]
			return value
		end
	end

	for lname, list in pairs(context["__lists"]) do
		for key, v in pairs(list) do
			if key == name then
				value = List.create()
				value[lname ..".".. key] = v
				return value
			end
		end
	end
	return nil
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

local function find(path, parent, keep_index) 

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

local EXIT = 1
local FUNCTION_RET = 2

local function run(container, output, context, stack)
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
				local value = pop(stack)
				if type(value) == "table" then --list?
					local temp = {}
					for key, _ in pairs(value) do
						local parts = split(key, ".")
						table.insert(temp, parts[#parts])
					end
					value = table.concat(temp, ", ")
				end
				table.insert(output.text, value)

			elseif item == "+" then
				local v1 = pop(stack)
				local v2 = pop(stack)
				table.insert(stack, v1 + v2)
				
			elseif item == "-" then
				local v1 = pop(stack)
				local v2 = pop(stack)
				table.insert(stack, v2 - v1)
				
			elseif item == "*" then
				local value = pop(stack) * pop(stack)
				table.insert(stack, value)
				
			elseif item == "/" then
				local value = 1 / pop(stack) * pop(stack)
				table.insert(stack, value)
				
			elseif item == "==" then
				local v1 = pop(stack)
				local v2 = pop(stack)			
				table.insert(stack,  v1 == v2)

				
			elseif item == ">" then
				local v1 = pop(stack)
				local v2 = pop(stack)
				table.insert(stack, v1 < v2)
				
			elseif item == ">=" then
				local v1 = pop(stack)
				local v2 = pop(stack)
				table.insert(stack, v1 <= v2)
				
			elseif item == "<" then
				local v2 = pop(stack)
				local v1 = pop(stack)
				table.insert(stack,  v1 < v2)
				
			elseif item == "<=" then
				local v2 = pop(stack)
				local v1 = pop(stack)
				table.insert(stack, v1 <= v2)
				
			elseif item == "!=" then
				local v1 = pop(stack)
				local v2 = pop(stack)
				table.insert(stack,  v1 ~= v2)
				
			elseif item == "<>" then -- glue
				glue_mode = true
				glue_paragraph(output)
				
			elseif item == "?" then --containment
				local v1 = pop(stack)
				local v2 = pop(stack)
				local result = true
				for key, _ in pairs(v1) do
					if v2[key] == nil then
						result = false
						break
					end
				end
				table.insert(stack, result)
				
			elseif item == "!?" then -- 
				local v1 = pop(stack)
				local v2 = pop(stack)
				local result = false
				for key, _ in pairs(v1) do
					if v2[key] == nil then
						result = true
						break
					end
				end
				table.insert(stack, result)
				
			elseif item == "nop" then
				--No-operation
			elseif item == "void" then
				table.insert(stack, "")
			elseif item == "->->" then
				break
			elseif item == "~ret" then
				return FUNCTION_RET
			elseif item == "thread" then --thread
				--no idea if this would work
				item = container.next()
				run(find(item["->"], container), output, context, stack)
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
					valid = find(choice.path, container, true).visits == 0
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
					local path = item["var"] and get_variable(context, container, item["->"]) or item["->"]
					local prev = container.name
					container = find(path, container)
					container.visit(prev)
				end

			elseif item["^->"] then --variable divert target -- only in stack?
				table.insert(stack, item["^->"])

			elseif item["VAR?"] then --variable
				table.insert(stack, get_variable(context, container, item["VAR?"]))

			elseif item["VAR="] then --variable assignment
				local name = item["VAR="]
				if not item["re"] or context["__globals"][name] ~= nil then
					context["__globals"][name] = pop(stack)
					if context["__observers"][name] then -- execute observers
						for _, f in ipairs(context["__observers"][name]) do
							f(context["__globals"][name])
						end
					end
				elseif context[container.stitch] and context[container.stitch][name] ~= nil then
					context[container.stitch][name] = pop(stack)
				else
					context["__root"][name] = pop(stack)
				end

			elseif item["temp="] then --temp variable assignment
				local name = item["temp="]
				if context[container.stitch] == nil then
					context[container.stitch] = {}
				end
				context[container.stitch][name] = pop(stack)

			elseif item["CNT?"] then --visits count
				local target = find(item["CNT?"], container, true)
				--pprint(item["CNT?"], target.visits)
				table.insert(stack, target.visits)
				
			elseif item["->t->"] then --tunnel
				local process = M.create(context)
				local tunnel = find(item["->t->"], container)
				process.run(tunnel, output)
	
				while #output.choices > 0 do
					tunnel, output = coroutine.yield(true)
					process.run(tunnel, output)
				end

			elseif item["f()"] then --function
				if FUNCTION_RET ~= run(find(item["f()"], container), output, context, stack) then
					table.insert(stack, "") --if not return in function we miss void on stack
				end
				glue_paragraph(output) -- ??? not sure

			elseif item["list"] then
				table.insert(stack, item["list"])

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

	return EXIT
end


M.create = function(context)
	local process = {
		completed = true
	}
	
	local co = nil
	process.run = function(data, output, stack) --data is container or choice info
		local container = data.is_container and data or find(data.path, data.container)

		--run(container, output, context, stack)

		if process.completed then
			co = coroutine.create(function()
				run(container, output, context, stack)
			end)
			local ok, check = coroutine.resume(co)
			if not ok then
				pprint("ERROR", debug.traceback(co))
			end
			process.completed = check == nil
		else
			local error, check = coroutine.resume(co, container, output)
			process.completed = check == nil
		end
		
	end
	return process
end


return M