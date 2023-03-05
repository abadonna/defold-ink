local Container = require "ink.container"
local Process = require "ink.process"
local List = require "ink.list"

local M = {}

M.create = function(s)
	local context = {
		__globals = {}, 
		__root = {},
		__lists = {},
		__observers = {},
		__randoms = {} -- to restore session with the same random values
	}

	math.randomseed(os.time())

	local state = { -- track user input and random values to save\load story
		answers = {}, 
		randoms = context["__randoms"]
	}
	
	local data
	local status, err = pcall(function()
		data = json.decode(s)
	end) 

	if not status then
		error("JSON read error, make sure it's utf-8.\n" .. err)
	end
	
	local story = {variables = context["__globals"]}

	local root = Container.create(data.root)
	local choices = {}

	local process = Process.create(context)
	
	story.continue = function(answer, data)
		data = data or root
		
		if #choices > 0 then
			table.insert(state.answers, answer)
			assert(type(answer) == "number" and answer > 0 and answer <= #choices, "answer required")
			data = choices[answer]
		end
		
		choices = {}

		local output = {
			tags = {},
			text = {},
			paragraphs = {},
			choices = choices
		}

		process.run(data, output)

		local answers = {}
		local paragraphs = output.paragraphs
	
		if #choices == 1 and choices[1].fallback then
			paragraphs, answers = story.continue(1)
			for i, p in ipairs(output.paragraphs) do
				table.insert(paragraphs, i, p)
			end
			
		elseif #choices > 0 then
			if choices[1].fallback then
				table.remove(choices, 1)
			end
			for i, choice in ipairs(choices) do
				if choice.fallback then
					table.remove(choices, i)
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
		context["__globals"][name] = value
		if context["__observers"][name] then -- execute observers
			for _, f in ipairs(context["__observers"][name]) do
				f(context["__globals"][name])
			end
		end
	end

	story.bind = function(name, f)
		assert(false, "not implemeted")
	end

	story.jump = function(path)
		assert(false, "not implemeted")
	end

	story.load = function(saved)
		local observers = context["__observers"]
		context = {
			__globals = {}, 
			__root = {},
			__lists = context["__lists"],
			__observers = {},
			__randoms = {unpack(saved.randoms)},
			__restore_mode = true
		}
		story.variables = context["__globals"]

		choices = {}
		process = Process.create(context)
		root = Container.create(data.root)

		if root.attributes["global decl"] then --init global variables
			story.continue(0, root.attributes["global decl"])
		end

		local paragraphs, answers = story.continue()

		for _, answer in ipairs(saved.answers) do
			paragraphs, answers = story.continue(answer)
		end

		state = {
			answers = {unpack(saved.answers)},
			randoms = {unpack(saved.randoms)}
		}

		context["__randoms"] = state.randoms
		context["__restore_mode"] = nil
		context["__observers"] = observers
		for name, functions in pairs(observers) do
			for _, f in ipairs(functions) do
				f(story.variables[name])
			end
		end

		return paragraphs, answers
	end

	story.save = function()
		return {
			answers = {unpack(state.answers)},
			randoms = {unpack(state.randoms)}
		}
	end

	story.eval = function(expression)

		for name, value in pairs(story.variables) do
			expression = expression:gsub("([^%w_])".. name .. "([^%w_])", "%1".. tostring(value) .. "%2")
			expression = expression:gsub("([^%w_])".. name .. "$", "%1".. tostring(value))
			expression = expression:gsub("^".. name .. "([^%w_])", tostring(value) .. "%1")
		end

		return load("return " .. expression)()
	end
	
	return story
end

return M