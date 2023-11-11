local M = {}

local function smallest(list)
	local res = math.huge
	for _, value in pairs(list) do
		res = math.min(res, value)
	end
	return res
end

local function largest(list)
	local res = 0
	for _, value in pairs(list) do
		res = math.max(res, value)
	end
	return res
end

local mt = {

	__add = function(a,b)
		local res = M.create(a)
		for key, value in pairs(b) do
			res[key] = value
		end
		return res
	end,

	__sub = function(a,b)
		local res = M.create(a)
		for key, _ in pairs(b) do
			res[key] = nil
		end
		return res
	end,

	__eq = function(a,b)
		local res = true
		for key, _ in pairs(a) do
			if b[key] == nil then
				return false
			end
		end
		for key, _ in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end,
	
	__lt = function(a,b) --  the smallest value in B is bigger than the largest values in A
		return largest(a) < smallest(b)
	end,

	__le = function(a,b) --  the smallest value in B is at least the smallest value in A, and the largest value in B is at least the largest value in A
		return (smallest(b) >= smallest(a)) and (largest(b) >= largest(a))
	end,

	__call = function(list, index)
		for key, value in pairs(list) do
			if value == index then
				return key
			end
		end
	end
}

M.create = function(data)
	local list = {}
	if data then
		for key, value in pairs(data) do
			list[key] = value
		end
	end
	setmetatable(list, mt)
	return list
end

return M