local Container = require "ink.container"
local Process = require "ink.process" 

local M = {}

M.create = function(s)
	local variables = {
		__globals = {}, 
		__root = {}
	}
	
	local data = json.decode(s)
	local story = {variables = variables["__globals"]}

	local root = Container.create(data.root)
	local choices = {}

	local process = Process.create(variables)
	
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

	if root.attributes["global decl"] then --init global variables
		story.continue(0, root.attributes["global decl"])
	end
	
	return story
end

return M