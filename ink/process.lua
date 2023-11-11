local List = require "ink.list"
local Utils = require "ink.utils"

local M = {}

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

local function get_variable_ref(context, container, name)
	if context["__globals"][name] ~= nil then 
		return {
			get = function() return context["__globals"][name] end,
			set = function(v) context["__globals"][name] = v end
		}
	end

	if context["__temp"][container.stitch] and context["__temp"][container.stitch][name] ~= nil then
		return {
			get = function() return context["__temp"][container.stitch][name] end,
			set = function(v) context["__temp"][container.stitch][name] = v end
		}
	end
	
	if context["__temp"]["__root"][name] ~= nil then
		return {
			get = function() return context["__temp"]["__root"][name] end,
			set = function(v) context["__temp"]["__root"][name] = v end
		}
	end

	error("No variable " .. name .. " reference found!")
end

local function get_value(variable)
	if type(variable) == "table" and variable.get then
		return variable.get()
	end

	return variable
end

local function get_variable(context, container, name)
	local variable = context["__globals"][name] 
	if variable ~= nil then return get_value(variable) end

	--check if temp variable
	variable = context["__temp"][container.stitch] and context["__temp"][container.stitch][name]
	if variable ~= nil then return get_value(variable) end

	variable = context["__temp"]["__root"][name] -- temp without stitch
	if variable ~= nil then return get_value(variable) end

	-- check if list item
	local value = nil
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

	error("Variable not found " .. name .. " in stitch " .. container.stitch)
	return nil
end

local function pop(stack)
	assert(#stack > 0, "Empty stack!")
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

local function find_tags_in_path(path, parent) -- deprecated, ink 1.0 json v.20, inky 0.12.0
	local tags = {}
	local container = find(path, parent, true)
	for i, item in ipairs(container.content) do
		if type(item) == "table" and item["#"] then
			item["choice"] = true -- mark this tag as "choice tag" to avoid adding in paragraph (?)
			-- possible bad design...
			table.insert(tags, item["#"])
		elseif item == "\n" then
			break --paragraph? stop collecting tags for choice
		end
	end
	return tags
end

local function make_paragraph(output, force)
	local p = {text = table.concat(output.text), tags = output.tags}
	p.text = Utils.trim(p.text)
	output.text = {}
	if force or string.len(p.text) > 0 then --skip empty strings
		output.tags = {}
		if #output.paragraphs > 0 then --check if previous paragraph is empty so we can combine
			local prev = output.paragraphs[#output.paragraphs] 
			if prev.text == "" then
				prev.text = p.text
				for _, tag in ipairs(p.tags) do table.insert(prev.tags, tag) end
				return
			end
		end
		table.insert(output.paragraphs, p)
	end
end


local function exit_string_eval_mode(context, stack)
	if context["__string_eval_mode"] and #context["__string_eval_mode"] > 0 then
		table.insert(stack, table.concat(context["__string_eval_mode"]))
	end
	context["__string_eval_mode"] = nil
end

local END = 1
local DONE = 2
local FUNCTION_RET = 3

local function run(container, output, context, from, stack)
	container.visit(from)
	stack = stack or {}
	while true do
		local item = container.next()

		if type(item) == "string" then
			if item == "\n" then
				if #output.text > 0 and not context["__glue_mode"] then
					make_paragraph(output)
				end

			elseif item:sub(1, 1) == "^" then --string value
				context["__glue_mode"] = false
				if context["__string_eval_mode"] then
					table.insert(context["__string_eval_mode"], item:sub(2))
				else
					table.insert(output.text, item:sub(2))
				end

			elseif item == "done" then
				return DONE
				
			elseif item == "end" then
				if  #output.text > 0 then
					make_paragraph(output)
				end
				return END
				
			elseif item == "ev" then --  start evaluation mode, objects are added to an evaluation stack

				if #output.text == 0 and #output.tags > 0 then --create empty paragraph
					make_paragraph(output, true)
				end
				
				--
			elseif item == "/ev" then 
				--
			elseif item == "str" then 
				context["__string_eval_mode"] = {}
				--
			elseif item == "/str" then 
				exit_string_eval_mode(context, stack)
				--
			elseif item == "pop" then
				pop(stack)

			elseif item == "seq" then
				local value = math.random(0, pop(stack)-1)
				if context["__replay_mode"] then
					value = pop(context["__randoms"])
				else
					table.insert(context["__randoms"], 1, value)
				end
				table.insert(stack, value)

			elseif item == "rnd" then
				local v2 = pop(stack)
				local v1 = pop(stack)
				local value = math.random(v1, v2)
				if context["__replay_mode"] then
					value = pop(context["__randoms"])
				else
					table.insert(context["__randoms"], 1, value)
				end
				table.insert(stack, value)
				
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

				if context["__string_eval_mode"] then
					table.insert(context["__string_eval_mode"], tostring(value))
				else
					table.insert(output.text, value)
				end

			elseif item == "du" then	--duplicate
				local obj = pop(stack)
				table.insert(stack, obj)
				if type(obj) == "table" then
					local copy = List.create(obj)
					table.insert(stack, obj)
				else
					table.insert(stack, obj)
				end

			elseif item == "%" then
				local v2 = pop(stack)
				local v1 = pop(stack)
				table.insert(stack, math.fmod(v1, v2))
				
			elseif item == "visit" then
				table.insert(stack, container.visits - 1)

			elseif item == "MIN" then
				table.insert(stack, math.min(pop(stack), pop(stack)))

			elseif item == "MAX" then
				table.insert(stack, math.max(pop(stack), pop(stack)))

			elseif item == "INT" then
				local value = pop(stack)
				table.insert(stack, value >= 0 and math.floor(value) or math.ceil(value))

			elseif item == "FLOOR" then
				table.insert(stack, math.floor(pop(stack)))

			elseif item == "FLOAT" then
				table.insert(stack, tonumber(pop(stack)))

			elseif item == "LIST_VALUE" then
				local value = 0
				for _, v in pairs(pop(stack)) do
					value = v > value and v or value
				end
				table.insert(stack, value)

			elseif item == "listInt" then
				local list_name = pop(output.text)
				local index = pop(stack)
				local list = context["__lists"][list_name]
				table.insert(stack, list(index))
				
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
				context["__glue_mode"] = true
				glue_paragraph(output)

			elseif item == "&&" then -- logical and
				table.insert(stack, pop(stack) and pop(stack))

			elseif item == "||" then -- logical or
				table.insert(stack, pop(stack) or pop(stack))

			elseif item == "!" then -- unary not
				table.insert(stack, not pop(stack))
				
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
				return DONE
			elseif item == "~ret" then
				return FUNCTION_RET
			elseif item == "thread" then --thread
				--no idea if this would work
				item = container.next()
				run(find(item["->"], container), output, context, container.name, stack)

			elseif item == "#" then -- version 21 tags! ink version 1.1
				exit_string_eval_mode(context, stack)
				output._text = output.text
				output.text = {}
			elseif item == "/#" then
				table.insert(output.tags, table.concat(output.text))
				output.text = output._text
			else
				error("Unknown command " .. item)
			end

		elseif type(item) == "number" then
			table.insert(stack, item)

		elseif type(item) == "boolean" then
			table.insert(stack, item)

		elseif type(item) == "table" then
			if item.is_container then -- inner container, go down hierachy
				item.index = 1
				return run(item, output, context, container.name, stack)

			elseif item["*"] then --choice point
				local choice = {
					tags = output.tags,
					path = item["*"],
					container = container
				}

				output.tags = {}
				
				local flags = item["flg"]
				local valid = true
				if Utils.testflag(flags, 0x1) then -- check condition
					valid = pop(stack)
				end

				choice.text = pop(stack)
				
				if valid and Utils.testflag(flags, 0x10) then --once only
					valid = find(choice.path, container, true).visits == 0
				end
				if valid and Utils.testflag(flags, 0x8) then --is fallback
					valid = #output.choices == 0
					choice.fallback = true
				end
				if valid then
					local tags = find_tags_in_path(choice.path, choice.container) -- deprecated?
					for _, tag in ipairs(tags) do table.insert(choice.tags, tag) end
					
					table.insert(output.choices, choice)
				end
				output.text = {}

			elseif item["#"] then --tag
				if not item["choice"] then
					table.insert(output.tags, item["#"])
				end

			elseif item["->"] then --divert
				if (item["c"] == nil) or (item["c"] and pop(stack)) then --checking condition
					local path = item["var"] and get_variable(context, container, item["->"]) or item["->"]
					return run(find(path, container), output, context,  container.name, stack)
				end

			elseif item["^->"] then --variable divert target -- only in stack?
				table.insert(stack, item["^->"])

			elseif item["VAR?"] then --variable
				table.insert(stack, get_variable(context, container, item["VAR?"]))

			elseif item["^var"] then --variable ref 
				table.insert(stack, get_variable_ref(context, container, item["^var"]))

			elseif item["VAR="] then --variable assignment
				local name = item["VAR="]
				if not item["re"] or context["__globals"][name] ~= nil then
					context["__globals"][name] = pop(stack)
					if context["__observers"][name] then -- execute observers
						for _, f in ipairs(context["__observers"][name]) do
							f(context["__globals"][name])
						end
					end
				elseif context["__temp"][container.stitch] and context["__temp"][container.stitch][name] ~= nil then
					context["__temp"][container.stitch][name] = pop(stack)
				else
					context["__temp"]["__root"][name] = pop(stack)
				end

			elseif item["temp="] then --temp variable assignment
				local name = item["temp="]
				if context["__temp"][container.stitch] == nil then
					context["__temp"][container.stitch] = {}
				end
				if item["re"] and type(context["__temp"][container.stitch][name]) == "table" then
					--reference!
					context["__temp"][container.stitch][name].set(pop(stack))
				else
					context["__temp"][container.stitch][name] = pop(stack)
				end

			elseif item["CNT?"] then --visits count
				local target = find(item["CNT?"], container, true)
				--pprint(item["CNT?"], target.visits)
				table.insert(stack, target.visits)
				
			elseif item["->t->"] then --tunnel
				local process = M.create(context)
				local tunnel = find(item["->t->"], container)
				process.run(tunnel, output, container.name)
	
				while #output.choices > 0 do
					tunnel, output = coroutine.yield(true)
					process.run(tunnel, output)
				end

			elseif item["f()"] then --function
				local fname = item["f()"]
				local fcontainer = find(fname, container)
				if context["__external"][fname] ~= nil then --external function binded
					local args = {}
					for _, param in ipairs(fcontainer.content) do
						if type(param) == "table" and param["temp="] then
							table.insert(args, 1, pop(stack))
						else
							break
						end
					end
					local res = context["__external"][fname](unpack(args)) or ""
					table.insert(stack, res)
				else
					if FUNCTION_RET ~= run(fcontainer, output, context, container.name, stack) then
						table.insert(stack, "") --if no return in function we miss void on stack
					end
				end
				glue_paragraph(output) -- ??? not sure

			elseif item["list"] then
				table.insert(stack, List.create(item["list"]))

			else
				local err = ""
				for key,_ in pairs(item) do
					err = err .. key .. " "
				end
				error("Unknown object " .. err)
			end
		end

		if item == nil then
			if container.parent and not container.is_stitch then
				container = container.parent
			else
				return DONE
			end
			
		end
	end
end


M.create = function(context)
	local process = {
		completed = true
	}
	
	local co = nil
	process.run = function(data, output, from, stack) --data is container or choice info
		context["__string_eval_mode"] = nil
		context["__glue_mode"] = false
		
		local container = data.is_container and data or find(data.path, data.container)
		
		--run(container, output, context, from, stack)

		if process.completed then
			co = coroutine.create(function()
				run(container, output, context, from, stack)
			end)
			local ok, check = coroutine.resume(co)
			if not ok then
				pprint("ERROR", debug.traceback(co))
			end
			process.completed = check == nil
		else
			local ok, check = coroutine.resume(co, container, output)
			process.completed = check == nil
		end

	end

	
	return process
end

return M