local Container = require "ink.container"
local Process = require "ink.process"
local List = require "ink.list"
local Utils = require "ink.utils"

local M = {}

M.create = function(s)
	local context = {
		__globals = {}, 
		__temp = {__root = {}},
		__lists = {},
		__observers = {},
		__external = {},
		__randoms = {} -- to restore session with the same random values
	}

	math.randomseed(os.time())

	local state = { -- track user input and random values to save\load story
		input = {}, 
		randoms = context["__randoms"]
	}
	
	local data
	local status, err = pcall(function()
		data = json.decode(s, {decode_null_as_userdata = true})
	end) 

	if not status then
		error("JSON read error, make sure it's utf-8.\n" .. err)
	end
	
	local story = {variables = context["__globals"]}

	local root = Container.create(data.root)
	local flows = {}

	local flow = {
		name = "__default",
		choices = {},
		process = Process.create(context)
	}

	flows["__default"] = flow
	
	story.continue = function(answer, data)
		data = data or root
		
		if #flow.choices > 0 then
			table.insert(state.input, {index = answer, text = flow.choices[answer].text})
			assert(type(answer) == "number" and answer > 0 and answer <= #flow.choices, "Answer required.")
			data = flow.choices[answer]
		end
		
		flow.choices = {}

		local output = {
			tags = {},
			text = {},
			paragraphs = {},
			choices = flow.choices
		}

		flow.process.run(data, output)

		local answers = {}
		local paragraphs = output.paragraphs
	
		if #flow.choices == 1 and flow.choices[1].fallback then
			paragraphs, answers = story.continue(1)
			for i, p in ipairs(output.paragraphs) do
				table.insert(paragraphs, i, p)
			end
			
		elseif #flow.choices > 0 then
			if flow.choices[1].fallback then
				table.remove(flow.choices, 1)
			end
			for i, choice in ipairs(flow.choices) do
				if choice.fallback then
					table.remove(flow.choices, i)
				else
					table.insert(answers, {text = choice.text, tags = choice.tags})
				end
			end
		end

		return paragraphs, answers
	end

	if data["listDefs"] then --init lists
		for name, values in pairs(data["listDefs"]) do
			context["__lists"][name] = List.create(values)
		end
	end

	if root.attributes["global decl"] then --init global variables
		story.continue(0, root.attributes["global decl"])
	end

	story.add_observer = function(var, f)
		if context["__observers"][var] == nil then
			context["__observers"][var] = {}
		end
		table.insert(context["__observers"][var], f)
	end
	
	story.remove_observer = function(var, f)
		if not context["__observers"][var] then return end

		if f == nil then 
			context["__observers"][var] = nil
			return
		end
		
		for i, observer in ipairs(context["__observers"][var]) do
			if observer == f then
				table.remove(context["__observers"][var], i)
				break
			end
		end
		
	end

	story.assign_value = function(name, value)
		context["__globals"][name] = value --possible issue with lists, see deserialize
		if context["__observers"][name] then -- execute observers
			for _, f in ipairs(context["__observers"][name]) do
				f(context["__globals"][name])
			end
		end
		table.insert(state.input, {name = name, value = value})
	end

	story.bind = function(name, f)
		context["__external"][name] = f
	end

	story.jump = function(path)
		flow.choices = {}
		table.insert(state.input, {jump = path})
		return story.continue(0, {path = path, container = root})
	end

	story.switch_flow = function(name)
		name = name or "__default"
		if flow.name == name then return end
		flow = flows[name]
		
		if flow == nil then
			flow = {
				name = name,
				choices = {},
				process = Process.create(context)
			}
			flows[name] = flow
		end
		table.insert(state.input, {flow = flow.name})
	end

	story.restore = function(history, with_bindings, ignore_errors)
		local error_idx = 0
		local observers = context["__observers"]
		local external = context["__external"]
		context = {
			__globals = {}, 
			__temp = {__root = {}},
			__lists = context["__lists"],
			__external = with_bindings and context["__external"] or {},
			__observers = {},
			__randoms = Utils.clone(history.randoms),
			__randoms__ = {},
			__replay_mode = true
		}
		story.variables = context["__globals"]

		flow = {
			name = "__default",
			choices = {},
			process = Process.create(context)
		}

		flows = {__default = flow}
		root = Container.create(data.root)


		if root.attributes["global decl"] then --init global variables
			story.continue(0, root.attributes["global decl"])
		end

		local paragraphs, answers = story.continue()

		local compare = function(s1, s2)
			--TODO fuzzy logic here?
			return Utils.trim(s1) == Utils.trim(s2)
		end

		for idx, input in ipairs(history.input) do
			if type(input) == "table" then 
				if input.flow then
					story.switch_flow(input.flow)
				elseif input.jump then
					story.jump(input.jump)
				elseif input.name then --manual change of variable
					context["__globals"][input.name] = input.value
				else
					if flow.choices[input.index] and compare(flow.choices[input.index].text, input.text) then
						-- all is good!
						paragraphs, answers = story.continue(input.index)
					else
						--story data has changed, we can't just rely on answer index
						--checking text as well (TODO: fuzzy logic?)
						local is_found = false
						for i, choice in ipairs(flow.choices) do
							if compare(choice.text, input.text) then
								paragraphs, answers = story.continue(i)
								is_found = true
								break
							end
						end
						if not is_found then
							if ignore_errors then 
								error_idx = idx
								break 
							end
							--pprint(paragraphs, answers)
							pprint("'".. input.text .. "' choice is not found.")
							error("Can't restore story, incompatible data?")
						end
					end
				end
			else --obsolete, for compatibility only
				local status, err = pcall(function ()
					paragraphs, answers = story.continue(input)
				end)
				if not status then --saved state and story are not compatible
					pprint(err)
					error("Can't restore story, incompatible data?")
				end
			end
		end

		if error_idx > 0 then
			state = {input = {}, randoms = context["__randoms__"]}

			for i = 1, error_idx - 1 do
				table.insert(state.input, history.input[i])
			end

		else
			state = {
				input = Utils.clone(history.input),
				randoms = Utils.clone(history.randoms)
			}
		end

		context["__randoms"] = state.randoms
		context["__replay_mode"] = nil
		context["__observers"] = observers
		context["__external"] = external
		for name, functions in pairs(observers) do
			for _, f in ipairs(functions) do
				f(story.variables[name])
			end
		end

		return paragraphs, answers
	end

	story.get_state = function()
		return {
			input = Utils.clone(state.input),
			randoms = Utils.clone(state.randoms)
		}
	end

	story.eval = function(expression)

		for name, value in pairs(story.variables) do
			expression = expression:gsub("([^%w_])".. name .. "([^%w_])", "%1".. tostring(value) .. "%2")
			expression = expression:gsub("([^%w_])".. name .. "$", "%1".. tostring(value))
			expression = expression:gsub("^".. name .. "([^%w_])", tostring(value) .. "%1")
		end

		return loadstring("return " .. expression)()
	end

	story.serialize = function()
		local data = {
			globals = Utils.clone(context["__globals"]),
			root = {}
		}
		
		Container.serialize(root, data.root)
		return data
	end

	story.deserialize = function(data, path, reset_observers)
		if reset_observers then
			context["__observers"] = {}
		end
		for key, value in pairs(data.globals) do
			if type(value) == "table" then
				value = List.create(value)
			end
			if context["__observers"][key] then
				story.assign_value(key, value)
			else
				context["__globals"][key] = value
			end
		end
		Container.deserialize(root, data.root)
		flow = {
			name = "__default",
			choices = {},
			process = Process.create(context)
		}

		flows = {__default = flow}
		return story.jump(path)
	end
	
	return story
end

return M