local total = 0

local function shit()
end

for i = 1, 100_000 do
    local start = os.clock()
    shit()
    total += os.clock() - start 
end

print((total / 100_000) * 1_000_000)
error("oops")