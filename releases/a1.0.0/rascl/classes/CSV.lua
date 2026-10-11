-- csvdb.lua

local CSV = {}
local delim = "÷"
--local delim = "\247"
----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

local function split_csv_line(line)
    local result = {}
    local value = ""

    local i = 1
    local in_quotes = false

    while i <= #line do
        local c = line:sub(i, i)

        if c == '"' then
            if in_quotes and line:sub(i + 1, i + 1) == '"' then
                value = value .. '"'
                i = i + 1
            else
                in_quotes = not in_quotes
            end

        elseif c == delim and not in_quotes then
            table.insert(result, value)
            value = ""

        else
            value = value .. c
        end

        i = i + 1
    end

    table.insert(result, value)

    return result
end

local function escape_csv(value)
    value = tostring(value or "")

    if value:find('[,"\n]') then
        value = '"' .. value:gsub('"', '""') .. '"'
    end

    return value
end

local function table_path(name)
    return name .. ".csv"
end

local function load_table(name)
    local path = table_path(name)

    local file = io.open(path, "r")
    if not file then
        return nil, "table does not exist"
    end

    local header_line = file:read("*l")
    if not header_line then
        file:close()
        return {columns = {}, rows = {}}
    end

    local columns = split_csv_line(header_line)
    local rows = {}

    for line in file:lines() do
        local values = split_csv_line(line)
        local row = {}

        for i, col in ipairs(columns) do
            row[col] = values[i] or ""
        end

        table.insert(rows, row)
    end

    file:close()

    return {
        columns = columns,
        rows = rows
    }
end

local function save_table(name, dbtable)
    local file = assert(io.open(table_path(name), "w"))

    local header = {}
    for _, col in ipairs(dbtable.columns) do
        table.insert(header, escape_csv(col))
    end

    file:write(table.concat(header, delim))
    file:write("\n")

    for _, row in ipairs(dbtable.rows) do
        local values = {}

        for _, col in ipairs(dbtable.columns) do
            table.insert(values, escape_csv(row[col]))
        end

        file:write(table.concat(values, delim))
        file:write("\n")
    end

    file:close()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function CSV.create_table(name, columns)
    local file = io.open(table_path(name), "r")

    if file then
        file:close()
        return false, "table already exists"
    end

    save_table(name, {
        columns = columns,
        rows = {}
    })

    return true
end

function CSV.delete_table(name)
    return os.remove(table_path(name))
end

function CSV.insert(name, row)
    local tbl, err = load_table(name)
    if not tbl then
        return false, err
    end

    table.insert(tbl.rows, row)

    save_table(name, tbl)

    return true
end

function CSV.select(name, filter)
    local tbl, err = load_table(name)
    if not tbl then
        return nil, err
    end

    local results = {}

    for _, row in ipairs(tbl.rows) do
        if not filter or filter(row) then
            table.insert(results, row)
        end
    end

    return results
end

function CSV.update(name, filter, updater)
    local tbl, err = load_table(name)
    if not tbl then
        return false, err
    end

    local count = 0

    for _, row in ipairs(tbl.rows) do
        if filter(row) then
            updater(row)
            count = count + 1
        end
    end

    save_table(name, tbl)

    return count
end

function CSV.delete(name, filter)
    local tbl, err = load_table(name)
    if not tbl then
        return false, err
    end

    local kept = {}
    local deleted = 0

    for _, row in ipairs(tbl.rows) do
        if filter(row) then
            deleted = deleted + 1
        else
            table.insert(kept, row)
        end
    end

    tbl.rows = kept

    save_table(name, tbl)

    return deleted
end

return CSV
