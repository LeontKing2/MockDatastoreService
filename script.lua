-- Mock DataStoreService
-- Crazyman32
-- August 20, 2014
-- Abhidjt, 1st January, 2025.
local DataStoreService = {}
local API = {}
local MT = {}

local realDataStoreService = game:GetService("DataStoreService")
local allStores = {}

if game.Players.LocalPlayer then
	warn("Mocked DataStoreService is functioning on the client: The real DataStoreService will not work on the client")
end

-- API:
function API:GetDataStore(name, scope)
	assert(type(name) == "string", "DataStore name must be a string; got " .. type(name))
	assert(type(scope) == "string" or scope == nil, "DataStore scope must be a string; got " .. type(scope))
	scope = scope or "global"

	local store = allStores[scope] and allStores[scope][name]
	if store then return store end
	
	local data = {}
	local updateListeners = {}

	local function triggerUpdates(k, v)
		if updateListeners[k] then
			for _, f in ipairs(updateListeners[k]) do
				spawn(function() f(v) end)
			end
		end
	end

	local d = {
		SetAsync = function(k, v)
			assert(v ~= nil, "Value cannot be nil")
			data[k] = v
			triggerUpdates(k, v)
		end,
		UpdateAsync = function(k, func)
			local v = func(data[k])
			assert(v ~= nil, "Value cannot be nil")
			data[k] = v
			triggerUpdates(k, v)
		end,
		GetAsync = function(k) return data[k] end,
		IncrementAsync = function(k, delta)
			delta = delta or 1
			assert(type(delta) == "number", "Can only increment numbers")
			d:UpdateAsync(k, function(num)
				assert(type(num) == "number" or num == nil, "Can only increment numbers")
				return (num or 0) + delta
			end)
		end,
		OnUpdate = function(k, onUpdateFunc)
			assert(type(onUpdateFunc) == "function", "Update function argument must be a function")
			updateListeners[k] = updateListeners[k] or {}
			table.insert(updateListeners[k], onUpdateFunc)
		end,
	}

	allStores[scope] = allStores[scope] or {}
	allStores[scope][name] = d

	return d
end

function API:GetGlobalDataStore()
	return self:GetDataStore("global", "global")
end

function API:GetOrderedDataStore(name, scope)
	local dataStore = self:GetDataStore(name, scope)
	local allData = {}

	local d = {
		GetAsync = function(k) return dataStore:GetAsync(k) end,
		SetAsync = function(k, v)
			assert(type(v) == "number", "Value must be a number")
			dataStore:SetAsync(k, v)
			allData[k] = v
		end,
		UpdateAsync = function(k, func)
			dataStore:UpdateAsync(k, function(oldValue)
				local v = func(oldValue)
				assert(type(v) == "number", "Value must be a number")
				allData[k] = v
				return v
			end)
		end,
		IncrementAsync = function(k, delta)
			dataStore:IncrementAsync(k, delta)
			allData[k] = (allData[k] or 0) + delta
		end,
		GetSortedAsync = function(isAscending, pageSize, minValue, maxValue)
			assert(type(pageSize) == "number" and pageSize > 0, "PageSize must be a positive integer")
			assert(not minValue or type(minValue) == "number", "MinValue must be a number")
			assert(not maxValue or type(maxValue) == "number", "MaxValue must be a number")

			if minValue and maxValue then
				assert(minValue <= maxValue, "MinValue must be less than or equal to MaxValue")
			end

			local data = {}
			for k, v in pairs(allData) do
				if (not minValue or v >= minValue) and (not maxValue or v <= maxValue) then
					table.insert(data, {key = k, value = v})
				end
			end

			table.sort(data, isAscending and function(a, b) return a.value < b.value end or function(a, b) return a.value > b.value end)

			pageSize = math.floor(pageSize)
			local pages = { IsFinished = false }
			for i, v in ipairs(data) do
				local pageNum = math.ceil(i / pageSize)
				local page = pages[pageNum] or {}
				pages[pageNum] = page
				page[((i - 1) % pageSize) + 1] = v
			end

			local currentPage = 1
			function pages:GetCurrentPage() return self[currentPage] end
			function pages:AdvanceToNextPageAsync()
				if currentPage < #pages then
					currentPage = currentPage + 1
				end
				self.IsFinished = currentPage >= #pages
			end

			return pages
		end,
	}

	return d
end

-- Metatable:
MT.__metatable = true
MT.__index = function(tbl, index)
	return API[index] or realDataStoreService[index]
end
MT.__newindex = function() error("Cannot edit MockDataStoreService") end
setmetatable(DataStoreService, MT)

return DataStoreService
