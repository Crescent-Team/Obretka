local luau = require("@lune/luau")
local process = require("@lune/process")
local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local net = require("@lune/net")

local command = process.args[1]
local path = process.args[2]

type BenchCase = {
	preRun: () -> any,
	postRun: (any) -> (),
	run: (any) -> (),
	numberOfCalls: number,
}

local function noOp() end

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

local function requireImpl(thing)
	if type(thing) == "string" then
		return require(thing)
	end
	return require(thing.path)
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

local function newMerged(t1, t2)
	local output = {}

	for key, value in t1 do
		output[key] = value
	end

	for key, value in t2 do
		output[key] = value
	end

	return output
end

local function executeLuauFromSource(
	content: string,
	env: { [string]: any }?,
	optimizationLevel: number?,
	debugLevel: number?
)
	local isOk, returnedValue = pcall(luau.compile, content, {
		coverageLevel = 0,
		optimizationLevel = optimizationLevel or 2,
		debugLevel = debugLevel or 1,
	})

	if not isOk then
		error(`[Obretka] Compilation Error: {returnedValue}`)
	end

	local chunk = luau.load(returnedValue, {
		environment = newMerged(env or {}, {
			require = requireImpl,
			script = script,
		}),
	})

	chunk()
end

if command == "run" then
	local sourceCode = fs.readFile(path)
	executeLuauFromSource(sourceCode)
end

if command == "bench" then
	if not fs.isFile("obretka.d.luau") then
		fs.writeFile(
			"obretka.d.luau",
			[[
		declare bencher: (suite: {[string]: {
		preRun: (() -> any)?,
		postRun: ((any) -> ())?,
		run: (any) -> (),
		numberOfCalls: number,
		}}) -> ()
	]]
		)

	end
	local currentFile = ""
	local function benchmark(case: BenchCase)
		local MeasuredTable = table.create(case.numberOfCalls)
		local MetrixTable = {
			["50th Percentile"] = 0,
			["MAX"] = 0,
			["MIN"] = "",
			["AVERAGE"] = 0,
			["TOTAL"] = 0,
		}

		local ALL_TIME_SUM = 0

		local run = case.run
		local preRun = case.preRun or noOp
		local postRun = case.postRun or noOp

		for i = 1, case.numberOfCalls do
			local val = preRun
			local TIME_START = os.clock()
			run(val)
			local TIME_END = os.clock()
			postRun(val)

			local TIME_DIFFERENCE = (TIME_END - TIME_START) * 1000000

			ALL_TIME_SUM += TIME_DIFFERENCE

			if TIME_DIFFERENCE > MetrixTable.MAX then
				MetrixTable.MAX = TIME_DIFFERENCE
			elseif MetrixTable.MIN == "" or TIME_DIFFERENCE < MetrixTable.MIN then
				MetrixTable.MIN = TIME_DIFFERENCE
			end

			table.insert(MeasuredTable, TIME_DIFFERENCE)
		end

		table.sort(MeasuredTable)

		MetrixTable.TOTAL = ALL_TIME_SUM
		MetrixTable.AVERAGE = (ALL_TIME_SUM / case.numberOfCalls)

		MetrixTable["50th Percentile"] = MeasuredTable[math.floor(#MeasuredTable * 0.5)]

		return MetrixTable
	end

	local function benchSuite(suite: { [string]: BenchCase })
		local function stringWithColor(string, color)
			return `{stdio.color(color)} {string} {stdio.color("reset")}`
		end
		local buff = { stringWithColor(`{currentFile}: \n`, "yellow") }

		for benchCaseName, case in suite do
			table.insert(buff, stringWithColor(`	{benchCaseName}: `, "green"))
			table.insert(buff, stringWithColor(benchmark(case)["50th Percentile"], "cyan"))
		end

		print(table.concat(buff))
	end

	local function run(path)
		for _, itemName in fs.readDir(path) do
			local itemPath = `{path}/{itemName}`
			if fs.isFile(itemPath) and itemName:find(".bench.luau") then
				local sourceCode = fs.readFile(itemPath)
				currentFile = itemPath
				executeLuauFromSource(sourceCode, {
					bencher = benchSuite,
				})
			elseif fs.isDir(itemPath) then
				run(itemPath)
			end
		end
	end

	run(path)
end
