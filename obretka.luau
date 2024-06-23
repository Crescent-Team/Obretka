local luau = require("@lune/luau")
local process = require("@lune/process")
local fs = require("@lune/fs")

local path = process.args[1]

local function PathHolder(currentPath)
    return setmetatable({ path = currentPath }, {
        __index = function(self, index)
            if index then
                if index == "Parent" then
                    return PathHolder(`{currentPath}../}`)
                else
                    return PathHolder(`{string.gsub(currentPath, "}", "")}{index}/`)
                end
            else
                return self
            end
        end,
    })
end

local script = setmetatable({ path = "" }, {
    __index = function(self, index)
        if index == "" then
            return script
        end

        if index ~= "Parent" then
            return PathHolder(`{index}/`)
        end

        if index == "Parent" then
            return PathHolder("")
        end

        return script
    end,
})

local function requireImpl(thing)
    if type(thing) == "string" then
        return require(thing)
    end
    return require(thing.path)
end


local content = fs.readFile(path)

local bytecode = luau.compile(content, {
    coverageLevel = 0,
    optimizationLevel = 2, 
    debugLevel = 1,
})

local chunk = luau.load(bytecode, {
    environment = {
        require = requireImpl,
        script = script
    }
})

chunk()