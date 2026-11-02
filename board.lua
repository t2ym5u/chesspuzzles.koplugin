-- ---------------------------------------------------------------------------
-- ChessBoard — complete chess engine (no AI)
--
-- Vendored from chesscourse.koplugin/board.lua, plus UCI helpers
-- (applyUCI / moveToUCI / parseUCI) for the Lichess puzzle move lists.
--
-- Piece encoding:
--   0  = empty
--   1  = white pawn   (W_PAWN)
--   2  = white rook   (W_ROOK)
--   3  = white knight (W_KNIGHT)
--   4  = white bishop (W_BISHOP)
--   5  = white queen  (W_QUEEN)
--   6  = white king   (W_KING)
--   7  = black pawn   (B_PAWN)
--   8  = black rook   (B_ROOK)
--   9  = black knight (B_KNIGHT)
--   10 = black bishop (B_BISHOP)
--   11 = black queen  (B_QUEEN)
--   12 = black king   (B_KING)
--
-- Grid coordinates: r=1 top (rank 8 in chess), r=8 bottom (rank 1 in chess)
--                   c=1 = a-file, c=8 = h-file
-- Conversion: chess_rank R → r = 9 - R;  chess_file f (a=1..h=8) → c = f
-- ---------------------------------------------------------------------------

local ChessBoard = {}
ChessBoard.__index = ChessBoard

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

ChessBoard.EMPTY    = 0
ChessBoard.W_PAWN   = 1
ChessBoard.W_ROOK   = 2
ChessBoard.W_KNIGHT = 3
ChessBoard.W_BISHOP = 4
ChessBoard.W_QUEEN  = 5
ChessBoard.W_KING   = 6
ChessBoard.B_PAWN   = 7
ChessBoard.B_ROOK   = 8
ChessBoard.B_KNIGHT = 9
ChessBoard.B_BISHOP = 10
ChessBoard.B_QUEEN  = 11
ChessBoard.B_KING   = 12

local EMPTY    = ChessBoard.EMPTY
local W_PAWN   = ChessBoard.W_PAWN
local W_ROOK   = ChessBoard.W_ROOK
local W_KNIGHT = ChessBoard.W_KNIGHT
local W_BISHOP = ChessBoard.W_BISHOP
local W_QUEEN  = ChessBoard.W_QUEEN
local W_KING   = ChessBoard.W_KING
local B_PAWN   = ChessBoard.B_PAWN
local B_ROOK   = ChessBoard.B_ROOK
local B_KNIGHT = ChessBoard.B_KNIGHT
local B_BISHOP = ChessBoard.B_BISHOP
local B_QUEEN  = ChessBoard.B_QUEEN
local B_KING   = ChessBoard.B_KING

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isWhite(v)
    return v >= W_PAWN and v <= W_KING
end

local function isBlack(v)
    return v >= B_PAWN and v <= B_KING
end

local function isEnemy(v, color)
    if color == "white" then return isBlack(v) end
    return isWhite(v)
end

local function isFriendly(v, color)
    if color == "white" then return isWhite(v) end
    return isBlack(v)
end

local function inBounds(r, c)
    return r >= 1 and r <= 8 and c >= 1 and c <= 8
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function ChessBoard:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.sq       = {}
    o.turn     = "white"
    o.selected = nil
    o.status   = "playing"   -- "playing", "check", "checkmate", "stalemate"
    o.winner   = nil
    o.last_move = nil

    -- Castling rights: white king-side, white queen-side, black king-side, black queen-side
    o.castle_wk = true
    o.castle_wq = true
    o.castle_bk = true
    o.castle_bq = true

    -- En passant target square (grid coords), or nil
    o.ep_r = nil
    o.ep_c = nil

    -- Halfmove clock and fullmove number
    o.halfmove = 0
    o.fullmove = 1

    -- Undo stack
    o._undo = {}

    for r = 1, 8 do
        o.sq[r] = {}
        for c = 1, 8 do
            o.sq[r][c] = EMPTY
        end
    end
    return o
end

-- ---------------------------------------------------------------------------
-- Board setup
-- ---------------------------------------------------------------------------

function ChessBoard:reset()
    -- Clear board
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = EMPTY
        end
    end

    -- Black pieces (r=1 = rank 8)
    self.sq[1][1] = B_ROOK
    self.sq[1][2] = B_KNIGHT
    self.sq[1][3] = B_BISHOP
    self.sq[1][4] = B_QUEEN
    self.sq[1][5] = B_KING
    self.sq[1][6] = B_BISHOP
    self.sq[1][7] = B_KNIGHT
    self.sq[1][8] = B_ROOK
    for c = 1, 8 do
        self.sq[2][c] = B_PAWN
    end

    -- White pieces (r=8 = rank 1)
    self.sq[8][1] = W_ROOK
    self.sq[8][2] = W_KNIGHT
    self.sq[8][3] = W_BISHOP
    self.sq[8][4] = W_QUEEN
    self.sq[8][5] = W_KING
    self.sq[8][6] = W_BISHOP
    self.sq[8][7] = W_KNIGHT
    self.sq[8][8] = W_ROOK
    for c = 1, 8 do
        self.sq[7][c] = W_PAWN
    end

    self.turn      = "white"
    self.selected  = nil
    self.status    = "playing"
    self.winner    = nil
    self.last_move = nil
    self.castle_wk = true
    self.castle_wq = true
    self.castle_bk = true
    self.castle_bq = true
    self.ep_r      = nil
    self.ep_c      = nil
    self.halfmove  = 0
    self.fullmove  = 1
    self._undo     = {}
end

-- ---------------------------------------------------------------------------
-- FEN loading
-- ---------------------------------------------------------------------------

-- FEN piece character to piece value
local FEN_PIECE = {
    P = W_PAWN,   R = W_ROOK,   N = W_KNIGHT, B = W_BISHOP, Q = W_QUEEN, K = W_KING,
    p = B_PAWN,   r = B_ROOK,   n = B_KNIGHT, b = B_BISHOP, q = B_QUEEN, k = B_KING,
}

-- FEN file letter to column number (a=1..h=8)
local function fileToCol(ch)
    return string.byte(ch) - string.byte("a") + 1
end

function ChessBoard:loadFEN(fen)
    -- Clear
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = EMPTY
        end
    end
    self.selected  = nil
    self.last_move = nil
    self._undo     = {}

    -- Split FEN into fields
    local fields = {}
    for field in fen:gmatch("%S+") do
        fields[#fields + 1] = field
    end

    -- Field 1: piece placement (rank 8 first = r=1 first)
    local position = fields[1] or ""
    local r = 1
    local c = 1
    for ch in position:gmatch(".") do
        if ch == "/" then
            r = r + 1
            c = 1
        elseif ch:match("%d") then
            c = c + tonumber(ch)
        else
            local piece = FEN_PIECE[ch]
            if piece and r >= 1 and r <= 8 and c >= 1 and c <= 8 then
                self.sq[r][c] = piece
            end
            c = c + 1
        end
    end

    -- Field 2: active color
    local color_field = fields[2] or "w"
    self.turn = (color_field == "b") and "black" or "white"

    -- Field 3: castling availability
    local castle_field = fields[3] or "-"
    self.castle_wk = castle_field:find("K") ~= nil
    self.castle_wq = castle_field:find("Q") ~= nil
    self.castle_bk = castle_field:find("k") ~= nil
    self.castle_bq = castle_field:find("q") ~= nil

    -- Field 4: en passant target square
    local ep_field = fields[4] or "-"
    if ep_field ~= "-" and #ep_field >= 2 then
        local ep_file = ep_field:sub(1, 1)
        local ep_rank = tonumber(ep_field:sub(2, 2))
        if ep_rank then
            self.ep_c = fileToCol(ep_file)
            self.ep_r = 9 - ep_rank
        else
            self.ep_c = nil
            self.ep_r = nil
        end
    else
        self.ep_r = nil
        self.ep_c = nil
    end

    -- Field 5: halfmove clock
    self.halfmove = tonumber(fields[5]) or 0

    -- Field 6: fullmove number
    self.fullmove = tonumber(fields[6]) or 1

    -- Compute initial status
    self:_updateStatus()
end

-- ---------------------------------------------------------------------------
-- Attack detection
-- ---------------------------------------------------------------------------

function ChessBoard:isAttacked(r, c, by_color)
    local sq = self.sq

    -- Knight attacks
    local knight = (by_color == "white") and W_KNIGHT or B_KNIGHT
    for _, d in ipairs({{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}) do
        local nr, nc = r + d[1], c + d[2]
        if inBounds(nr, nc) and sq[nr][nc] == knight then
            return true
        end
    end

    -- Rook / Queen (straight lines)
    local rook  = (by_color == "white") and W_ROOK  or B_ROOK
    local queen = (by_color == "white") and W_QUEEN or B_QUEEN
    for _, d in ipairs({{0,1},{0,-1},{1,0},{-1,0}}) do
        local nr, nc = r + d[1], c + d[2]
        while inBounds(nr, nc) do
            local v = sq[nr][nc]
            if v ~= EMPTY then
                if v == rook or v == queen then return true end
                break
            end
            nr = nr + d[1]
            nc = nc + d[2]
        end
    end

    -- Bishop / Queen (diagonals)
    local bishop = (by_color == "white") and W_BISHOP or B_BISHOP
    for _, d in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do
        local nr, nc = r + d[1], c + d[2]
        while inBounds(nr, nc) do
            local v = sq[nr][nc]
            if v ~= EMPTY then
                if v == bishop or v == queen then return true end
                break
            end
            nr = nr + d[1]
            nc = nc + d[2]
        end
    end

    -- Pawn attacks
    -- White pawns move up (decreasing r); they attack diagonally upward from their position
    -- A white pawn at (pr, pc) attacks (pr-1, pc-1) and (pr-1, pc+1)
    -- So the square (r, c) is attacked by a white pawn sitting at (r+1, c±1)
    if by_color == "white" then
        for dc = -1, 1, 2 do
            local pr, pc = r + 1, c + dc
            if inBounds(pr, pc) and sq[pr][pc] == W_PAWN then
                return true
            end
        end
    else
        -- Black pawns move down (increasing r); attack from (pr+1, pc±1) toward (pr, pc)
        -- Square (r,c) is attacked by a black pawn at (r-1, c±1)
        for dc = -1, 1, 2 do
            local pr, pc = r - 1, c + dc
            if inBounds(pr, pc) and sq[pr][pc] == B_PAWN then
                return true
            end
        end
    end

    -- King attacks
    local enemy_king = (by_color == "white") and W_KING or B_KING
    for _, d in ipairs({{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}}) do
        local nr, nc = r + d[1], c + d[2]
        if inBounds(nr, nc) and sq[nr][nc] == enemy_king then
            return true
        end
    end

    return false
end

function ChessBoard:findKing(color)
    local king = (color == "white") and W_KING or B_KING
    for r = 1, 8 do
        for c = 1, 8 do
            if self.sq[r][c] == king then
                return r, c
            end
        end
    end
    return nil, nil
end

function ChessBoard:isInCheck(color)
    local kr, kc = self:findKing(color)
    if not kr then return false end
    local by = (color == "white") and "black" or "white"
    return self:isAttacked(kr, kc, by)
end

-- ---------------------------------------------------------------------------
-- Move generation (pseudo-legal, then filtered for legality)
-- ---------------------------------------------------------------------------

-- Generate pseudo-legal moves for the piece at (r, c).
-- Returns list of {fr, fc, tr, tc, capture, special, promo_piece}
-- special: nil, "ep", "castle_ks", "castle_qs", "promo"
function ChessBoard:_pseudoMovesForPiece(r, c)
    local v     = self.sq[r][c]
    local moves = {}
    local sq    = self.sq

    if v == EMPTY then return moves end

    local color = isWhite(v) and "white" or "black"

    local function addMove(tr, tc, special, promo)
        local cap = sq[tr][tc]
        moves[#moves + 1] = {
            fr = r, fc = c, tr = tr, tc = tc,
            capture = cap ~= EMPTY and cap or nil,
            special = special,
            promo_piece = promo,
        }
    end

    -- Sliding piece helper
    local function slide(dirs)
        for _, d in ipairs(dirs) do
            local nr, nc = r + d[1], c + d[2]
            while inBounds(nr, nc) do
                local target = sq[nr][nc]
                if target == EMPTY then
                    addMove(nr, nc)
                elseif isEnemy(target, color) then
                    addMove(nr, nc)
                    break
                else
                    break  -- friendly piece
                end
                nr = nr + d[1]
                nc = nc + d[2]
            end
        end
    end

    if v == W_PAWN then
        -- Forward one square (up = decreasing r)
        if inBounds(r-1, c) and sq[r-1][c] == EMPTY then
            if r-1 == 1 then
                -- Promotion
                for _, pp in ipairs({W_QUEEN, W_ROOK, W_BISHOP, W_KNIGHT}) do
                    addMove(r-1, c, "promo", pp)
                end
            else
                addMove(r-1, c)
            end
            -- Double advance from starting rank (r=7)
            if r == 7 and sq[r-2][c] == EMPTY then
                addMove(r-2, c)
            end
        end
        -- Captures diagonally
        for _, dc in ipairs({-1, 1}) do
            local tc = c + dc
            if inBounds(r-1, tc) then
                local target = sq[r-1][tc]
                if isBlack(target) then
                    if r-1 == 1 then
                        for _, pp in ipairs({W_QUEEN, W_ROOK, W_BISHOP, W_KNIGHT}) do
                            addMove(r-1, tc, "promo", pp)
                        end
                    else
                        addMove(r-1, tc)
                    end
                end
                -- En passant
                if self.ep_r == r-1 and self.ep_c == tc then
                    addMove(r-1, tc, "ep")
                end
            end
        end

    elseif v == B_PAWN then
        -- Forward one square (down = increasing r)
        if inBounds(r+1, c) and sq[r+1][c] == EMPTY then
            if r+1 == 8 then
                for _, pp in ipairs({B_QUEEN, B_ROOK, B_BISHOP, B_KNIGHT}) do
                    addMove(r+1, c, "promo", pp)
                end
            else
                addMove(r+1, c)
            end
            -- Double advance from starting rank (r=2)
            if r == 2 and sq[r+2][c] == EMPTY then
                addMove(r+2, c)
            end
        end
        -- Captures diagonally
        for _, dc in ipairs({-1, 1}) do
            local tc = c + dc
            if inBounds(r+1, tc) then
                local target = sq[r+1][tc]
                if isWhite(target) then
                    if r+1 == 8 then
                        for _, pp in ipairs({B_QUEEN, B_ROOK, B_BISHOP, B_KNIGHT}) do
                            addMove(r+1, tc, "promo", pp)
                        end
                    else
                        addMove(r+1, tc)
                    end
                end
                -- En passant
                if self.ep_r == r+1 and self.ep_c == tc then
                    addMove(r+1, tc, "ep")
                end
            end
        end

    elseif v == W_KNIGHT or v == B_KNIGHT then
        for _, d in ipairs({{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}) do
            local nr, nc = r + d[1], c + d[2]
            if inBounds(nr, nc) and not isFriendly(sq[nr][nc], color) then
                addMove(nr, nc)
            end
        end

    elseif v == W_BISHOP or v == B_BISHOP then
        slide({{1,1},{1,-1},{-1,1},{-1,-1}})

    elseif v == W_ROOK or v == B_ROOK then
        slide({{0,1},{0,-1},{1,0},{-1,0}})

    elseif v == W_QUEEN or v == B_QUEEN then
        slide({{0,1},{0,-1},{1,0},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1}})

    elseif v == W_KING then
        for _, d in ipairs({{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}}) do
            local nr, nc = r + d[1], c + d[2]
            if inBounds(nr, nc) and not isFriendly(sq[nr][nc], color) then
                addMove(nr, nc)
            end
        end
        -- Castling king-side: king e1(r=8,c=5) → g1(r=8,c=7)
        if self.castle_wk and r == 8 and c == 5
            and sq[8][6] == EMPTY and sq[8][7] == EMPTY
            and sq[8][8] == W_ROOK
            and not self:isAttacked(8, 5, "black")
            and not self:isAttacked(8, 6, "black")
            and not self:isAttacked(8, 7, "black")
        then
            addMove(8, 7, "castle_ks")
        end
        -- Castling queen-side: king e1(r=8,c=5) → c1(r=8,c=3)
        if self.castle_wq and r == 8 and c == 5
            and sq[8][4] == EMPTY and sq[8][3] == EMPTY and sq[8][2] == EMPTY
            and sq[8][1] == W_ROOK
            and not self:isAttacked(8, 5, "black")
            and not self:isAttacked(8, 4, "black")
            and not self:isAttacked(8, 3, "black")
        then
            addMove(8, 3, "castle_qs")
        end

    elseif v == B_KING then
        for _, d in ipairs({{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}}) do
            local nr, nc = r + d[1], c + d[2]
            if inBounds(nr, nc) and not isFriendly(sq[nr][nc], color) then
                addMove(nr, nc)
            end
        end
        -- Castling king-side: king e8(r=1,c=5) → g8(r=1,c=7)
        if self.castle_bk and r == 1 and c == 5
            and sq[1][6] == EMPTY and sq[1][7] == EMPTY
            and sq[1][8] == B_ROOK
            and not self:isAttacked(1, 5, "white")
            and not self:isAttacked(1, 6, "white")
            and not self:isAttacked(1, 7, "white")
        then
            addMove(1, 7, "castle_ks")
        end
        -- Castling queen-side: king e8(r=1,c=5) → c8(r=1,c=3)
        if self.castle_bq and r == 1 and c == 5
            and sq[1][4] == EMPTY and sq[1][3] == EMPTY and sq[1][2] == EMPTY
            and sq[1][1] == B_ROOK
            and not self:isAttacked(1, 5, "white")
            and not self:isAttacked(1, 4, "white")
            and not self:isAttacked(1, 3, "white")
        then
            addMove(1, 3, "castle_qs")
        end
    end

    return moves
end

-- Apply a move temporarily to test for check, returns undo function.
-- Handles en passant, castling, promotion.
function ChessBoard:_applyTempMove(m)
    local sq = self.sq
    local fr, fc, tr, tc = m.fr, m.fc, m.tr, m.tc
    local moved = sq[fr][fc]
    local captured = sq[tr][tc]
    local ep_captured_r, ep_captured_c, ep_captured_v

    sq[fr][fc] = EMPTY
    sq[tr][tc] = m.promo_piece or moved

    -- En passant: remove the captured pawn
    if m.special == "ep" then
        -- The captured pawn is on the same rank as the moving pawn's origin, same file as destination
        if moved == W_PAWN then
            ep_captured_r = fr     -- same rank as white pawn source (since white pawn moved up)
            ep_captured_c = tc
        else
            ep_captured_r = fr
            ep_captured_c = tc
        end
        ep_captured_v = sq[ep_captured_r][ep_captured_c]
        sq[ep_captured_r][ep_captured_c] = EMPTY
    end

    -- Castling: move rook too
    local rook_fr, rook_fc, rook_tr, rook_tc
    if m.special == "castle_ks" then
        rook_fr = tr; rook_fc = 8; rook_tr = tr; rook_tc = tc - 1
        sq[rook_tr][rook_tc] = sq[rook_fr][rook_fc]
        sq[rook_fr][rook_fc] = EMPTY
    elseif m.special == "castle_qs" then
        rook_fr = tr; rook_fc = 1; rook_tr = tr; rook_tc = tc + 1
        sq[rook_tr][rook_tc] = sq[rook_fr][rook_fc]
        sq[rook_fr][rook_fc] = EMPTY
    end

    return function()
        sq[fr][fc] = moved
        sq[tr][tc] = captured
        if m.special == "ep" then
            sq[ep_captured_r][ep_captured_c] = ep_captured_v
        end
        if rook_fr then
            sq[rook_fr][rook_fc] = sq[rook_tr][rook_tc]
            sq[rook_tr][rook_tc] = EMPTY
        end
    end
end

-- Check if a move leaves the moving side's king in check (illegal).
function ChessBoard:_isLegalMove(m)
    local color = isWhite(self.sq[m.fr][m.fc]) and "white" or "black"
    local undo = self:_applyTempMove(m)
    local in_check = self:isInCheck(color)
    undo()
    return not in_check
end

-- ---------------------------------------------------------------------------
-- Public: legal move generation
-- ---------------------------------------------------------------------------

function ChessBoard:getLegalMoves()
    local legal = {}
    for r = 1, 8 do
        for c = 1, 8 do
            local v = self.sq[r][c]
            if v ~= EMPTY then
                local color = isWhite(v) and "white" or "black"
                if color == self.turn then
                    local pseudo = self:_pseudoMovesForPiece(r, c)
                    for _, m in ipairs(pseudo) do
                        if self:_isLegalMove(m) then
                            legal[#legal + 1] = m
                        end
                    end
                end
            end
        end
    end
    return legal
end

function ChessBoard:getMovesForSquare(r, c)
    local v = self.sq[r][c]
    if v == EMPTY then return {} end
    local color = isWhite(v) and "white" or "black"
    if color ~= self.turn then return {} end

    local result = {}
    local pseudo = self:_pseudoMovesForPiece(r, c)
    for _, m in ipairs(pseudo) do
        if self:_isLegalMove(m) then
            result[#result + 1] = m
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Apply a move (permanent)
-- ---------------------------------------------------------------------------

function ChessBoard:makeMove(fr, fc, tr, tc, promo_piece)
    -- Find a matching legal move
    local legal = self:getMovesForSquare(fr, fc)
    local chosen = nil
    for _, m in ipairs(legal) do
        if m.tr == tr and m.tc == tc then
            -- For promotions, match promo_piece; default to queen
            if m.special == "promo" then
                local want = promo_piece
                if not want then
                    want = isWhite(self.sq[fr][fc]) and W_QUEEN or B_QUEEN
                end
                if m.promo_piece == want then
                    chosen = m
                    break
                end
            else
                chosen = m
                break
            end
        end
    end
    if not chosen then return false end

    -- Push undo snapshot
    self:_pushUndo()

    local sq    = self.sq
    local moved = sq[fr][fc]

    -- Save new en passant square (for double pawn advance)
    local new_ep_r, new_ep_c = nil, nil

    -- Apply move
    sq[fr][fc] = EMPTY
    sq[tr][tc] = chosen.promo_piece or moved

    -- En passant capture: remove the pawn on the same rank as origin, same file as destination
    if chosen.special == "ep" then
        if moved == W_PAWN then
            sq[fr][tc] = EMPTY   -- white pawn captures: pawn to remove is at (fr, tc)
        else
            sq[fr][tc] = EMPTY   -- black pawn captures: pawn to remove is at (fr, tc)
        end
    end

    -- Double pawn advance: set en passant square
    if moved == W_PAWN and fr == 7 and tr == 5 then
        new_ep_r = 6; new_ep_c = fc
    elseif moved == B_PAWN and fr == 2 and tr == 4 then
        new_ep_r = 3; new_ep_c = fc
    end

    -- Castling: move rook
    if chosen.special == "castle_ks" then
        -- King-side: rook moves from h-file to f-file (same rank)
        sq[tr][tc-1] = sq[tr][8]
        sq[tr][8] = EMPTY
    elseif chosen.special == "castle_qs" then
        -- Queen-side: rook moves from a-file to d-file (same rank)
        sq[tr][tc+1] = sq[tr][1]
        sq[tr][1] = EMPTY
    end

    -- Update castling rights
    if moved == W_KING then
        self.castle_wk = false
        self.castle_wq = false
    elseif moved == B_KING then
        self.castle_bk = false
        self.castle_bq = false
    elseif moved == W_ROOK then
        if fr == 8 and fc == 8 then self.castle_wk = false end
        if fr == 8 and fc == 1 then self.castle_wq = false end
    elseif moved == B_ROOK then
        if fr == 1 and fc == 8 then self.castle_bk = false end
        if fr == 1 and fc == 1 then self.castle_bq = false end
    end
    -- If rook square is captured
    if tr == 8 and tc == 8 then self.castle_wk = false end
    if tr == 8 and tc == 1 then self.castle_wq = false end
    if tr == 1 and tc == 8 then self.castle_bk = false end
    if tr == 1 and tc == 1 then self.castle_bq = false end

    self.ep_r = new_ep_r
    self.ep_c = new_ep_c

    -- Update halfmove clock
    if moved == W_PAWN or moved == B_PAWN or chosen.capture then
        self.halfmove = 0
    else
        self.halfmove = self.halfmove + 1
    end

    -- Update fullmove
    if self.turn == "black" then
        self.fullmove = self.fullmove + 1
    end

    -- Record last move
    self.last_move = { fr = fr, fc = fc, tr = tr, tc = tc,
                       special = chosen.special, promo_piece = chosen.promo_piece }

    -- Switch turn
    self.turn = (self.turn == "white") and "black" or "white"

    self.selected = nil
    self:_updateStatus()
    return true
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function ChessBoard:_pushUndo()
    local snap = {
        turn      = self.turn,
        selected  = self.selected,
        status    = self.status,
        winner    = self.winner,
        last_move = self.last_move and {
            fr = self.last_move.fr, fc = self.last_move.fc,
            tr = self.last_move.tr, tc = self.last_move.tc,
            special = self.last_move.special,
            promo_piece = self.last_move.promo_piece,
        } or nil,
        castle_wk = self.castle_wk,
        castle_wq = self.castle_wq,
        castle_bk = self.castle_bk,
        castle_bq = self.castle_bq,
        ep_r      = self.ep_r,
        ep_c      = self.ep_c,
        halfmove  = self.halfmove,
        fullmove  = self.fullmove,
        sq        = {},
    }
    for r = 1, 8 do
        snap.sq[r] = {}
        for c = 1, 8 do
            snap.sq[r][c] = self.sq[r][c]
        end
    end
    self._undo[#self._undo + 1] = snap
    -- Limit undo stack
    if #self._undo > 100 then
        table.remove(self._undo, 1)
    end
end

function ChessBoard:undoMove()
    if #self._undo == 0 then return false end
    local snap = self._undo[#self._undo]
    self._undo[#self._undo] = nil

    self.turn      = snap.turn
    self.selected  = snap.selected
    self.status    = snap.status
    self.winner    = snap.winner
    self.last_move = snap.last_move
    self.castle_wk = snap.castle_wk
    self.castle_wq = snap.castle_wq
    self.castle_bk = snap.castle_bk
    self.castle_bq = snap.castle_bq
    self.ep_r      = snap.ep_r
    self.ep_c      = snap.ep_c
    self.halfmove  = snap.halfmove
    self.fullmove  = snap.fullmove
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = snap.sq[r][c]
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Status update (check/checkmate/stalemate)
-- ---------------------------------------------------------------------------

function ChessBoard:_updateStatus()
    local color = self.turn
    local in_check = self:isInCheck(color)
    local has_moves = false

    -- Check if current side has any legal moves
    for r = 1, 8 do
        for c = 1, 8 do
            local v = self.sq[r][c]
            if v ~= EMPTY then
                local vc = isWhite(v) and "white" or "black"
                if vc == color then
                    local pseudo = self:_pseudoMovesForPiece(r, c)
                    for _, m in ipairs(pseudo) do
                        if self:_isLegalMove(m) then
                            has_moves = true
                            break
                        end
                    end
                end
            end
            if has_moves then break end
        end
        if has_moves then break end
    end

    if not has_moves then
        if in_check then
            self.status = "checkmate"
            self.winner = (color == "white") and "black" or "white"
        else
            self.status = "stalemate"
            self.winner = nil
        end
    elseif in_check then
        self.status = "check"
    else
        self.status = "playing"
    end
end

-- ---------------------------------------------------------------------------
-- tapCell — interactive selection/move dispatch
-- Returns: "select", "move", "deselect", "invalid", "promo_needed"
-- ---------------------------------------------------------------------------

function ChessBoard:tapCell(r, c)
    if self.status == "checkmate" or self.status == "stalemate" then
        return "invalid"
    end

    local v = self.sq[r][c]

    -- If a piece is already selected
    if self.selected then
        local sr, sc = self.selected[1], self.selected[2]

        -- Tapping same square: deselect
        if r == sr and c == sc then
            self.selected = nil
            return "deselect"
        end

        -- Attempt move
        local legal = self:getMovesForSquare(sr, sc)
        for _, m in ipairs(legal) do
            if m.tr == r and m.tc == c then
                -- Promotion: if multiple promo choices, we pick queen by default
                -- The caller can pass promo_piece separately if needed
                local ok = self:makeMove(sr, sc, r, c)
                if ok then
                    return "move"
                end
            end
        end

        -- Tap on a friendly piece: switch selection
        if v ~= EMPTY and isFriendly(v, self.turn) then
            local new_moves = self:getMovesForSquare(r, c)
            if #new_moves > 0 then
                self.selected = { r, c }
                return "select"
            end
        end

        -- Otherwise invalid
        return "invalid"
    end

    -- No selection: try to select
    if v ~= EMPTY and isFriendly(v, self.turn) then
        local moves = self:getMovesForSquare(r, c)
        if #moves > 0 then
            self.selected = { r, c }
            return "select"
        end
    end

    return "invalid"
end

-- ---------------------------------------------------------------------------
-- UCI helpers ("e2e4", "e7e8q") — the Lichess puzzle move lists use them.
-- ---------------------------------------------------------------------------

local PROMO_W = { q = W_QUEEN, r = W_ROOK, b = W_BISHOP, n = W_KNIGHT }
local PROMO_B = { q = B_QUEEN, r = B_ROOK, b = B_BISHOP, n = B_KNIGHT }
local PROMO_CHAR = {
    [W_QUEEN] = "q", [W_ROOK] = "r", [W_BISHOP] = "b", [W_KNIGHT] = "n",
    [B_QUEEN] = "q", [B_ROOK] = "r", [B_BISHOP] = "b", [B_KNIGHT] = "n",
}

-- "e2e4" -> fr, fc, tr, tc, promo_char (or nil); nil when malformed.
function ChessBoard.parseUCI(uci)
    if type(uci) ~= "string" then return nil end
    local f1, r1, f2, r2, p = uci:match("^([a-h])([1-8])([a-h])([1-8])([qrbn]?)$")
    if not f1 then return nil end
    return 9 - tonumber(r1), fileToCol(f1), 9 - tonumber(r2), fileToCol(f2),
        (p ~= "" and p or nil)
end

-- Grid coordinates (+ optional promotion char or piece value) -> "e2e4".
function ChessBoard.toUCI(fr, fc, tr, tc, promo)
    local files = "abcdefgh"
    if type(promo) == "number" then promo = PROMO_CHAR[promo] end
    return files:sub(fc, fc) .. (9 - fr) .. files:sub(tc, tc) .. (9 - tr) .. (promo or "")
end

-- The last move played, in UCI.
function ChessBoard:lastMoveUCI()
    local m = self.last_move
    if not m then return nil end
    return ChessBoard.toUCI(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
end

-- Piece value for promotion char `p` for the side to move.
function ChessBoard:promoPiece(p)
    if not p then return nil end
    return (self.turn == "white" and PROMO_W or PROMO_B)[p]
end

-- True when moving (fr,fc)->(tr,tc) is a legal pawn promotion.
function ChessBoard:isPromotionMove(fr, fc, tr, tc)
    for _, m in ipairs(self:getMovesForSquare(fr, fc)) do
        if m.tr == tr and m.tc == tc and m.special == "promo" then return true end
    end
    return false
end

-- True when the move is legal (a promotion needs `p`, or defaults to queen).
function ChessBoard:isLegalUCI(uci)
    local fr, fc, tr, tc, p = ChessBoard.parseUCI(uci)
    if not fr then return false end
    local want = self:promoPiece(p)
    for _, m in ipairs(self:getMovesForSquare(fr, fc)) do
        if m.tr == tr and m.tc == tc then
            if m.special ~= "promo" then return p == nil end
            if m.promo_piece == (want or self:promoPiece("q")) then return true end
        end
    end
    return false
end

-- Play a UCI move; false (board unchanged) when it is not legal.
function ChessBoard:applyUCI(uci)
    if not self:isLegalUCI(uci) then return false end
    local fr, fc, tr, tc, p = ChessBoard.parseUCI(uci)
    return self:makeMove(fr, fc, tr, tc, self:promoPiece(p))
end

return ChessBoard
