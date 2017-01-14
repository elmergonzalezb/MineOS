
---------------------------------------------------- Libraries ----------------------------------------------------

-- package.loaded.syntax = nil
-- package.loaded.GUI = nil
-- package.loaded.windows = nil
-- package.loaded.MineOSCore = nil

local args = {...}
require("advancedLua")
local component = require("component")
local gpu = component.gpu
local fs = require("filesystem")
local buffer = require("doubleBuffering")
local GUI = require("GUI")
local windows = require("windows")
local MineOSCore = require("MineOSCore")
local event = require("event")
local syntax = require("syntax")
local unicode = require("unicode")
local ecs = require("ECSAPI")
local keyboard = require("keyboard")

---------------------------------------------------- Constants ----------------------------------------------------

-- "/MineOS/Desktop/MineCode IDE.app/MineCode IDE.lua"

local workPath
local clipboard
local cursor = {
	position = {
		symbol = 20,
		line = 8
	},
	color = 0x00A8FF,
	symbol = "┃",
	blinkDelay = 0.4,
	blinkState = false,
}

local mainWindow = {}
local config = {
	indentaionWidth = 2,
	colorScheme = {
		topToolBar = 0xBBBBBB,
		topMenu = {
			backgroundColor = 0xEEEEEE,
			textColor = 0x444444,
			backgroundPressedColor = 0x3366CC,
			textPressedColor = 0xFFFFFF,
		},
	},
	scrollSpeed = 8,
}

---------------------------------------------------- Cursor methods ----------------------------------------------------

local function fixFromLineByCursorPosition()
	if mainWindow.codeView.fromLine > cursor.position.line then
		mainWindow.codeView.fromLine = cursor.position.line
	elseif mainWindow.codeView.fromLine + mainWindow.codeView.height - 2 < cursor.position.line then
		mainWindow.codeView.fromLine = cursor.position.line - mainWindow.codeView.height + 2
	end
end

local function fixFromSymbolByCursorPosition()
	if mainWindow.codeView.fromSymbol > cursor.position.symbol then
		mainWindow.codeView.fromSymbol = cursor.position.symbol
	elseif mainWindow.codeView.fromSymbol + mainWindow.codeView.codeAreaWidth - 3 < cursor.position.symbol then
		mainWindow.codeView.fromSymbol = cursor.position.symbol - mainWindow.codeView.codeAreaWidth + 3
	end
end

local function fixCursorPosition(symbol, line)
	if line < 1 then
		line = 1
	elseif line > #mainWindow.codeView.lines then
		line = #mainWindow.codeView.lines
	end

	local lineLength = unicode.len(mainWindow.codeView.lines[line])
	if symbol < 1 or lineLength == 0 then
		symbol = 1
	elseif symbol > lineLength then
		symbol = lineLength + 1
	end

	return symbol, line
end

local function setCursorPosition(symbol, line)
	cursor.position.symbol, cursor.position.line = fixCursorPosition(symbol, line)
	fixFromLineByCursorPosition()
	fixFromSymbolByCursorPosition()
end

local function convertScreenCoordinatesToCursorPosition(x, y)
	return x - mainWindow.codeView.codeAreaPosition + mainWindow.codeView.fromSymbol - 1, y - mainWindow.codeView.y + mainWindow.codeView.fromLine
end

local function clearSelection()
	mainWindow.codeView.selections[1] = nil
end

local function moveCursor(symbolOffset, lineOffset)
	local newSymbol, newLine = cursor.position.symbol + symbolOffset, cursor.position.line + lineOffset
	
	if newSymbol < 1 then
		newLine, newSymbol = newLine - 1, math.huge
	elseif newSymbol > unicode.len(mainWindow.codeView.lines[newLine] or "") + 1 then
		newLine, newSymbol = newLine + 1, 1
	end

	setCursorPosition(newSymbol, newLine)
end

local function setCursorPositionToEOF()
	setCursorPosition(unicode.len(mainWindow.codeView.lines[#mainWindow.codeView.lines]) + 1, #mainWindow.codeView.lines)
end

---------------------------------------------------- File processing methods ----------------------------------------------------

local function loadFile(path)
	mainWindow.codeView.fromLine, mainWindow.codeView.fromSymbol, mainWindow.codeView.lines, mainWindow.codeView.maximumLineLength = 1, 1, {}, 0
	local file = io.open(path, "r")
	for line in file:lines() do
		line = line:gsub("\t", string.rep(" ", config.indentaionWidth))
		table.insert(mainWindow.codeView.lines, line)
		mainWindow.codeView.maximumLineLength = math.max(mainWindow.codeView.maximumLineLength, unicode.len(line))
	end
	file:close()
	workPath = path
	setCursorPosition(1, 1)
end

local function saveFile(path)
	fs.makeDirectory(fs.path(path))
	local file = io.open(path, "w")
	for line = 1, #mainWindow.codeView.lines do
		file:write(mainWindow.codeView.lines[line], "\n")
	end
	file:close()
end

local function newFile()
	mainWindow.codeView.lines = {
		"",
		"for i = 1, 10 do",
		"  print(\"Hello world!\")",
		"end",
		""
	}
	setCursorPositionToEOF()
end

local function open()
	local data = ecs.universalWindow("auto", "auto", 30, ecs.windowColors.background, true,
		{"EmptyLine"},
		{"CenterText", 0x000000, "Open file"},
		{"EmptyLine"},
		{"Input", 0x262626, 0x880000, ""},
		{"EmptyLine"},
		{"Button", {0xAAAAAA, 0xffffff, "OK"}, {0x888888, 0xffffff, MineOSCore.localization.cancel}}
	)
	if data[2] == "OK" and fs.exists(data[1]) then
		loadFile(data[1])
		setCursorPosition(1, 1)
	end
end

local function saveAs()
	local data = ecs.universalWindow("auto", "auto", 30, ecs.windowColors.background, true,
		{"EmptyLine"},
		{"CenterText", 0x000000, "Save as"},
		{"EmptyLine"},
		{"Input", 0x262626, 0x880000, ""},
		{"EmptyLine"},
		{"Button", {0xAAAAAA, 0xffffff, "OK"}, {0x888888, 0xffffff, MineOSCore.localization.cancel}}
	)
	if data[2] == "OK" then
		saveFile(data[1])
	end
end

local function run()
	local loadSuccess, loadReason = load(table.concat(mainWindow.codeView.lines, "\n"))
	if loadSuccess then
		local oldResolutionX, oldResolutionY = gpu.getResolution()
		gpu.setBackground(0x262626); gpu.setForeground(0xFFFFFF); gpu.fill(1, 1, oldResolutionX, oldResolutionY, " "); require("term").setCursor(1, 1)
		
		local xpcallSuccess, xpcallReason = xpcall(loadSuccess)
		if xpcallSuccess then
			MineOSCore.waitForPressingAnyKey()
			gpu.setResolution(oldResolutionX, oldResolutionY)
			buffer.start()
			mainWindow:draw()
			buffer:draw()
		else

		end
	else

	end
end

---------------------------------------------------- Text processing methods ----------------------------------------------------

local function deleteLine(line)
	if #lines > 0 then
		table.remove(mainWindow.codeView.lines, line)
		setCursorPosition(1, cursor.position.line)
	end
end

local function deleteSpecifiedData(fromSymbol, fromLine, toSymbol, toLine)
	local upperLine = unicode.sub(mainWindow.codeView.lines[fromLine], 1, fromSymbol - 1)
	local lowerLine = unicode.sub(mainWindow.codeView.lines[toLine], toSymbol + 1, -1)
	for line = fromLine + 1, toLine do
		table.remove(mainWindow.codeView.lines, fromLine + 1)
	end
	mainWindow.codeView.lines[fromLine] = upperLine .. lowerLine
	setCursorPosition(fromSymbol, fromLine)
end

local function deleteSelectedData()
	if mainWindow.codeView.selections[1] then
		deleteSpecifiedData(
			mainWindow.codeView.selections[1].from.symbol,
			mainWindow.codeView.selections[1].from.line,
			mainWindow.codeView.selections[1].to.symbol,
			mainWindow.codeView.selections[1].to.line
		)
		clearSelection()
	end
end

local function copy()
	if mainWindow.codeView.selections[1] then
		if mainWindow.codeView.selections[1].to.line == mainWindow.codeView.selections[1].from.line then
			clipboard = { unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].from.line], mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol) }
		else
			clipboard = { unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].from.line], mainWindow.codeView.selections[1].from.symbol, -1) }
			for line = mainWindow.codeView.selections[1].from.line + 1, mainWindow.codeView.selections[1].to.line - 1 do
				table.insert(clipboard, mainWindow.codeView.lines[line])
			end
			table.insert(clipboard, unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].to.line], 1, mainWindow.codeView.selections[1].to.symbol))
		end
	end
end

local function cut()
	if mainWindow.codeView.selections[1] then
		copy()
		deleteSelectedData()
	end
end

local function paste(pasteLines)
	if pasteLines then
		if mainWindow.codeView.selections[1] then
			deleteSelectedData()
		end

		local firstPart = unicode.sub(mainWindow.codeView.lines[cursor.position.line], 1, cursor.position.symbol - 1)
		local secondPart = unicode.sub(mainWindow.codeView.lines[cursor.position.line], cursor.position.symbol, -1)

		if #pasteLines == 1 then
			mainWindow.codeView.lines[cursor.position.line] = firstPart .. pasteLines[1] .. secondPart
			setCursorPosition(cursor.position.symbol + unicode.len(pasteLines[1]), cursor.position.line)
		else
			mainWindow.codeView.lines[cursor.position.line] = firstPart .. pasteLines[1]
			for pasteLine = #pasteLines - 1, 2, -1 do
				table.insert(mainWindow.codeView.lines, cursor.position.line + 1, pasteLines[pasteLine])
			end
			table.insert(mainWindow.codeView.lines, cursor.position.line + #pasteLines - 1, pasteLines[#pasteLines] .. secondPart)
			setCursorPosition(unicode.len(pasteLines[#pasteLines]) + 1, cursor.position.line + #pasteLines - 1)
		end
	end
end

local function backspace()
	if mainWindow.codeView.selections[1] then
		deleteSelectedData()
	else
		if cursor.position.symbol > 1 then
			deleteSpecifiedData(cursor.position.symbol - 1, cursor.position.line, cursor.position.symbol - 1, cursor.position.line)
		else
			if cursor.position.line > 1 then
				deleteSpecifiedData(unicode.len(mainWindow.codeView.lines[cursor.position.line - 1]) + 1, cursor.position.line - 1, 0, cursor.position.line)
			end
		end
	end
end

local function enter()
	local firstPart = unicode.sub(mainWindow.codeView.lines[cursor.position.line], 1, cursor.position.symbol - 1)
	local secondPart = unicode.sub(mainWindow.codeView.lines[cursor.position.line], cursor.position.symbol, -1)
	mainWindow.codeView.lines[cursor.position.line] = firstPart
	table.insert(mainWindow.codeView.lines, cursor.position.line + 1, secondPart)
	setCursorPosition(1, cursor.position.line + 1)
end

local function selectAll()
	mainWindow.codeView.selections[1] = {from = {}, to = {}}
	mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].from.line = 1, 1
	mainWindow.codeView.selections[1].to.symbol, mainWindow.codeView.selections[1].to.line = unicode.len(mainWindow.codeView.lines[#mainWindow.codeView.lines]), #mainWindow.codeView.lines
end

---------------------------------------------------- Text comments-related methods ----------------------------------------------------

local function isLineCommented(line)
	return mainWindow.codeView.lines[line]:match("%-%-[^%-]")
end

local function commentLine(line)
	mainWindow.codeView.lines[line] = "-- " .. mainWindow.codeView.lines[line]
end

local function uncommentLine(line)
	mainWindow.codeView.lines[line], countOfReplaces = mainWindow.codeView.lines[line]:gsub("%-%-%s", "", 1)
	return countOfReplaces
end

local function toggleComment()
	if mainWindow.codeView.selections[1] then
		local allLinesAreCommented = true
		
		for line = mainWindow.codeView.selections[1].from.line, mainWindow.codeView.selections[1].to.line do
			if not isLineCommented(line) then
				allLinesAreCommented = false
			end
		end
		
		for line = mainWindow.codeView.selections[1].from.line, mainWindow.codeView.selections[1].to.line do
			if allLinesAreCommented then
				uncommentLine(line)
			else
				commentLine(line)
			end
		end

		local modifyer = 3
		if allLinesAreCommented then
			modifyer = -3
		end
		setCursorPosition(cursor.position.symbol + modifyer, cursor.position.line)
		mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol = mainWindow.codeView.selections[1].from.symbol + modifyer, mainWindow.codeView.selections[1].to.symbol + modifyer
	else
		if isLineCommented(cursor.position.line) then
			if uncommentLine(cursor.position.line) > 0 then
				setCursorPosition(cursor.position.symbol - 3, cursor.position.line)
			end
		else
			commentLine(cursor.position.line)
			setCursorPosition(cursor.position.symbol + 3, cursor.position.line)
		end
	end
end

---------------------------------------------------- Text indentation-related methods ----------------------------------------------------

local function indentLine(line)
	mainWindow.codeView.lines[line] = string.rep(" ", config.indentaionWidth) .. mainWindow.codeView.lines[line]
end

local function unindentLine(line)
	mainWindow.codeView.lines[line], countOfReplaces = string.gsub(mainWindow.codeView.lines[line], "^" .. string.rep("%s", config.indentaionWidth), "")
	return countOfReplaces
end

local function indentOrUnindent(isIndent)
	if mainWindow.codeView.selections[1] then
		local countOfReplacesInFirstLine, countOfReplacesInLastLine
		
		for line = mainWindow.codeView.selections[1].from.line, mainWindow.codeView.selections[1].to.line do
			if isIndent then
				indentLine(line)
			else
				local countOfReplaces = unindentLine(line)
				if line == mainWindow.codeView.selections[1].from.line then
					countOfReplacesInFirstLine = countOfReplaces
				elseif line == mainWindow.codeView.selections[1].to.line then
					countOfReplacesInLastLine = countOfReplaces
				end
			end
		end		

		if isIndent then
			setCursorPosition(cursor.position.symbol + config.indentaionWidth, cursor.position.line)
			mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol = mainWindow.codeView.selections[1].from.symbol + config.indentaionWidth, mainWindow.codeView.selections[1].to.symbol + config.indentaionWidth
		else
			if countOfReplacesInFirstLine > 0 then
				mainWindow.codeView.selections[1].from.symbol = mainWindow.codeView.selections[1].from.symbol - config.indentaionWidth
				if cursor.position.line == mainWindow.codeView.selections[1].from.line then
					setCursorPosition(cursor.position.symbol - config.indentaionWidth, cursor.position.line)
				end
			end

			if countOfReplacesInLastLine > 0 then
				mainWindow.codeView.selections[1].to.symbol = mainWindow.codeView.selections[1].to.symbol - config.indentaionWidth
				if cursor.position.line == mainWindow.codeView.selections[1].to.line then
					setCursorPosition(cursor.position.symbol - config.indentaionWidth, cursor.position.line)
				end
			end
		end
	else
		if isIndent then
			indentLine(cursor.position.line)
			setCursorPosition(cursor.position.symbol + config.indentaionWidth, cursor.position.line)
		else
			if unindentLine(cursor.position.line) > 0 then
				setCursorPosition(cursor.position.symbol - config.indentaionWidth, cursor.position.line)
			end
		end
	end
end

---------------------------------------------------- Main window related methods ----------------------------------------------------

local function updateTitle()
	mainWindow.titleTextBox.lines[1] = "File: " .. (workPath or "none")
	mainWindow.titleTextBox.lines[2] = "Cursor: " .. cursor.position.line .. " line, " .. cursor.position.symbol .. " symbol"
	if mainWindow.codeView.selections[1] then
		local countOfSelectedLines = mainWindow.codeView.selections[1].to.line - mainWindow.codeView.selections[1].from.line + 1
		local countOfSelectedSymbols
		if mainWindow.codeView.selections[1].from.line == mainWindow.codeView.selections[1].to.line then
			countOfSelectedSymbols = unicode.len(unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].from.line], mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol))
		else
			countOfSelectedSymbols = unicode.len(unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].from.line], mainWindow.codeView.selections[1].from.symbol, -1))
			for line = mainWindow.codeView.selections[1].from.line + 1, mainWindow.codeView.selections[1].to.line - 1 do
				countOfSelectedSymbols = countOfSelectedSymbols + unicode.len(mainWindow.codeView.lines[line])
			end
			countOfSelectedSymbols = countOfSelectedSymbols + unicode.len(unicode.sub(mainWindow.codeView.lines[mainWindow.codeView.selections[1].to.line], 1, mainWindow.codeView.selections[1].to.symbol))
		end
		mainWindow.titleTextBox.lines[3] = "Selection: " .. countOfSelectedLines .. " lines, " .. countOfSelectedSymbols .. " symbols"
	else
		mainWindow.titleTextBox.lines[3] = "Selection: none"
	end
end

local function calculateSizes()
	if mainWindow.topToolBar.isHidden then
		mainWindow.codeView.localPosition.y = 2
		mainWindow.codeView.height = mainWindow.height - 1
	else
		mainWindow.codeView.localPosition.y = 5
		mainWindow.topToolBar.width = mainWindow.width
		mainWindow.topToolBar.backgroundPanel.width = mainWindow.width
		mainWindow.titleTextBox.width = math.floor(mainWindow.topToolBar.width * 0.28)
		mainWindow.titleTextBox.localPosition.x = math.floor(mainWindow.topToolBar.width / 2 - mainWindow.titleTextBox.width / 2)
		mainWindow.codeView.height = mainWindow.height - 4
	end

	mainWindow.topMenu.width = mainWindow.width
	mainWindow.codeView.width = mainWindow.width
end

local function createWindow()
	mainWindow = windows.fullScreen()

	mainWindow.codeView = mainWindow:addCodeView(1, 1, 1, 1, {""}, 1, 1, 1, {}, {}, true)
	mainWindow.topMenu = mainWindow:addMenu(1, 1, 1, config.colorScheme.topMenu.backgroundColor, config.colorScheme.topMenu.textColor, config.colorScheme.topMenu.backgroundPressedColor, config.colorScheme.topMenu.textPressedColor)
	
	local item1 = mainWindow.topMenu:addItem("MineCode", 0x0)
	item1.onTouch = function()
		local menu = GUI.contextMenu(item1.x, item1.y + 1)
		menu:addItem("About", true).onTouch = function()
			
		end
		menu:addItem("Quit MineCode").onTouch = function()
			mainWindow:close()
		end
		menu:show()
	end

	local item2 = mainWindow.topMenu:addItem("File")
	item2.onTouch = function()
		local menu = GUI.contextMenu(item2.x, item2.y + 1)
		menu:addItem("New").onTouch = function()
			newFile()
		end
		menu:addItem("Open").onTouch = function()
			open()
		end
		menu:addSeparator()
		menu:addItem("Save", true).onTouch = function()

		end
		menu:addItem("Save as").onTouch = function()
			saveAs()
		end
		menu:show()
	end

	local item3 = mainWindow.topMenu:addItem("View")
	item3.onTouch = function()
		local menu = GUI.contextMenu(item3.x, item3.y + 1)
		menu:addItem("Togle top toolbar").onTouch = function()
			mainWindow.topToolBar.isHidden = not mainWindow.topToolBar.isHidden
			calculateSizes()
		end
		menu:show()
	end

	-- mainWindow.topMenu:addItem("Properties")
	mainWindow.topToolBar = mainWindow:addContainer(1, 2, 1, 3)
	mainWindow.topToolBar.backgroundPanel = mainWindow.topToolBar:addPanel(1, 1, 1, 3, config.colorScheme.topToolBar)
	mainWindow.titleTextBox = mainWindow.topToolBar:addTextBox(1, 1, 1, 3, 0xDDDDDD, 0x444444, {}, 1):setAlignment(GUI.alignment.horizontal.center, GUI.alignment.vertical.top)
	mainWindow.runButton = mainWindow.topToolBar:addAdaptiveButton(1, 1, 2, 1, 0x444444, 0xFFFFFF, 0xFFFFFF, 0x444444, "Run")
	mainWindow.runButton.onTouch = function()
		run()
	end
	mainWindow.toggleSyntaxHighlightingButton = mainWindow.topToolBar:addAdaptiveButton(8, 1, 2, 1, 0x262626, 0xDDDDDD, 0x262626, 0xDDDDDD, "Syntax")
	mainWindow.toggleSyntaxHighlightingButton.onTouch = function()
		mainWindow.codeView.highlightLuaSyntax = not mainWindow.codeView.highlightLuaSyntax
		local color1, color2 = 0xDDDDDD, 0x262626
		if mainWindow.codeView.highlightLuaSyntax then
			color1, color2 = 0x262626, 0xDDDDDD
		end
		mainWindow.toggleSyntaxHighlightingButton.colors.default.background, mainWindow.toggleSyntaxHighlightingButton.colors.default.text = color1, color2
		mainWindow.toggleSyntaxHighlightingButton.colors.pressed.background, mainWindow.toggleSyntaxHighlightingButton.colors.pressed.text = color1, color2
	end

	mainWindow.onAnyEvent = function(eventData)
		cursor.blinkState = not cursor.blinkState
		local oldCursorState = cursor.blinkState
		cursor.blinkState = true
			
		if eventData[1] == "touch" and mainWindow.codeView:isClicked(eventData[3], eventData[4]) then
			if eventData[5] == 1 then
				local menu = GUI.contextMenu(eventData[3], eventData[4])
				menu:addItem("Cut", not mainWindow.codeView.selections[1], "^C").onTouch = function()
					cut()
				end
				menu:addItem("Copy", not mainWindow.codeView.selections[1], "^C").onTouch = function()
					copy()
				end
				menu:addItem("Paste", not clipboard, "^V").onTouch = function()
					paste(clipboard)
				end
				menu:addSeparator()
				menu:addItem("Select all", false, "^A").onTouch = function()
					selectAll()
				end
				menu:show()
			else
				clearSelection()
				setCursorPosition(convertScreenCoordinatesToCursorPosition(eventData[3], eventData[4]))
			end
		elseif eventData[1] == "drag" then
			if eventData[5] ~= 1 then
				mainWindow.codeView.selections[1] = mainWindow.codeView.selections[1] or {from = {}, to = {}}
				mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].from.line = cursor.position.symbol, cursor.position.line
				mainWindow.codeView.selections[1].to.symbol, mainWindow.codeView.selections[1].to.line = fixCursorPosition(convertScreenCoordinatesToCursorPosition(eventData[3], eventData[4]))
				
				if mainWindow.codeView.selections[1].from.line > mainWindow.codeView.selections[1].to.line then
					mainWindow.codeView.selections[1].from.line, mainWindow.codeView.selections[1].to.line = swap(mainWindow.codeView.selections[1].from.line, mainWindow.codeView.selections[1].to.line)
					mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol = swap(mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol)
				elseif mainWindow.codeView.selections[1].from.line == mainWindow.codeView.selections[1].to.line then
					if mainWindow.codeView.selections[1].from.symbol > mainWindow.codeView.selections[1].to.symbol then
						mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol = swap(mainWindow.codeView.selections[1].from.symbol, mainWindow.codeView.selections[1].to.symbol)
					end
				end
			end
		elseif eventData[1] == "key_down" then
			-- Ctrl or CMD
			if keyboard.isKeyDown(29) or keyboard.isKeyDown(219) then
				-- Slash
				if eventData[4] == 53 then
					toggleComment()
				-- A
				elseif eventData[4] == 30 then
					selectAll()
				-- C
				elseif eventData[4] == 46 then
					copy()
				-- V
				elseif eventData[4] == 47 then
					paste(clipboard)
				-- X
				elseif eventData[4] == 45 then
					cut()
				-- W
				elseif eventData[4] == 17 then

				end
			-- Arrows up, down, left, right
			elseif eventData[4] == 200 then
				moveCursor(0, -1)
			elseif eventData[4] == 208 then
				moveCursor(0, 1)
			elseif eventData[4] == 203 then
				moveCursor(-1, 0)
			elseif eventData[4] == 205 then
				moveCursor(1, 0)
			-- Backspace
			elseif eventData[4] == 14 then
				backspace()
			-- Tab
			elseif eventData[4] == 15 then
				if keyboard.isKeyDown(42) then
					indentOrUnindent(false)
				else
					indentOrUnindent(true)
				end
			-- Enter
			elseif eventData[4] == 28 then
				enter()
			-- F5
			elseif eventData[4] == 63 then
				run()
			else
				if not keyboard.isControl(eventData[3]) then
					deleteSelectedData()
					paste({unicode.char(eventData[3])})
				end
			end
		elseif eventData[1] == "clipboard" then
			paste({eventData[3]})
		elseif eventData[1] == "scroll" then
			if mainWindow.codeView:isClicked(eventData[3], eventData[4]) then
				if eventData[5] == 1 then
					if mainWindow.codeView.fromLine > config.scrollSpeed then
						mainWindow.codeView.fromLine = mainWindow.codeView.fromLine - config.scrollSpeed
					else
						mainWindow.codeView.fromLine = 1
					end
				else
					if mainWindow.codeView.fromLine < #mainWindow.codeView.lines - config.scrollSpeed then
						mainWindow.codeView.fromLine = mainWindow.codeView.fromLine + config.scrollSpeed
					else
						mainWindow.codeView.fromLine = #mainWindow.codeView.lines
					end
				end
			end
		elseif not eventData[1] then
			cursor.blinkState = oldCursorState
		end

		updateTitle()
		mainWindow:draw()
		if cursor.blinkState then
			local x, y = mainWindow.codeView.codeAreaPosition + cursor.position.symbol - mainWindow.codeView.fromSymbol + 1, mainWindow.codeView.y + cursor.position.line - mainWindow.codeView.fromLine
			if 
				x >= mainWindow.codeView.codeAreaPosition + 1 and
				x <= mainWindow.codeView.codeAreaPosition + mainWindow.codeView.codeAreaWidth - 2 and
				y >= mainWindow.codeView.y and
				y <= mainWindow.codeView.y + mainWindow.codeView.height - 2
			then
				buffer.text(x, y, cursor.color, cursor.symbol)
			end
		end
		buffer.draw()
	end
end

-----------------------------------------------------------------------------------------------------------------------------

buffer.start()

createWindow()
calculateSizes()
mainWindow.drawShadow = false
mainWindow:draw()

if args[1] == "open" and fs.exists(args[2]) then
	loadFile("/lib/GUI.lua")
else
	newFile()
end

buffer.draw()
mainWindow:handleEvents(cursor.blinkDelay)


