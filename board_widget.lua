-- ---------------------------------------------------------------------------
-- PuzzleBoardWidget — renders the 8×8 board for the chess puzzles plugin.
-- Vendored from chesscourse.koplugin/board_widget.lua; adds the hint marks
-- (the squares of the piece to move and of its target, inverted) and the wrong-move
-- mark (a cross on the square the wrong move went to).
-- Supports flipping via the `flipped` field.
-- ---------------------------------------------------------------------------

local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawDiagonal   = gwb.drawDiagonalLine
-- Plugin-local copy: chess and chesscourse ship a "chess_pieces" too.
local ChessPieces    = lrequire("chess_pieces")

local Screen = Device.screen

local C_LIGHT_SQ = Blitbuffer.COLOR_GRAY_E
local C_DARK_SQ  = Blitbuffer.COLOR_GRAY_9
local C_SEL      = Blitbuffer.COLOR_LIGHT_GRAY
local C_LASTMOV  = Blitbuffer.COLOR_GRAY_B
local C_DOT      = Blitbuffer.COLOR_GRAY_3
local C_LINE     = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- PuzzleBoardWidget
-- ---------------------------------------------------------------------------

local PuzzleBoardWidget = GridWidgetBase:extend{
    board        = nil,
    size_ratio   = 0.80,
    onCellAction = nil,
    cols         = 8,
    rows         = 8,
    -- last_move: {fr,fc,tr,tc} or nil
    last_move    = nil,
    -- flipped: true → black's perspective
    flipped      = false,
    -- marks: { {r, c}, ... } squares inverted by a hint
    marks        = nil,
    -- wrong: {fr,fc,tr,tc} the wrong move to cross out, or nil
    wrong        = nil,
}

function PuzzleBoardWidget:init()
    GridWidgetBase.init(self)

    -- Rank/file labels get their own margin outside the 8x8 grid (left for
    -- rank numbers, bottom for file letters) so they never sit on top of
    -- piece art. The grid shrinks to fit; self.size (the widget's overall
    -- footprint, used by the screen layout) is unchanged. Same approach as
    -- chess.koplugin's board widget.
    local approx_cell = self.size / 8
    -- Font:getFace scales its size by DPI; this one is derived from pixels.
    local label_size  = math.max(6, math.floor(approx_cell * 0.22 / (Screen:scaleBySize(1000) / 1000)))
    self.label_face   = Font:getFace("smallinfofont", label_size)

    -- The margin must fit both the widest rank digit (left) and the
    -- tallest file letter, ascender to descender (bottom). File letters
    -- share one baseline (label_ascent below the grid) so "g" and "b"
    -- line up instead of each being centred on its own ink box.
    local pad    = math.floor(approx_cell * 0.15)
    local digits = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.label_face, "8", true, false)
    local files  = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.label_face, "abcdefgh", true, false)
    self.label_ascent = files.y_top
    self.label_margin = math.max(digits.x, files.y_top + files.y_bottom) + pad

    self.grid_size = self.size - self.label_margin
    self.cell_w    = self.grid_size / 8
    self.cell_h    = self.grid_size / 8
end

function PuzzleBoardWidget:onCellTap(v_row, v_col)
    local br = self.flipped and (9 - v_row) or v_row
    local bc = self.flipped and (9 - v_col) or v_col
    if self.onCellAction then self.onCellAction(br, bc) end
end

-- Override: the tappable grid is offset by label_margin from the widget's
-- origin (paint_rect still covers the whole widget so refresh() repaints
-- the labels too).
function PuzzleBoardWidget:getCellFromPoint(px, py)
    local rect = self.paint_rect
    if not rect then return nil end
    local local_x = px - (rect.x + self.label_margin)
    local local_y = py - rect.y
    if local_x < 0 or local_y < 0 or local_x > self.grid_size or local_y > self.grid_size then
        return nil
    end
    local col = math.min(8, math.floor(local_x / self.cell_w) + 1)
    local row = math.min(8, math.floor(local_y / self.cell_h) + 1)
    return row, col
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function PuzzleBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local n     = 8
    local cw    = self.cell_w
    local ch    = self.cell_h
    local flip  = self.flipped
    local S     = self.grid_size
    local margin = self.label_margin
    local x0    = x
    x = x + margin

    -- Selected square and valid targets
    local sel_r, sel_c
    if board.selected then
        sel_r = board.selected[1]
        sel_c = board.selected[2]
    end
    local marked = {}
    for _, mk in ipairs(self.marks or {}) do marked[mk[1] * 10 + mk[2]] = true end
    local move_targets = {}
    if sel_r then
        local moves = board:getMovesForSquare(sel_r, sel_c)
        for _, m in ipairs(moves) do
            move_targets[m.tr * 10 + m.tc] = true
        end
    end

    -- Last move
    local lm         = self.last_move
    local lm_key_fr  = lm and (lm.fr * 10 + lm.fc) or nil
    local lm_key_to  = lm and (lm.tr * 10 + lm.tc) or nil

    for v_row = 1, n do
        for v_col = 1, n do
            local br  = flip and (9 - v_row) or v_row
            local bc  = flip and (9 - v_col) or v_col
            local px  = x + math.floor((v_col - 1) * cw)
            local py  = y + math.floor((v_row - 1) * ch)
            local pcw = math.ceil(cw)
            local pch = math.ceil(ch)
            local key = br * 10 + bc

            -- Background
            local dark = (br + bc) % 2 == 1
            local bg
            if sel_r and br == sel_r and bc == sel_c then
                bg = C_SEL
            elseif lm and (key == lm_key_fr or key == lm_key_to) then
                bg = C_LASTMOV
            else
                bg = dark and C_DARK_SQ or C_LIGHT_SQ
            end
            bb:paintRect(px, py, pcw, pch, bg)

            -- Piece
            local v = board.sq[br][bc]
            if v ~= 0 then
                ChessPieces.drawPiece(bb, px, py, pcw, pch, v)
            end

            -- Valid-move dot
            if move_targets[key] then
                local dot = math.max(3, math.floor(math.min(cw, ch) * 0.18))
                bb:paintRect(px + math.floor(cw / 2) - math.floor(dot / 2),
                             py + math.floor(ch / 2) - math.floor(dot / 2),
                             dot, dot, C_DOT)
            end

            -- Hint: the whole square inverted. The piece art sits in its
            -- own framed box, so a frame would look like every other piece.
            if marked[key] then
                bb:invertRect(px, py, pcw, pch)
            end
        end
    end

    -- The wrong-move cross, over the pieces.
    local function cellOrigin(br, bc)
        local v_row = flip and (9 - br) or br
        local v_col = flip and (9 - bc) or bc
        return x + math.floor((v_col - 1) * cw), y + math.floor((v_row - 1) * ch)
    end
    local mark_w = math.max(3, math.floor(math.min(cw, ch) * 0.09))
    local wr = self.wrong
    if wr then
        local px, py = cellOrigin(wr.tr, wr.tc)
        local inset = math.floor(math.min(cw, ch) * 0.12)
        local len = math.floor(math.min(cw, ch)) - 2 * inset - mark_w
        for o = 0, 1 do
            -- White under black so the cross reads on dark squares and pieces.
            local col = o == 0 and Blitbuffer.COLOR_WHITE or C_LINE
            local t = o == 0 and mark_w + 2 or mark_w
            local d = o == 0 and -1 or 0
            drawDiagonal(bb, px + inset + d, py + inset + d, len, 1, 1, col, t)
            drawDiagonal(bb, px + inset + d, py + inset + len + d, len, 1, -1, col, t)
        end
    end

    -- Grid lines
    local thick = math.max(2, math.floor(math.min(cw, ch) * 0.06))
    for i = 0, n do
        local lw    = (i == 0 or i == n) and thick or 1
        local color = (i == 0 or i == n) and C_LINE or Blitbuffer.COLOR_GRAY_9
        -- Keep the outer frame inside the grid so it doesn't bleed into
        -- the label margin.
        local off   = (i == n) and lw or 0
        bb:paintRect(x + math.floor(i * cw) - off, y,  lw, S, color)
        bb:paintRect(x, y + math.floor(i * ch) - off,  S, lw, color)
    end

    -- Rank / file labels, drawn outside the grid in the reserved margin
    local file_letters = {"a","b","c","d","e","f","g","h"}
    local label_face   = self.label_face
    for i = 1, n do
        -- Rank number: left margin, vertically centred on row i
        local board_row  = flip and i or (9 - i)
        local rank_label = tostring(board_row)
        local row_top = y + math.floor((i - 1) * ch)
        local m1      = RenderText:sizeUtf8Text(0, Screen:getWidth(), label_face, rank_label, true, false)
        local base1   = row_top + math.floor((ch + m1.y_top - m1.y_bottom) / 2)
        RenderText:renderUtf8Text(bb, x0 + math.floor((margin - m1.x) / 2), base1,
            label_face, rank_label, true, false, Blitbuffer.COLOR_GRAY_5)

        -- File letter: bottom margin, horizontally centred on column i
        local board_col  = flip and (9 - i) or i
        local file_label = file_letters[board_col] or ""
        local col_left = x + math.floor((i - 1) * cw)
        local m2       = RenderText:sizeUtf8Text(0, Screen:getWidth(), label_face, file_label, true, false)
        local base2    = y + S + math.floor((margin - self.label_ascent) / 2) + self.label_ascent
        RenderText:renderUtf8Text(bb, col_left + math.floor((cw - m2.x) / 2), base2,
            label_face, file_label, true, false, Blitbuffer.COLOR_GRAY_5)
    end
end

return PuzzleBoardWidget
