local Container = require "ink.container"
local Process = require "ink.process" 

local M = {}

M.create = function(s)
	local variables = {__globals = {}, __root = {}}
	local data = json.decode(s)
	local story = {variables = variables["__globals"]}

	local root = Container.create(data.root)
	local choices = {}

	story.continue = function(answer, data)
		data = data or root
		
		if #choices > 0 then
			assert(type(answer) == "number" and answer > 0 and answer <= #choices, "answer required")
			data = Process.find(choices[answer].path, choices[answer].container)
		end
		
		choices = {}

		local output = {
			tags = {},
			text = {},
			paragraphs = {},
			choices = choices
		}

		Process.run(data, output, variables)

		local answers = {}
		for _, choice in ipairs(choices) do
			table.insert(answers, choice.text)
		end
		
		return output.paragraphs, answers
	end

	if root.attributes["global decl"] then --init global variables
		story.continue(0, root.attributes["global decl"])
	end
	
	return story
end

return M