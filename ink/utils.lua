local M = {}

M.testflag = function(value, flag)
	return bit.band(value, flag) == flag
end

M.clone = function(obj)
	local copy = {}
	for key, value in pairs(obj) do
		if type(value) == "table" then
			copy[key] = M.clone(value)
		else
			copy[key] = value
		end
	end
	return copy
end

M.trim = function(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end

return M