-- Replay every shipped puzzle: each move of each line must be legal on its
-- position, the line must end with the player's move, and a "mate" puzzle
-- must end in checkmate. Run from the plugin directory:
--     lua tools/check_puzzles.lua      (or luajit)
-- Exits non-zero on the first bad band, listing the bad puzzles.

package.path = "./?.lua;" .. package.path
local Board   = dofile("board.lua")
local Puzzles = dofile("puzzles.lua")
Puzzles.data_dir = "./"

local function check(p)
    local b = Board:new()
    b:loadFEN(p.fen)
    if #p.moves < 2 or #p.moves % 2 ~= 0 then
        return "odd move count"
    end
    for i, m in ipairs(p.moves) do
        if not b:applyUCI(m) then
            return ("move %d (%s) illegal"):format(i, m)
        end
    end
    if p.themes:find("m", 1, true) and b.status ~= "checkmate" then
        return "mate theme but no checkmate"
    end
    return nil
end

local bad, total = 0, 0
for _, band in ipairs(Puzzles.BANDS) do
    local n = Puzzles.count(band)
    local prev = 0
    for i = 1, n do
        local p = Puzzles.get(band, i)
        total = total + 1
        local err = not p and "unparsable" or check(p)
        if not err then
            local r = Puzzles.RANGES[band]
            if p.rating < r[1] or p.rating >= r[2] then err = "rating out of band" end
            if p.rating < prev then err = "not sorted by rating" end
            prev = p.rating
        end
        if err then
            bad = bad + 1
            print(band, i, p and p.id or "?", err)
        end
    end
    print(("%-8s %d puzzles"):format(band, n))
end
print(("%d puzzles checked, %d bad"):format(total, bad))
os.exit(bad == 0 and 0 or 1)
