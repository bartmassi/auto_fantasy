pico-8 cartridge // http://www.pico-8.com
version 32

__lua__
--TODO:
--Cursor refactors 
--	*make cursor class handle depressed button detection
--	*lock based on state changes rather than times.
--
--Graphics
-- * sprites
-- * battle animations
--Sound
-- * shop music
-- * battle music
--Combat
-- * core logic
-- * unit stat growth
-- * enemy progression by level
-- * rather than using actions that apply status effects w tick conditions that apply buffs, have actions that apply buffs with "trigger types" (e.g., on damage, on attack, time)
--Game over screen
-- * game over restart loop


DIFFICULTY_INCREMENT = 1
PARTY_MAX_SIZE = 4
SHOP_SLOTS = 3
MAX_MAP_SIZE = 6
MAX_LEVEL = 6 --gray, green, blue, purple, orange, pink
ATB_GAUGE_SIZE = 100
VISIBLE_REPORT_LIMIT = 5
FIGHT_UPDATE_TIMEOUT = 60

--------------------------------------------------Helper functions

--concatenates two arrays
--will not function as intended on non-arrays
function arrayConcat(a, b)	
	local c = {}
	
	for k,v in ipairs(a) do add(c, v) end
	for k,v in ipairs(b) do add(c, v) end
	
	return c
end

----------------------------------------------------Player Control

Cursor = {}
Cursor.maxLockoutTime = 7
Cursor.scrollLockout = Cursor.maxLockoutTime
Cursor.buttonLockout = Cursor.maxLockoutTime

function Cursor:isScrollFree()
	if(self.scrollLockout>0) then
		return false
	else
		return true
	end
end

function Cursor:isButtonFree()
	if(self.buttonLockout>0) then
		return false
	else
		return true
	end
end

function Cursor:lockScroll()
	self.scrollLockout = Cursor.maxLockoutTime
end

function Cursor:lockButton()
	self.buttonLockout = Cursor.maxLockoutTime
end

function Cursor:tick()
	self.scrollLockout -=1
	self.buttonLockout -=1
end

----------------------------------------------------UNIT DATA

User = {}
User.__index = User
User.units = {}
User.numUnits = 0

function User:initialize()
	self.units = {}
end

function User:canBuy(unit)
	return true
end

function User:owns(unit)
	return self.units[unit.id] ~= nil
end

function User:upgrade(unit, n)
	self.units[unit.id]:upgrade(n)
end

function User:addUnit(unit)
	self.units[unit.id] = unit
end

function User:replace(replacedUnit, newUnit)
	self.units[replacedUnit.id] = nil
	self.units[newUnit.id] = newUnit
end

function User:getUnitArray()
	local unitArray = {}
	local i = 1
	for _, unit in pairs(self.units) do
		unitArray[i] = unit
		i += 1
	end
	return unitArray
end

----------------------------------------------------MAP DATA
Stage = {}
Stage.__index = Stage
Stage.difficulty = 0
Stage.next = nil

function Stage:growStageTree(depth)
	if depth == 0 then return self end
	local nextStage = {}
	setmetatable(nextStage, Stage)
	nextStage.difficulty = self.difficulty+DIFFICULTY_INCREMENT
	self.next = nextStage
	return nextStage:growStageTree(depth-1, nextStage.difficulty)
end

function Stage:getMonsters()
end

GameMap = {}
GameMap.__index = GameMap
GameMap.current = {}
GameMap.first = {}
GameMap.tail = {}
GameMap.mapNumber = 0
GameMap.indexInMap = 0

function GameMap:create()
	local firstStage = {}
	setmetatable(firstStage, Stage)
	
	self.current = firstStage
	self.first = firstStage
	self.tail = firstStage
	self.mapNumber = 0
end

function GameMap:advance()

	if(self.indexInMap == MAX_MAP_SIZE) then
		self.indexInMap = 0
		self.mapNumber = self.mapNumber + 1
		self.tail = self.tail:growStageTree(MAX_MAP_SIZE)
		self.first = self.tail.next
	else 
		self.indexInMap = self.indexInMap + 1
	end
	
	return State.SHOP

end



----------------------------------------------------STATE DATA AND MANIPULATION
State = {
	SHOP=1,
	FIGHT=2,
	GAME_OVER=3,
	VICTORY=4,
	INIT=5,
	TRAVEL_TO_FIGHT=6,
}

Shop = {}

function Shop:initialize(slots)
	Cursor:lockScroll()
	Cursor:lockButton()
	
	Shop.playerShopping = true
	Shop.storeCursorPosition = 1
	Shop.inventoryCursorPosition = 1
	--select slots random keys from AllyDatabase
	Shop.store = AllyDatabase:selectWithoutReplacement(SHOP_SLOTS)
	Shop.userInventoryPositions = Player:getUnitArray()
	
end

--shop has SHOP_SLOTS+PARTY_MAX_SIZE+1 possible cursor positions
function Shop:updateState()

	--left 
	if btn(0) and Cursor:isScrollFree() then 
		if(Shop.playerShopping and Shop.storeCursorPosition > 1) then
			Shop.storeCursorPosition -= 1
			Cursor:lockScroll()
		elseif (not Shop.playerShopping) and Shop.inventoryCursorPosition > 1 then
			Shop.inventoryCursorPosition -= 1
			Cursor:lockScroll()
		end
	--right
	elseif btn(1) and Cursor:isScrollFree() then 
		if(Shop.playerShopping and Shop.storeCursorPosition <= SHOP_SLOTS) then
			Shop.storeCursorPosition += 1
			Cursor:lockScroll()
		elseif (not Shop.playerShopping) and Shop.inventoryCursorPosition < Player.numUnits then
			Shop.inventoryCursorPosition += 1
			Cursor:lockScroll()
		end
	--
	elseif btn(4) and Cursor:isButtonFree() then
		if Shop.playerShopping then
			if(Shop.storeCursorPosition == SHOP_SLOTS+1) then
				return State.TRAVEL_TO_FIGHT
			else
				local targetUnit = Shop.store[Shop.storeCursorPosition]
				if Player:canBuy(targetUnit) then
					if Player:owns(targetUnit) then 
						Player:upgrade(targetUnit, 1)
						return State.TRAVEL_TO_FIGHT
					else
						if(Player.numUnits == PARTY_MAX_SIZE) then
							Shop.playerShopping = false
							Shop.inventoryCursorPosition = 1
							Cursor:lockButton()
						else
							Player:addUnit(targetUnit)
							Player.numUnits += 1
							return State.TRAVEL_TO_FIGHT
						end
					end
				else
					playSound(WRONG)
				end
			end
		else
			local replacedUnit = Shop.userInventoryPositions[Shop.inventoryCursorPosition]
			local newUnit = Shop.store[Shop.storeCursorPosition]
			Player:replace(replacedUnit, newUnit)
			return State.TRAVEL_TO_FIGHT
		end
	elseif btn(5) and Cursor:isButtonFree() then
		if not Shop.playerShopping then
			Shop.playerShopping = true
			Shop.inventoryCursorPosition = 1
			Cursor:lockButton()
		end
	end
	
	return State.SHOP
end

function Shop:draw()

	local increment = 20
	print('store cursor position: ' .. Shop.storeCursorPosition, 0, increment, 7)

	local storeString = 'S: '
	for i = 1, #Shop.store do
		storeString = storeString .. Shop.store[i].id .. ', '
	end
	print(storeString, 0, 2*increment, 7)

	print('inventory cursor position: ' .. Shop.inventoryCursorPosition, 0, 3*increment, 7)
	
	local inventoryString = 'I: '
	for i = 1, #Shop.userInventoryPositions do
		inventoryString = inventoryString .. Shop.userInventoryPositions[i].id .. 
			'(' .. Shop.userInventoryPositions[i].level .. '), '
	end
	print(inventoryString, 0, 4*increment, 7)
	
	print('player shopping: ' .. tostring(Shop.playerShopping), 0, 5*increment, 7)
	
	print('map ' .. tostring(Map.indexInMap) .. ' level ' .. tostring(Map.mapNumber), 0, 6*increment, 7)
end

-- Fight = {}

-- function Fight:initialize()
	-- self.transitDuration = 30*1
	-- self.framesTraveled = 0
-- end

-- function Fight:doneWaiting()
	-- self.framesTraveled += 1
	-- return self.framesTraveled >= self.transitDuration
-- end

-- function Fight:updateState()
	-- if(self:doneWaiting()) then
		-- return State.VICTORY
	-- else
		-- return State.FIGHT
	-- end
-- end

-- function Fight:draw()
	-- print('fighting !', 2, 20, 7)
-- end

Fight = {}

function Fight:drawHP(units, xpos, color)
	local increment = 7
	for i,u in ipairs(units) do
		print(u.name .. ': ' .. u.stats.hp, xpos, 5+i*increment, color)
	end
end

function Fight:drawNeutral()
	self:drawHP(self.allies, 2, 12)
	self:drawHP(self.enemies, 80, 8)
end

function Fight:updateVisibleReports()
	if(Fight.queuedReports == nil) then return end
	
	--enqueue new reports
	for _, v in ipairs(Fight.queuedReports) do
		add(Fight.visibleReports, v)
		--dequeue old reports
		if(#Fight.visibleReports > VISIBLE_REPORT_LIMIT) then
			deli(Fight.visibleReports, 1)
		end
	end
	Fight.queuedReports = nil
end

function Fight:drawReports()
	
	self:updateVisibleReports()

	--draw reports
	local increment = 7
	for i, v in ipairs(Fight.visibleReports) do
		print(v, 2, 80+i*increment, 7)
	end
	--assert(1==0, #Fight.visibleReports)
end

function Fight:makeUnitsFromPrototypes(prototypes)
	local units = {}
	for i,u in pairs(prototypes) do
		units[i] = {}
		setmetatable(units[i], u)
		units[i].stats = {}
		setmetatable(units[i].stats, u.stats)
		units[i].statusEffects = {}
		units[i].buffs = {}
		units[i].turnTimer = 0
	end
	return units
end

function Fight:handleEffect(user, target, effectFunction, sourceName, sourceEvent)

	local reports = {user.name .. " used " .. sourceName .. " [" .. sourceEvent .. "] "}
	
	if(effectFunction == nil) then
		return reports
	end
	
	local effect = effectFunction(user, target)
	
	if(effect.targetDamage != nil) then
		target.stats.hp -= effect.targetDamage
		add(reports, target.name .. " took " .. effect.targetDamage .. " damage!")
	end
	
	return reports
end

function Fight:handleDeath(units)
	local deadUnitIndices = {}
	local deathReports = {}
	
	for ui,u in ipairs(units) do
		if(u.stats.hp <= 0) then 
			add(deadUnitIndices, ui) 
		end
	end
	
	for _,ui in ipairs(deadUnitIndices) do
		add(deathReports, units[ui].name .. ' died!')
		deli(units, ui)
	end
	
	return deathReports
	
end

function Fight:checkAndHandleDeath()
	return arrayConcat(self:handleDeath(self.allies), self:handleDeath(self.enemies))
end

function Fight:statusTicks(units)
	local effectReports = {}
	local deadUnits = {}
	for ui, u in ipairs(units) do
		--TODO: Keep track of the source of status effects (player, move)
		for si, s in ipairs(u.statusEffects) do
			if(s.duration > 0) then
				local reports = self:handleEffect(u, u, s.tick, s.name, "tick")
				arrayConcat(effectReports, reports)
				s.duration = s.duration - 1
			else
				local reports = self:handleEffect(u, u, s.expiration, s.name, "expiration")
				arrayConcat(effectReports, reports)
				deli(u.statusEffects, si)
			end
		end
		
	end
		
	return arrayConcat(effectReports, self:checkAndHandleDeath())
end

function Fight:combatTicks(units)
	local activeUnits = {}
	
	for _,u in ipairs(units) do
		u.turnTimer += u.stats.speed
		--assert(u.turnTimer == -100, u.name .. ' timer is ' .. u.turnTimer .. '(speed=' .. u.stats.speed)
		if(u.turnTimer >= ATB_GAUGE_SIZE) then
			add(activeUnits, u)
			u.turnTimer = ATB_GAUGE_SIZE - u.turnTimer
		end
	end

	return activeUnits
end

function Fight:processAction(activeUnit)

	local reports = {}

	local chosenAction = activeUnit:chooseAction()
	local targetingFunction = TargetingFunctions:get(chosenAction.targeting)
	local chosenTarget = 0
	if(activeUnit.isEnemy) then
		chosenTarget = targetingFunction(self.allies, self.enemies)
	else
		chosenTarget = targetingFunction(self.enemies, self.allies)
	end
	local effect = StatusEffectDatabase:get(chosenAction.effect)
	
	add(chosenTarget.statusEffects, effect)
	reports = arrayConcat(reports, self:handleEffect(activeUnit, chosenTarget, effect.application, effect.name, "application"))	
		
	return chosenAction, arrayConcat(reports, self:checkAndHandleDeath())

end

function Fight:initialize()
	--TODO build a smarter way to select enemies based on map level
	self.enemies = self:makeUnitsFromPrototypes(EnemyDatabase:selectWithoutReplacement(1))
	self.allies = self:makeUnitsFromPrototypes(Player:getUnitArray())
	

	self.activeUnitQueue = {}
	self.animationActive = false
	self.totalCombatTicks = 0
	self.visibleReports = {}
	self.activeAnimation = nil
	self.stateTimeout = FIGHT_UPDATE_TIMEOUT
	
end

function Fight:doneWaiting()

end

function Fight:updateState()

	self.stateTimeout = self.stateTimeout - 1

	if(self.activeAnimation != nil) then return end
	if(self.stateTimeout > 0) then return end
	
	--advance combat until we queue a unit
	local allyEffectReports = {}
	local enemyEffectReports = {}
	local newAllyReports = {}
	local newEnemyReports = {}
		
	while(#self.activeUnitQueue == 0) do
		if(#self.allies == 0) then return State.GAME_OVER end
		if(#self.enemies == 0) then return State.VICTORY end
		
		newAllyReports = self:statusTicks(self.allies)
		newEnemyReports = self:statusTicks(self.enemies)
		if(#newAllyReports > 0) then 
			allyEffectReports = arrayConcat(allyEffectReports, newAllyReports)
		end
		if(#newEnemyReports > 0) then 
			enemyEffectReports = arrayConcat(enemyEffectReports, newEnemyReports)
		end
		
		--TODO: randomize this output
		self.activeUnitQueue = arrayConcat(self:combatTicks(self.allies), self:combatTicks(self.enemies))
		self.totalCombatTicks = self.totalCombatTicks + 1
	end
	
	local chosenAction, actionReports = self:processAction(deli(self.activeUnitQueue))
	self.activeAnimation = {}
	setmetatable(self.activeAnimation, AnimationDatabase:get(chosenAction.animation))
	
	Fight.queuedReports = arrayConcat(arrayConcat(allyEffectReports, enemyEffectReports), actionReports)
	
	--Lock state again
	self.stateTimeout = FIGHT_UPDATE_TIMEOUT
	
end

function Fight:draw()
	Fight:drawNeutral()
	Fight:drawReports()
	if(self.activeAnimation != nil) then
		self.activeAnimation:draw()
		self.activeAnimation.timer = self.activeAnimation.timer - 1
		if(self.activeAnimation.timer == 0) then
			self.activeAnimation = nil
		end		
	end
end

GameOverScreen = {}

function GameOverScreen:initialize()
	Cursor:lockScroll()
	Cursor:lockButton()
	GameOverScreen.cursorPosition = 0
end

function GameOverScreen:updateState()
--if cursor on new game and enter depressed, set state to initialize
--if cursor on quit and enter depressed, quit game
--do nothing otherwise
end

function GameOverScreen:draw()
	print("game over bitch", 30, 30, 3)
end

Intermission = {}
Intermission.__index = Intermission

function Intermission:initialize()
	self.transitDuration = 30*1
	self.framesTraveled = 0
end

function Intermission:doneWaiting()
	self.framesTraveled += 1
	return self.framesTraveled >= self.transitDuration
end

TravelToFight = {}
setmetatable(TravelToFight, Intermission)

function TravelToFight:updateState()
	if(self:doneWaiting()) then
		return State.FIGHT
	else
		return State.TRAVEL_TO_FIGHT
	end
end

function TravelToFight:draw()
	print("travel to fight..,", 30, 60, 7)
end

Victory = {}
setmetatable(Victory, Intermission)

function Victory:updateState()
	if(self:doneWaiting()) then
		return State.SHOP
	else
		return State.VICTORY
	end
end

function Victory:draw()
	print("win!,,", 30, 60, 7)
	
end

function handleNextState(currentState, nextState)

	if(currentState == nextState) then
		return
	end

	if nextState == State.SHOP then
		Shop:initialize()
		CurrentState =  State.SHOP
	elseif nextState == State.TRAVEL_TO_FIGHT then
		TravelToFight:initialize()
		CurrentState = State.TRAVEL_TO_FIGHT
	elseif nextState == State.FIGHT then
		Fight:initialize()
		CurrentState = State.FIGHT
	elseif nextState == State.VICTORY then
		Map:advance()
		Victory:initialize()
		CurrentState = State.VICTORY
	elseif nextState == State.GAME_OVER then
		CurrentState = State.GAME_OVER
	elseif nextState == State.INIT then
		CurrentState = State.INIT
	end
end
		

----------------------------------------------------SENSORY FUNCTIONS
function playSound(sound)
end


----------------------------------------------------MAIN FUNCTIONS

function _init()

	Player = {}
	setmetatable(Player, User)
	Player:initialize()

	Map = {}
	setmetatable(Map, GameMap)
	Map:create()
	Map.tail = Map.first:growStageTree(6, DIFFICULTY_INCREMENT)
	
	DBInit()
		
	Shop:initialize()
	CurrentState = State.SHOP
	
	return State.SHOP
end

function _update()
	Cursor:tick()

	if CurrentState == State.SHOP then
		nextState = Shop:updateState()
	elseif CurrentState == State.TRAVEL_TO_FIGHT then
		nextState = TravelToFight:updateState()
	elseif CurrentState == State.FIGHT then
		nextState = Fight:updateState()
	elseif CurrentState == State.GAME_OVER then
		nextState = GameOverScreen:updateState()
	elseif CurrentState == State.VICTORY then
		nextState = Victory:updateState()
	elseif CurrentState == State.INIT then
		nextState = _init()
	end
	
	handleNextState(CurrentState, nextState)
	
end

function _draw()
	cls()
	
	if CurrentState == State.SHOP then
		Shop:draw()
	elseif CurrentState == State.TRAVEL_TO_FIGHT then
		TravelToFight:draw()
	elseif CurrentState == State.FIGHT then
		Fight:draw()
	elseif CurrentState == State.GAME_OVER then
		GameOverScreen:draw()
	elseif CurrentState == State.VICTORY then
		Victory:draw()
	end
	
end

-----------------------------------------------------------------
----------------------------------------------------UNIT DATABASE
-----------------------------------------------------------------

Unit = {}
Unit.__index = Unit
Unit.name = "__default"
Unit.isEnemy = false
Unit.level = 0
Unit.actions = {}
Unit.stats = {}

function Unit:upgrade(n)
	self.level += n
	
	--TODO: build unit growth; apply growth
end

--TODO: make this smarter for each unit type
function Unit:chooseAction()
	return ActionDatabase:get(self.actions[1+flr(rnd(#self.actions))])
end

function Unit:indexTableFields()
	self.stats.__index = self.stats
	self.actions.__index = self.actions
end

Database = {}
Database.__index = Database
Database.elements = {}

function Database:get(ind)
	return self.elements[ind]
end

function Database:getKeyset()

	local keyset = {}
	local n = 0
	
	for k,v in pairs(self.elements) do
		n=n+1
		keyset[n]=k
	end
	
	return keyset
end

function Database:setElementMeta(metaClass)
	for _, element in pairs(self.elements) do
		element.__index = element
		setmetatable(element, metaClass)
		
		if(metaClass == Unit) then
			element:indexTableFields()
		end
	end
end

function Database:selectWithoutReplacement(n)
	local keyset = self:getKeyset()
	assert(n <= #keyset, 'requested ' .. tostring(n) .. ' elements from set of ' .. tostring(#keyset))
	
	local chosenElements = {}
	
	for i=1, n do
		local upperBound = #keyset - i + 1
		local elementIndex = 1+flr(rnd(upperBound))
		
		chosenElements[i] = {}
		chosenElements[i].__index = chosenElements[i]
		setmetatable(chosenElements[i], self.elements[keyset[elementIndex]])
		local holder = keyset[upperBound]
		keyset[upperBound] = keyset[elementIndex]
		keyset[elementIndex] = holder
	end
	
	return chosenElements
end

AllyDatabase = {}
setmetatable(AllyDatabase, Database)

function AllyDatabase:initialize()
	self.elements = {
		WAR={
			id = 'WAR',
			name = 'Warrior',
			actions = {'Attack'},
			stats =  {
				hp = 400,
				power = 4,
				threat = 4,
				speed = 2
			},
		},
		
		CLR={
			id = 'CLR',
			name = 'Cleric',
			actions = {'Attack'},--{ActionDatabase['Cure']},
			stats =  {
				hp = 400,
				power = 4,
				threat = 4,
				speed = 2
			},
		},
		
		WLK={
			id = 'WLK',
			name = 'Warlock',
			actions = {'Attack'},
			stats =  {
				hp = 400,
				power = 4,
				threat = 4,
				speed = 2
			},
		},
		
		KGT={
			id = 'KGT',
			name = 'Knight',
			actions = {'Attack'},
			stats =  {
				hp = 400,
				power = 4,
				threat = 4,
				speed = 2
			},
		},
		
		ROG={
			id = 'ROG',
			name = 'Rogue',
			actions = {'Attack'},
			stats =  {
				hp = 400,
				power = 4,
				threat = 4,
				speed = 2
			},
		},
	}
	
	self:setElementMeta(Unit)
	
end

EnemyDatabase = {}
setmetatable(EnemyDatabase, Database)

function EnemyDatabase:initialize()
	self.elements = {
		Goblin = {
			id = 'Goblin',
			name = 'Goblin',
			isEnemy = true,
			actions = {'Attack'},
			stats =  {
				hp = 100,
				power = 2,
				threat = 1,
				speed = 3
			},
		},
	}
	
	self:setElementMeta(Unit)
end

-----------------------------------------------------------------
-------------------------------------------------------ANIMATIONS
-----------------------------------------------------------------

Animation = {}
Animation.__index = Animation
function Animation:draw() end
Animation.timer = 0

AnimationDatabase = {}
setmetatable(AnimationDatabase, Database)

function AnimationDatabase:initialize()
	self.elements = {
		Attack = {
			timer = 15,
			draw = function () return nil end,
		},
		
		Cure = {
			timer = 20,
			draw = function () return nil end,
		},
	}
	self:setElementMeta(Animation)
end

-----------------------------------------------------------------
----------------------------------------------------------ACTIONS
-----------------------------------------------------------------

TargetingFunctions = {}
setmetatable(TargetingFunctions, Database)

function TargetingFunctions:initialize()
	self.elements = {
		AnyEnemy = function (enemies, allies) return enemies[1+flr(rnd(#enemies))] end,

		AllEnemies = function (enemies, allies) return enemies end,

		AnyAlly = function (enemies, allies) return allies[1+flr(rnd(#allies))] end,
			
		AllAllies = function (enemies, allies) return allies end,
	}
end

StatusEffect = {}
StatusEffect.__index = StatusEffect

StatusEffectDatabase = {}
setmetatable(StatusEffectDatabase, Database)


function StatusEffectDatabase:initialize()
	self.elements = {
	
		AttackDamage = {
			name = 'AttackDamage',
			duration=0,
			application=function (user, target) return {targetDamage=user.stats.power*10} end,
			tick=nil,
			check=nil,
			expiration=nil
		},
		
		SingleTargetHeal = {
			name = 'SingleTargetHeal',
			duration=0,
			application=function (user, target) return {targetDamage=-user.stats.power*15} end,
			tick=nil,
			check=nil,
			expiration=nil
		},
	}
	
	self:setElementMeta(StatusEffect)
end


Action = {}
Action.__index = Action

ActionDatabase = {}
setmetatable(ActionDatabase, Database)

function ActionDatabase:initialize()
	self.elements = {
	
		Attack = {
			name = 'Attack',
			targeting='AnyEnemy',
			effect='AttackDamage',
			animation='Attack'
		},
		
		Cure = {
			name = 'Cure',
			targeting='AnyAlly',
			effect='SingleTargetHeal',
			animation='Cure'
		},
	}
	
	self:setElementMeta(Action)
end

function DBInit()
	TargetingFunctions:initialize()
	AnimationDatabase:initialize()
	StatusEffectDatabase:initialize()
	ActionDatabase:initialize()
	AllyDatabase:initialize()
	EnemyDatabase:initialize()
end

__gfx__
00000000eeeeeeee3000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000e000000e33300033000111100c000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700e000000e0030033001110011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000e000000e00333300010000010c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000e000000e00033000010000010c000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700e000000e00333330010000110cc0cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000e000000e333000330110111000ccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000eeeeeeee3000000300111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001000101010100000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001010000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010101010101000001010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000001010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
