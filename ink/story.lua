local Container = require "ink.container"
local Process = require "ink.process"
local List = require "ink.list"

local M = {}

M.create = function(s)
	local context = {
		__globals = {}, 
		__root = {},
		__lists = {},
		__observers = {}
	}

	math.randomseed(os.time())
	
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
					table.insert(answers, choice.text)
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

	story.load = function(state)
		assert(false, "not implemeted")
	end

	story.save = function()
		local state = {context = {}}
		for key, value in pairs(context) do
			if key ~= "__observers" and  key ~= "__lists" then
				state.context[key] = value
			end
		end

		state.root = root.get_state()

		state.choices = {}
		for _, choice in ipairs(choices) do
			table.insert(state.choices, {
				path = choice.path,
				name = choice.container.name
			})
		end
		
		return state
	end
	
	return story
end

return M