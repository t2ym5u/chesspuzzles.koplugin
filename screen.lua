local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local DailySeed   = require("daily_seed")
local MenuHelper  = require("menu_helper")
local Party       = require("party")
local BoardWidget = lrequire("board_widget")
local Game        = lrequire("game")
local Puzzles     = lrequire("puzzles")
local Rating      = lrequire("rating")
local PartyMatch  = lrequire("party_match")

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

local GAME_RULES_PARTY_EN = [[
Chess Puzzles · multiplayer — Rules

For 2 to 8 players, or teams, around one reader laid on the table. Everyone looks at the same puzzle; the fastest correct solver scores.

Setup (title-bar menu)
• Players: how many; Player names: type each name (remembered). Play as: Teams to play in teams instead (Teams, Team names — remembered apart).
• Difficulty: every puzzle of the match comes from this band — Beginner (under 1000), Easy (1000–1399), Medium (1400–1799), Hard (1800–2199), Expert (2200+).
• Puzzles: 3, 5 or 10 per match.
• Time: 1, 2, 3 or 5 minutes per puzzle, or No limit.

A puzzle
• The board is shown after the opponent's move (highlighted); the side to move is in the status line. The clock starts.
• Whoever thinks they have it taps "I have it!" (or taps the board) and picks their name in "Who has it?". The clock stops while they play.
• They play the moves on the board: tap a piece, then its square. The opponent answers each right move; any checkmate counts.
• The whole solution right wins the puzzle's points. One wrong move and that player is out for this puzzle: the position goes back to the start, the clock runs again and the others may try.
• Hint (between attempts, for everyone): first the piece to move, then its square. Each hint takes 1 point off the puzzle.
• The puzzle ends when it is solved, when everyone is out, when the time is up or when Show solution is used — nobody scores then, and the solution can be stepped through. "Next puzzle" deals the next one.

Scoring
• Beginner 1, Easy 2, Medium 3, Hard 4, Expert 5 points, plus 1 for each move to find beyond the first (a Medium mate in 2 is worth 4). Each hint: −1, never below 1. The status line shows what the puzzle is worth now.

End of the match
• After the last puzzle the final scores are shown: the highest total wins. Equal totals are a tie.
• "New game" starts a new match. Closing the reader keeps the match (an attempt in progress starts over).
• Multiplayer puzzles never change your solo rating, statistics or seen puzzles.
]]

local GAME_RULES_PARTY_FR = [[
Problèmes d'échecs · à plusieurs — Règles

De 2 à 8 joueurs, ou des équipes, autour d'une seule liseuse posée sur la table. Tout le monde regarde le même problème ; le plus rapide à le résoudre marque.

Préparation (menu de la barre de titre)
• Joueurs : combien ; Noms des joueurs : tapez chaque nom (ils sont mémorisés). Vous jouez : Équipes pour jouer en équipes (Équipes, Noms des équipes — mémorisés à part).
• Difficulté : tous les problèmes de la partie viennent de cette tranche — Débutant (moins de 1000), Facile (1000–1399), Moyen (1400–1799), Difficile (1800–2199), Expert (2200 et plus).
• Problèmes : 3, 5 ou 10 par partie.
• Durée : 1, 2, 3 ou 5 minutes par problème, ou Sans limite.

Un problème
• L'échiquier est montré après le coup de l'adversaire (en surbrillance) ; le camp au trait est dans la ligne d'état. Le chrono démarre.
• Celui qui pense avoir trouvé touche « Je l'ai ! » (ou l'échiquier) et choisit son nom dans « Qui l'a ? ». Le chrono s'arrête pendant qu'il joue.
• Il joue les coups sur l'échiquier : touchez une pièce, puis sa case. L'adversaire répond à chaque bon coup ; tout mat compte.
• La solution complète rapporte les points du problème. Un seul mauvais coup et ce joueur est éliminé pour ce problème : la position revient au départ, le chrono repart et les autres peuvent essayer.
• Astuce (entre deux essais, pour tous) : d'abord la pièce à jouer, puis sa case. Chaque astuce retire 1 point au problème.
• Le problème se termine quand il est résolu, quand tout le monde est éliminé, quand le temps est écoulé ou avec Voir la solution — personne ne marque alors, et on peut parcourir la solution. « Problème suivant » donne le suivant.

Points
• Débutant 1, Facile 2, Moyen 3, Difficile 4, Expert 5 points, plus 1 par coup à trouver au-delà du premier (un mat en 2 Moyen vaut 4). Chaque astuce : −1, jamais moins de 1. La ligne d'état indique ce que vaut le problème.

Fin de la partie
• Après le dernier problème, les scores finaux s'affichent : le plus haut total gagne. À total égal, c'est une égalité.
• « Nouvelle partie » relance une partie. Fermer la liseuse garde la partie (un essai en cours recommence).
• Les problèmes à plusieurs ne changent jamais votre classement, vos statistiques ni les problèmes vus en solo.
]]

local MODE_RULES = {
    solo  = { GAME_RULES_EN, GAME_RULES_FR },
    party = { GAME_RULES_PARTY_EN, GAME_RULES_PARTY_FR },
}

local PARTY_KEY = "party_state"

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
    self.user_flip = false
    self.party = self.plugin.launch_mode == "party"
    if self.party then
        self:_loadParty()
    else
        self:_loadSolo()
    end
    ScreenBase.init(self)
    self:_startCountdown()
end

function ChessPuzzlesScreen:_loadSolo()
    self.game = Game:new()
    self.match = nil
    local saved = self.plugin:loadState()
    local p = type(saved) == "table" and Puzzles.isBand(saved.band)
        and Puzzles.get(saved.band, tonumber(saved.index) or 0)
    if not (p and self.game:load(saved, p)) then
        self:_newPuzzle()
    end
end

-- The solo save (setting "state"); a match keeps its own key, so the solo
-- puzzle in progress is left as it was.
function ChessPuzzlesScreen:serializeState()
    if self.party then return self.plugin:loadState() end
    return self.game:serialize()
end

function ChessPuzzlesScreen:_save()
    if self.party then return self:_saveParty() end
    self.plugin:saveState(self.game:serialize())
end

function ChessPuzzlesScreen:closeScreen()
    self:_cancelReply()
    self:_stopCountdown()
    if self.party then self:_saveParty() end
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
    -- A multiplayer puzzle never touches the solo rating or statistics.
    if self.party or g.rated then return end
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
    if self.party then return self:onNewMatch() end
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
        if self.party then return self:_partyMenuItems() end
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
        table.insert(items, 5, { text = self:_modeLabel(), callback = function() self:_setMode("party") end })
        items[#items + 1] = self:makeModeRulesButtonConfig(MODE_RULES)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local hint     = { text = _("Hint"),          callback = function() self:onHint() end }
    local solution = { text = _("Show solution"), callback = function() self:onShowSolution() end }
    local action_bar
    if self.party then
        local m = self.match
        hint.enabled = m.player == nil
        local claim = { text = _("I have it!"), enabled = m.player == nil,
                        callback = function() self:_askWhoHasIt() end }
        action_bar = self:buildActionBar(is_landscape
            and { { claim }, { hint }, { solution } }
            or  { claim, hint, solution })
    else
        -- The landscape side panel is too narrow for both labels on one row.
        action_bar = self:buildActionBar(is_landscape
            and { { hint }, { solution } }
            or  { hint, solution })
    end
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }
    self.header_widget, self.header_frame, self.scores_widget = nil, nil, nil
    if self.party then self:_addPartyHeader(controls) end

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
    if self.party and not self.match.player then
        -- Nobody on the move yet: a tap on the board is a claim.
        if not self.match:isPuzzleOver() then self:_askWhoHasIt() end
        return
    end
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
    if self.party then return self:_partyMoveResult(result) end
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
    -- Multiplayer: a hint is for everyone, between attempts, and costs the
    -- puzzle a point.
    if self.party then
        if self.match.player or self.match:isPuzzleOver() then return end
        self.match:hint()
    end
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
    if self.party then
        if self.match:isPuzzleOver() then return end
        self.match:giveUp()
        g:showSolution()
        return self:_onPuzzleEnd()
    end
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
    if self.party then return self.match:isPuzzleOver() end
    return self.game:isOver()
end

function ChessPuzzlesScreen:getRoundOverButtons()
    if self.party then return self:_partyRoundOverButtons() end
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
    if self.party then
        status = msg or self:_partyStatus()
        if self.header_widget then self.header_widget:setText(self:_headerText()) end
        if self.scores_widget then self.scores_widget:setText(self:_scoresText()) end
    elseif msg then
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

-- ---------------------------------------------------------------------------
-- Mode: solo / multiplayer
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_modeLabel()
    return T(_("Mode: %1"), self.party and _("Multiplayer") or _("Solo"))
end

-- Switching starts a multiplayer match; back to solo, the solo puzzle in
-- progress comes back (its save is never touched by a match).
function ChessPuzzlesScreen:_setMode(mode)
    self:_cancelReply()
    self:_stopCountdown()
    self:_save()
    self.plugin.launch_mode = mode
    self.party = mode == "party"
    self.user_flip = false
    self.marks = nil
    if self.party then
        self:_newMatch()
    else
        self:_loadSolo()
    end
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:_startCountdown()
end

-- ---------------------------------------------------------------------------
-- Multiplayer match
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_teams()
    -- Not "party_teams": party.lua keeps the team names under that key.
    return self.plugin:getSetting("party_play_teams", false) and true or false
end

-- party.lua options: teams get their own labels and remembered names/count.
function ChessPuzzlesScreen:_seatOpts()
    return self:_teams() and { teams = true } or nil
end

function ChessPuzzlesScreen:_loadSeats()
    local opts = self:_seatOpts()
    return Party.loadPlayers(self.plugin, Party.loadCount(self.plugin, opts), opts)
end

function ChessPuzzlesScreen:_partyBand()
    local b = self.plugin:getSetting("party_band", "easy")
    return Puzzles.isBand(b) and b or "easy"
end

function ChessPuzzlesScreen:_partyOptions()
    return {
        rounds   = self.plugin:getSetting("party_rounds", 5),
        duration = self.plugin:getSetting("party_duration", 120),
        band     = self:_partyBand(),
    }
end

function ChessPuzzlesScreen:_newMatch()
    self.game = Game:new()
    self.match = PartyMatch.new(self:_loadSeats(), self:_partyOptions())
    self:_dealPuzzle()
end

-- The next puzzle of the match: from its band, never one already dealt in
-- it. Nothing is marked seen: the solo progress stays as it was.
function ChessPuzzlesScreen:_dealPuzzle()
    local m = self.match
    local band, index = Puzzles.pick{
        band    = m.band,
        is_seen = function(b, i) return b == m.band and m:wasUsed(i) end,
    }
    local p = band and Puzzles.get(band, index)
    if not p then return false end
    self:_cancelReply()
    self.game:setPuzzle(p, nil, false)
    m:startPuzzle(index, self.game:playerMoveCount())
    self.user_flip = false
    self.marks = nil
    self:_saveParty()
    return true
end

function ChessPuzzlesScreen:_loadParty()
    self.game = Game:new()
    local t = self.plugin:loadState(PARTY_KEY)
    local m = type(t) == "table" and PartyMatch.restore(t.match)
    local g = type(t) == "table" and type(t.game) == "table" and t.game
    local p = m and g and Puzzles.isBand(g.band) and Puzzles.get(g.band, tonumber(g.index) or 0)
    if p and self.game:load(g, p) then
        self.match = m
        -- An attempt cut short by closing the reader starts over.
        if m.player and not self.game:isOver() and self.game:ply() > 1 then
            self.game:setPuzzle(p, nil, false)
        end
    else
        self:_newMatch()
    end
end

function ChessPuzzlesScreen:_saveParty()
    if not self.match then return end
    self.plugin:saveState({ match = self.match:serialize(), game = self.game:serialize() }, PARTY_KEY)
end

function ChessPuzzlesScreen:_rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function ChessPuzzlesScreen:onNewMatch()
    self:_stopCountdown()
    self:_newMatch()
    self:_rebuild()
    self:_startCountdown()
end

function ChessPuzzlesScreen:onNextPuzzle()
    local m = self.match
    if not m:isPuzzleOver() or m:isLastRound() then return end
    self:_dealPuzzle()
    self:_rebuild()
    self:_startCountdown()
end

-- "Who has it?": the players not out yet; picking one starts their attempt.
function ChessPuzzlesScreen:_askWhoHasIt()
    local m = self.match
    if m.player or m:isPuzzleOver() then return end
    local seats, names = m:remaining(), {}
    for k, i in ipairs(seats) do names[k] = m.scores.names[i] end
    Party.askWhoFound(names, {
        title   = _("Who has it?"),
        on_pick = function(k)
            if k then self:onClaim(seats[k]) end
        end,
    })
end

function ChessPuzzlesScreen:onClaim(i)
    if not self.match:claim(i) then return end
    self:_stopCountdown()
    self.game.board.selected = nil
    self.marks = nil
    self:_saveParty()
    self:_rebuild()
end

function ChessPuzzlesScreen:_partyMoveResult(result)
    local g, m = self.game, self.match
    self.marks = nil
    if result == "illegal" then return end
    if result == "correct" then
        self:_save()
        self:_refreshBoard()
        self:updateStatus(_("Correct! Keep going."))
        self:_scheduleReply()
        return
    end
    local name = m.scores.names[m.player]
    if result == "solved" then
        local pts = m:solved()
        return self:_onPuzzleEnd(T(_("%1 solved it! +%2"), name, pts))
    end
    -- Wrong: out for this puzzle, the position back to the start.
    local all_out = m:wrong()
    g:setPuzzle(g.puzzle, nil, false)
    if all_out then
        g:showSolution()
        return self:_onPuzzleEnd()
    end
    self:_saveParty()
    self:_rebuild()
    self:updateStatus(T(_("Wrong move: %1 is out."), name))
    self:_startCountdown()
end

function ChessPuzzlesScreen:_onPuzzleEnd(msg)
    self:_cancelReply()
    self:_stopCountdown()
    self.game.board.selected = nil
    self.marks = nil
    self:_saveParty()
    self:_rebuild()
    if msg then self:updateStatus(msg) end
    self:_showScores()
end

function ChessPuzzlesScreen:_showScores()
    local m = self.match
    if m:isOver() then
        Party.showScoreboard(m.scores, { final = true })
    else
        Party.showScoreboard(m.scores, { title = T(_("Puzzle %1/%2"), m:round(), m.rounds) })
    end
end

function ChessPuzzlesScreen:_partyRoundOverButtons()
    local m = self.match
    local scores = { text = _("Scores"), callback = function() self:_showScores() end }
    local next_btn = m:isLastRound()
        and { text = _("New game"), callback = function() self:onNewMatch() end }
        or  { text = _("Next puzzle"), callback = function() self:onNextPuzzle() end }
    if self.game:isShowingSolution() then
        return {
            { { text = _("Step back"),    callback = function() self:onSolutionStep(-1) end },
              { text = _("Step forward"), callback = function() self:onSolutionStep(1) end } },
            { scores, next_btn },
        }
    end
    return { scores, next_btn }
end

function ChessPuzzlesScreen:_partyStatus()
    local g, m = self.game, self.match
    if g:isShowingSolution() then
        return T(_("Solution: move %1/%2"), g.sol_step, g:solutionLength())
    end
    if m.result == "solved" then
        return T(_("%1 solved it! +%2"), m.scores.names[m.winner] or "", m.value)
    end
    local side = g.board.turn == "white" and _("White to move") or _("Black to move")
    if m.player then
        return self:joinStatus(T(_("%1 plays"), m.scores.names[m.player]), side)
    end
    local out = {}
    for i, s in ipairs(m.scores.names) do
        if m:isOut(i) then out[#out + 1] = s end
    end
    return self:joinStatus(side, T(_("Points: %1"), m.value),
        #out > 0 and T(_("Out: %1"), table.concat(out, ", ")) or nil)
end

-- "Puzzle 2/5 · 1:42"; once over, how it ended in place of the clock.
function ChessPuzzlesScreen:_headerText()
    local m = self.match
    local round = T(_("Puzzle %1/%2"), m:round(), m.rounds)
    local ends = {
        solved   = _("Solved!"),
        all_out  = _("Everyone is out."),
        time_up  = _("Time's up!"),
        given_up = _("Solution"),
    }
    if m.result then return self:joinStatus(round, ends[m.result]) end
    if not m:hasClock() then return round end
    local t = m.time_left
    return self:joinStatus(round, string.format("%d:%02d", math.floor(t / 60), t % 60))
end

-- "Alice 7 · Bob 14", a line only breaking between players; with `pad`,
-- every total reads `pad` (to measure the widest it can get).
function ChessPuzzlesScreen:_scoresText(pad)
    local scores = self.match.scores
    local parts = {}
    for i, s in ipairs(scores.names) do
        parts[i] = (s .. " " .. (pad or scores.points[i] or 0)):gsub(" ", "\u{00A0}")
    end
    return table.concat(parts, ScreenBase.STATUS_SEP)
end

-- Round and clock on a bold line, the scores under it, both above the
-- status line; heights reserved for the longest text each can show, so
-- nothing moves during the match.
function ChessPuzzlesScreen:_addPartyHeader(controls)
    local w = self:getControlsWidth()
    local function reserved(texts, face, bold)
        local h = 0
        for _i, text in ipairs(texts) do
            local tb = TextBoxWidget:new{ text = text, face = face, bold = bold,
                width = w, alignment = "center" }
            h = math.max(h, tb:getSize().h)
            tb:free()
        end
        return h
    end
    local m = self.match
    local round = T(_("Puzzle %1/%2"), m.rounds, m.rounds)
    local header_face = Font:getFace("cfont", 24)
    self.header_widget = TextBoxWidget:new{
        text = self:_headerText(), face = header_face, bold = true,
        width = w, alignment = "center",
        height = reserved({
            self:joinStatus(round, "00:00"),
            self:joinStatus(round, _("Everyone is out.")),
            self:joinStatus(round, _("Time's up!")),
        }, header_face, true),
    }
    -- Its own frame: the countdown repaints this box only.
    self.header_frame = FrameContainer:new{
        padding = 0, margin = 0, bordersize = 0,
        self.header_widget,
    }
    local face = Font:getFace("smallinfofont")
    self.scores_widget = TextBoxWidget:new{
        text = self:_scoresText(), face = face, bold = true,
        width = w, alignment = "center",
        height = reserved({ self:_scoresText("000") }, face, true),
    }
    table.insert(controls, 1, self.header_frame)
    table.insert(controls, 2, self.scores_widget)
    table.insert(controls, 3, VerticalSpan:new{ width = Size.span.vertical_default })
end

function ChessPuzzlesScreen:_partyMenuItems()
    local plugin, m = self.plugin, self.match
    local opts = self:_partyOptions()
    local items = {
        { text = _("New game"), callback = function() self:onNewMatch() end },
        { text = T(self:_teams() and _("Teams: %1") or _("Players: %1"), #m.scores.names), callback = function()
            Party.pickCount(plugin, function() self:onNewMatch() end, self, self:_seatOpts())
        end },
        { text = self:_teams() and _("Team names") or _("Player names"), callback = function()
            Party.editPlayers(plugin, m.scores.names, function()
                self:_saveParty()
                self:updateStatus()
            end, self, self:_seatOpts())
        end },
        { text = T(_("Play as: %1"), self:_teams() and _("Teams") or _("Players")), callback = function()
            plugin:saveSetting("party_play_teams", not self:_teams())
            self:onNewMatch()
        end },
        { text = T(_("Difficulty: %1"), BAND_LABELS[opts.band]), callback = function()
            local list = {}
            for _i, id in ipairs(Puzzles.BANDS) do
                list[#list + 1] = { id = id, text = self:joinStatus(BAND_LABELS[id], BAND_RANGES[id]) }
            end
            self:_pickSetting(_("Difficulty"), "party_band", opts.band, list)
        end },
        { text = T(_("Puzzles: %1"), opts.rounds), callback = function()
            local list = {}
            for _i, n in ipairs(PartyMatch.ROUNDS) do list[#list + 1] = { id = n, text = tostring(n) } end
            self:_pickSetting(_("Puzzles"), "party_rounds", opts.rounds, list)
        end },
        { text = T(_("Time: %1"), self:_durationLabel(opts.duration)), callback = function()
            local list = {}
            for _i, d in ipairs(PartyMatch.DURATIONS) do list[#list + 1] = { id = d, text = self:_durationLabel(d) } end
            self:_pickSetting(_("Time"), "party_duration", opts.duration, list)
        end },
        { text = self:_modeLabel(), callback = function() self:_setMode("solo") end },
    }
    if not m:isPuzzleOver() then
        items[#items + 1] = { text = _("Show solution"), callback = function() self:onShowSolution() end }
    end
    items[#items + 1] = { text = _("Flip board"), callback = function() self:onFlipBoard() end }
    items[#items + 1] = self:makeModeRulesButtonConfig(MODE_RULES)
    return items
end

-- A match setting: saved, then a new match starts with it.
function ChessPuzzlesScreen:_pickSetting(title, key, current, items)
    MenuHelper.openPickerMenu{
        title      = title,
        items      = items,
        current_id = current,
        parent     = self,
        on_select  = function(v)
            self.plugin:saveSetting(key, v)
            self:onNewMatch()
        end,
    }
end

function ChessPuzzlesScreen:_durationLabel(secs)
    if not secs or secs <= 0 then return _("No limit") end
    if secs < 60 then return T(_("%1 s"), secs) end
    return T(_("%1 min"), math.floor(secs / 60))
end

-- ---------------------------------------------------------------------------
-- Countdown: one tick a second, repainting the header box only. It does not
-- run during an attempt.
-- ---------------------------------------------------------------------------

function ChessPuzzlesScreen:_startCountdown()
    self:_stopCountdown()
    local m = self.match
    if not (self.party and m and m:hasClock()) or m:isPuzzleOver() or m.player then return end
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function ChessPuzzlesScreen:_stopCountdown()
    -- Any pending tick sees a newer generation and does nothing.
    self._tick_gen = (self._tick_gen or 0) + 1
end

function ChessPuzzlesScreen:_onTick(gen)
    if gen ~= self._tick_gen or not self.party then return end
    if self.match:tick() then
        self.game:showSolution()
        return self:_onPuzzleEnd()
    end
    if self.header_widget then
        self.header_widget:setText(self:_headerText())
        local frame = self.header_frame
        UIManager:setDirty(self, function() return "fast", frame.dimen end)
    end
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

return ChessPuzzlesScreen
