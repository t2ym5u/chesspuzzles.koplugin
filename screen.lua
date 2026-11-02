local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local DailySeed   = require("daily_seed")
local MenuHelper  = require("menu_helper")
local BoardWidget = lrequire("board_widget")
local Game        = lrequire("game")
local Puzzles     = lrequire("puzzles")
local Rating      = lrequire("rating")

local GAME_RULES_EN = [[
Chess Puzzles — Rules

Find the best move. Each puzzle comes from a real game: the board is shown after your opponent's last move (highlighted), and you play the side to move — your pieces are at the bottom.

• Tap a piece, then the square to move it to (dots mark its legal moves). A pawn reaching the last rank asks which piece it becomes.
• A right move is answered by your opponent; keep going until the puzzle is solved. Several moves may be needed.
• A wrong move is crossed out and the board stays as it was: try again. Any move that checkmates is accepted, even if it is not the one in the solution.
• Hint: the first tap marks (inverts) the square of the piece to move, the second marks its target square too.
• Show solution gives up and lets you step through the rest of the solution, forwards and back.

Rating: you start at 1200. A puzzle solved without a wrong move, a hint or the solution wins rating points; otherwise it loses some — more or fewer depending on the puzzle's own rating. Only the first time you play a puzzle counts. Streak counts puzzles solved cleanly in a row.

Difficulty: Adaptive picks puzzles near your rating; Beginner (under 1000), Easy (1000–1399), Medium (1400–1799), Hard (1800–2199) and Expert (2200 and up) stay in one range. Theme narrows the choice (mates in 1, 2 or 3+, forks, pins, endgames…). Puzzles you have played are not offered again until you have seen them all. The Daily Challenge is the same puzzle for everyone today.

Puzzles from the Lichess puzzle database (lichess.org), CC0 public domain: 10,000 well-established puzzles, rated by Lichess players.
]]

local GAME_RULES_FR = [[
Problèmes d'échecs — Règles

Trouvez le meilleur coup. Chaque problème vient d'une vraie partie : l'échiquier est montré après le dernier coup de votre adversaire (en surbrillance), et vous jouez le camp au trait — vos pièces sont en bas.

• Touchez une pièce, puis la case où la jouer (des points marquent ses coups légaux). Un pion qui atteint la dernière rangée demande en quelle pièce il se transforme.
• Un bon coup reçoit la réponse de l'adversaire ; continuez jusqu'à la solution complète. Il faut parfois plusieurs coups.
• Un mauvais coup est barré et la position reste la même : réessayez. Tout coup qui fait mat est accepté, même s'il n'est pas celui de la solution.
• Astuce : le premier appui marque (en négatif) la case de la pièce à jouer, le second marque aussi sa case d'arrivée.
• Voir la solution abandonne et permet de parcourir le reste de la solution, en avant et en arrière.

Classement : vous partez de 1200. Un problème résolu sans faute, sans astuce et sans la solution fait gagner des points ; sinon il en fait perdre — plus ou moins selon le classement du problème. Seule la première partie d'un problème compte. La série compte les problèmes résolus sans faute d'affilée.

Difficulté : Adaptatif choisit des problèmes proches de votre classement ; Débutant (moins de 1000), Facile (1000–1399), Moyen (1400–1799), Difficile (1800–2199) et Expert (2200 et plus) restent dans une tranche. Le thème restreint le choix (mats en 1, 2 ou 3+, fourchettes, clouages, finales…). Les problèmes déjà joués ne reviennent pas avant que vous les ayez tous vus. Le Défi du jour est le même problème pour tout le monde aujourd'hui.

Problèmes issus de la base de problèmes de Lichess (lichess.org), domaine public CC0 : 10 000 problèmes bien établis, classés par les joueurs de Lichess.
]]

local BAND_LABELS = {
    adaptive = _("Adaptive"),
    beginner = _("Beginner"),
    easy     = _("Easy"),
    medium   = _("Medium"),
    hard     = _("Hard"),
    expert   = _("Expert"),
}

local BAND_RANGES = {
    beginner = "< 1000",
    easy     = "1000–1399",
    medium   = "1400–1799",
    hard     = "1800–2199",
    expert   = "2200+",
}

local THEME_LABELS = {
    all        = _("All themes"),
    mate1      = _("Mate in 1"),
    mate2      = _("Mate in 2"),
    mate3      = _("Mate in 3+"),
    fork       = _("Forks"),
    pin        = _("Pins"),
    skewer     = _("Skewers"),
    discovered = _("Discovered attacks"),
    sacrifice  = _("Sacrifices"),
    endgame    = _("Endgames"),
    promotion  = _("Promotion"),
}

local REPLY_DELAY = 0.6

local ChessPuzzlesScreen = ScreenBase:extend{}

function ChessPuzzlesScreen:init()
    self.game = Game:new()
    self.user_flip = false
    local saved = self.plugin:loadState()
    local p = type(saved) == "table" and Puzzles.isBand(saved.band)
        and Puzzles.get(saved.band, tonumber(saved.index) or 0)
    if not (p and self.game:load(saved, p)) then
        self:_newPuzzle()
    end
    ScreenBase.init(self)
end

function ChessPuzzlesScreen:serializeState()
    return self.game:serialize()
end

function ChessPuzzlesScreen:_save()
    self.plugin:saveState(self.game:serialize())
end

function ChessPuzzlesScreen:closeScreen()
    self:_cancelReply()
    ScreenBase.closeScreen(self)
end

-- ---------------------------------------------------------------------------
-- Settings, progress and rating
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_getBand()
    local b = self.plugin:getSetting("difficulty", "adaptive")
    return (b == "adaptive" or Puzzles.isBand(b)) and b or "adaptive"
end

function ChessPuzzlesScreen:_getTheme()
    local t = self.plugin:getSetting("theme", "all")
    return THEME_LABELS[t] and t or "all"
end

function ChessPuzzlesScreen:getRating()
    return tonumber(self.plugin:getSetting("rating", Rating.START)) or Rating.START
end

-- Puzzles seen per band: one character per puzzle, "0" not played yet,
-- "1" solved cleanly, "2" failed (wrong move, hint or solution).
function ChessPuzzlesScreen:_seenMap(band)
    local s = self.plugin:getSetting("seen_" .. band, "")
    return type(s) == "string" and s or ""
end

function ChessPuzzlesScreen:isSeen(band, index)
    local ch = self:_seenMap(band):sub(index, index)
    return ch ~= "" and ch ~= "0"
end

function ChessPuzzlesScreen:seenCount(band)
    local _s, n = self:_seenMap(band):gsub("[12]", "")
    return n
end

function ChessPuzzlesScreen:_markSeen(band, index, ch)
    if not band or not index or index < 1 then return end
    local s = self:_seenMap(band)
    if #s < index then s = s .. string.rep("0", index - #s) end
    s = s:sub(1, index - 1) .. ch .. s:sub(index + 1)
    self.plugin:saveSetting("seen_" .. band, s)
end

function ChessPuzzlesScreen:_stat(key)
    return tonumber(self.plugin:getSetting(key, 0)) or 0
end

-- Rate the puzzle once: on the first slip (win = false) or on a clean solve.
-- Puzzles played before (replays, a daily already met) are not rated.
function ChessPuzzlesScreen:_settle(win)
    local g = self.game
    if g.rated then return end
    g.rated = true
    if not g.ratable then return end
    local p = g.puzzle
    local n = self:_stat("rated_count")
    local new, delta = Rating.update(self:getRating(), p.rating, win, n)
    g.delta = delta
    self.plugin:saveSetting("rating", new)
    self.plugin:saveSetting("rated_count", n + 1)
    if win then
        self.plugin:saveSetting("solved_count", self:_stat("solved_count") + 1)
        local streak = self:_stat("streak") + 1
        self.plugin:saveSetting("streak", streak)
        if streak > self:_stat("best_streak") then
            self.plugin:saveSetting("best_streak", streak)
        end
    else
        self.plugin:saveSetting("failed_count", self:_stat("failed_count") + 1)
        self.plugin:saveSetting("streak", 0)
    end
    self:_markSeen(p.band, p.index, win and "1" or "2")
end

-- ---------------------------------------------------------------------------
-- Starting puzzles
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_startPuzzle(band, index, daily)
    local p = index and Puzzles.get(band, index)
    if not p then return false end
    self:_cancelReply()
    self.game:setPuzzle(p, daily, not self:isSeen(band, index))
    self.user_flip = false
    self.marks = nil
    self:_save()
    return true
end

-- The next puzzle for the current difficulty and theme. Returns a status
-- message when there is something to say about the choice.
function ChessPuzzlesScreen:_newPuzzle()
    local theme = self:_getTheme()
    local band, index, fresh = Puzzles.pick{
        band    = self:_getBand(),
        target  = self:getRating(),
        theme   = theme,
        -- The puzzle on the board counts as seen: "New game" on an
        -- unplayed puzzle must not deal the same one again.
        is_seen = function(b, i)
            local cur = self.game.puzzle
            return (cur and cur.band == b and cur.index == i) or self:isSeen(b, i)
        end,
    }
    if not band then
        -- Nothing matches the theme at all: drop the filter.
        band, index, fresh = Puzzles.pick{ band = self:_getBand(), target = self:getRating() }
    end
    if band then self:_startPuzzle(band, index) end
    if band and not fresh then
        return _("You have seen every puzzle that matches: this one is a replay, not rated.")
    end
end

function ChessPuzzlesScreen:onNewGame()
    local msg = self:_newPuzzle()
    self:buildLayout()
    if msg then self:updateStatus(msg) end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Today's puzzle: drawn from one band by the daily seed, so everyone playing
-- the same difficulty gets the same puzzle today (Adaptive: the band of your
-- rating). Only rated if you have never played it.
function ChessPuzzlesScreen:onDailyGame()
    local band = self:_getBand()
    if band == "adaptive" then band = Puzzles.bandFor(self:getRating()) end
    local total = Puzzles.count(band)
    if total == 0 then return end
    local plugin = self.plugin
    local key = (plugin.getPluginId and plugin:getPluginId() or plugin.name) .. "_" .. band
    local index
    DailySeed.run(key, function() index = math.random(total) end)
    self:_startPuzzle(band, index, os.date("%Y-%m-%d"))
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_isFlipped()
    return (self.game.player == "black") ~= self.user_flip
end

function ChessPuzzlesScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Chess Puzzles"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = T(_("Difficulty: %1"), BAND_LABELS[self:_getBand()]),
              callback = function() self:openDifficultyMenu() end },
            { text = T(_("Theme: %1"), THEME_LABELS[self:_getTheme()]),
              callback = function() self:openThemeMenu() end },
        }
        if not self.game:isOver() then
            items[#items + 1] = { text = _("Show solution"), callback = function() self:onShowSolution() end }
        end
        items[#items + 1] = { text = _("Flip board"), callback = function() self:onFlipBoard() end }
        items[#items + 1] = { text = _("Statistics"), callback = function() self:showStatistics() end }
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local hint     = { text = _("Hint"),          callback = function() self:onHint() end }
    local solution = { text = _("Show solution"), callback = function() self:onShowSolution() end }
    -- The landscape side panel is too narrow for both labels on one row.
    local action_bar = self:buildActionBar(is_landscape
        and { { hint }, { solution } }
        or  { hint, solution })
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    local frame_pad = Size.padding.default
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BoardWidget:new{
        board        = self.game.board,
        flipped      = self:_isFlipped(),
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellAction = function(r, c) self:onCellTap(r, c) end,
    }
    self:_syncWidget()
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- Copy what the board widget draws besides the pieces from the game.
function ChessPuzzlesScreen:_syncWidget()
    local w = self.board_widget
    if not w then return end
    w.last_move = self.game.board.last_move
    w.wrong     = self.game.wrong
    w.marks     = self.marks
    w.flipped   = self:_isFlipped()
end

function ChessPuzzlesScreen:_refreshBoard()
    self:_syncWidget()
    if self.board_widget then self.board_widget:refresh() end
end

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:onCellTap(r, c)
    local g = self.game
    if g.state ~= "play" then return end
    local b = g.board
    if g.wrong then
        g.wrong = nil
    end
    local sel = b.selected
    local v = b.sq[r][c]
    local own = v ~= 0 and ((v <= 6) == (b.turn == "white"))
    if sel and sel[1] == r and sel[2] == c then
        b.selected = nil
    elseif sel and not own then
        local legal = false
        for _i, m in ipairs(b:getMovesForSquare(sel[1], sel[2])) do
            if m.tr == r and m.tc == c then legal = true break end
        end
        b.selected = nil
        if legal then
            if g:needsPromotion(sel[1], sel[2], r, c) then
                self:showPromoDialog(sel[1], sel[2], r, c)
                self:_refreshBoard()
                return
            end
            self:_playerMove(sel[1], sel[2], r, c)
            return
        end
    elseif own and #b:getMovesForSquare(r, c) > 0 then
        b.selected = { r, c }
    else
        b.selected = nil
    end
    self:_refreshBoard()
    self:updateStatus()
end

function ChessPuzzlesScreen:showPromoDialog(fr, fc, tr, tc)
    local labels = {
        { "q", _("Queen") }, { "r", _("Rook") }, { "b", _("Bishop") }, { "n", _("Knight") },
    }
    local row = {}
    for _i, l in ipairs(labels) do
        row[#row + 1] = {
            text = l[2],
            callback = function()
                UIManager:close(self._promo_dialog)
                self._promo_dialog = nil
                self:_playerMove(fr, fc, tr, tc, l[1])
            end,
        }
    end
    self._promo_dialog = ButtonDialog:new{
        title   = _("Promotion — choose a piece:"),
        buttons = { row },
    }
    UIManager:show(self._promo_dialog)
end

function ChessPuzzlesScreen:_playerMove(fr, fc, tr, tc, promo)
    local g = self.game
    local result = g:tryMove(fr, fc, tr, tc, promo)
    self.marks = nil
    local msg
    if result == "wrong" then
        self:_settle(false)
        msg = _("Wrong move. Try again.")
    elseif result == "correct" then
        msg = _("Correct! Keep going.")
        self:_scheduleReply()
    elseif result == "solved" then
        self:_settle(not g.failed)
    end
    self:_save()
    self:_refreshBoard()
    self:updateStatus(msg)
end

-- The opponent answers after a short pause, so the player sees their own
-- move land first (one repaint each; no animation).
function ChessPuzzlesScreen:_scheduleReply()
    self:_cancelReply()
    self._reply_fn = function()
        self._reply_fn = nil
        self:_playReply()
    end
    UIManager:scheduleIn(REPLY_DELAY, self._reply_fn)
end

function ChessPuzzlesScreen:_cancelReply()
    if self._reply_fn then
        UIManager:unschedule(self._reply_fn)
        self._reply_fn = nil
    end
end

function ChessPuzzlesScreen:_playReply()
    if self.game:playReply() then
        self:_save()
        self:_refreshBoard()
        self:updateStatus()
    end
end

function ChessPuzzlesScreen:onHint()
    local g = self.game
    if g.state == "reply" then return end
    if g:isShowingSolution() then
        self:updateStatus(_("Hide the solution to keep playing."))
        return
    end
    local fr, fc, tr, tc, level = g:hint()
    if not fr then return end
    self:_settle(false)
    g.board.selected = nil
    self.marks = { { fr, fc } }
    if level == 2 then self.marks[2] = { tr, tc } end
    self:_save()
    self:_refreshBoard()
    self:updateStatus(level == 1
        and _("Move the marked piece.")
        or  _("Move it to the marked square."))
end

function ChessPuzzlesScreen:onShowSolution()
    self:_cancelReply()
    local g = self.game
    if not g:showSolution() then return end
    self:_settle(false)
    g.board.selected = nil
    self.marks = nil
    self:_save()
    self:_refreshBoard()
    self:updateStatus()
end

function ChessPuzzlesScreen:onSolutionStep(dir)
    if self.game:solutionStep(dir) then
        self:_save()
        self:_refreshBoard()
        self:updateStatus()
    end
end

function ChessPuzzlesScreen:onFlipBoard()
    self.user_flip = not self.user_flip
    self:_refreshBoard()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:openDifficultyMenu()
    local items = {
        { id = "adaptive",
          text = BAND_LABELS.adaptive .. " · " .. T(_("Rating: %1"), self:getRating()) },
    }
    for _i, id in ipairs(Puzzles.BANDS) do
        items[#items + 1] = {
            id   = id,
            text = self:joinStatus(BAND_LABELS[id], BAND_RANGES[id],
                T(_("Seen: %1/%2"), self:seenCount(id), Puzzles.count(id))),
        }
    end
    MenuHelper.openPickerMenu{
        title      = _("Difficulty"),
        items      = items,
        current_id = self:_getBand(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

function ChessPuzzlesScreen:openThemeMenu()
    local items = {}
    for _i, id in ipairs(Puzzles.THEMES) do
        items[#items + 1] = { id = id, text = THEME_LABELS[id] }
    end
    MenuHelper.openPickerMenu{
        title      = _("Theme"),
        items      = items,
        current_id = self:_getTheme(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("theme", id)
            self:onNewGame()
        end,
    }
end

function ChessPuzzlesScreen:statisticsText()
    local lines = {
        T(_("Rating: %1"), self:getRating()),
        T(_("Rated puzzles: %1"), self:_stat("rated_count")),
        T(_("Solved: %1"), self:_stat("solved_count")) .. ScreenBase.STATUS_SEP
            .. T(_("Failed: %1"), self:_stat("failed_count")),
        T(_("Streak: %1"), self:_stat("streak")) .. ScreenBase.STATUS_SEP
            .. T(_("Best streak: %1"), self:_stat("best_streak")),
        "",
    }
    for _i, id in ipairs(Puzzles.BANDS) do
        lines[#lines + 1] = BAND_LABELS[id] .. " · "
            .. T(_("Seen: %1/%2"), self:seenCount(id), Puzzles.count(id))
    end
    return table.concat(lines, "\n")
end

function ChessPuzzlesScreen:showStatistics()
    UIManager:show(InfoMessage:new{ text = self:statisticsText() })
end

-- ---------------------------------------------------------------------------
-- Round over: solved, or the solution on show (one-way).
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:isRoundOver()
    return self.game:isOver()
end

function ChessPuzzlesScreen:getRoundOverButtons()
    local new_game = { text = _("New game"), callback = function() self:onNewGame() end }
    if self.game:isShowingSolution() then
        local back = { text = _("Step back"),    callback = function() self:onSolutionStep(-1) end }
        local fwd  = { text = _("Step forward"), callback = function() self:onSolutionStep(1) end }
        if self:isLandscape() then
            return { { back, fwd }, { new_game } }
        end
        return { { back, fwd, new_game } }
    end
    return { new_game }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

local function signed(n)
    return n >= 0 and ("+" .. n) or tostring(n)
end

function ChessPuzzlesScreen:updateStatus(msg)
    local g = self.game
    local p = g.puzzle
    local status
    if msg then
        status = msg
    elseif not p then
        status = ""
    elseif g:isShowingSolution() then
        status = self:joinStatus(T(_("Solution: move %1/%2"), g.sol_step, g:solutionLength()),
            T(_("Puzzle: %1"), p.rating))
    elseif g:isSolved() then
        local rating
        if g.ratable and g.delta then
            rating = T(_("Rating: %1"), T("%1 (%2)", self:getRating(), signed(g.delta)))
        end
        -- Kept short: portrait has one status line. A slip shows in the
        -- rating change.
        status = self:joinStatus(g.failed and _("Solved.") or _("Solved!"),
            T(_("Puzzle: %1"), p.rating), rating)
    else
        local side = g.board.turn == "white" and _("White to move") or _("Black to move")
        local where = g.daily and _("Daily Challenge") or BAND_LABELS[self:_getBand()]
        status = self:joinStatus(where, T(_("Rating: %1"), self:getRating()), side)
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

return ChessPuzzlesScreen
