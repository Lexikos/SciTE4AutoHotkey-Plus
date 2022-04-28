-- ahk.lua
-- =======

-- Part of SciTE4AutoHotkey
-- This file implements features specific to AutoHotkey in SciTE
-- Do NOT edit this file, use UserLuaScript.lua instead!

-- Functions:
--     AutoIndent for AutoHotkey
--     Some AutoComplete tweaks
--     Automatic backups
--     SciTEDebug.ahk DBGp debugger interface

local prepared = false
local bkall = {}
local bkcur = nil

-- ================================================== --
-- OnClear event - fired when SciTE changes documents --
-- ================================================== --

function OnClear()
	if not prepared then
		-- Remove the current line markers.
		ClearCurrentLineMarkers()
	end
	
	SetMarkerColors()
	editor.MarginSensitiveN[1] = true
end

-- ================================================== --
-- File/buffer events - needed to set up breakpoints  --
-- ================================================== --

function OnOpen(filename)
	if not InAHKLexer() then return end
	bkcur = bkall[filename]
	if bkcur then
		-- Restore breakpoints from memory
		for line in pairs(bkcur) do
			editor:MarkerAdd(line, 10)
		end
	else
		bkcur = {}
		bkall[filename] = bkcur
	end
end

function OnSwitchFile(filename)
	bkcur = bkall[filename]
end

function UpdateBreakpoints(filename) -- Called by OnBeforeSave
	if not bkcur then return end
	-- Compensate for line additions/removals by rebuilding the array.
	-- This is only useful when the file is being saved, because the
	-- debugger will load the version of script that's on disk.
	for k in next,bkcur do bkcur[k] = nil end
	local line = -1
	while true do
		line = editor:MarkerNext(line + 1, 1024) -- 1024 = BIT(10)
		if line == -1 then break end
		bkcur[line] = true
	end
end

-- ================================================== --
-- OnMarginClick event - needed to set up breakpoints --
-- ================================================== --

function OnMarginClick(position, margin)
	-- This function only works with the AutoHotkey lexer
	if not bkcur then return false end
	
	if margin ~= 1 then
		return false
	end
	local line = editor:LineFromPosition(position)
	-- Toggle the marker, not bkcur[], since the latter can be inaccurate
	-- while editing a file
	if editor:MarkerNext(line, 1024) == line then -- 1024 = BIT(10)
		editor:MarkerDelete(line, 10)
		bkcur[line] = nil
	else
		editor:MarkerAdd(line, 10)
		bkcur[line] = true
	end
	if prepared then
		-- Send the filename, line number and new state to the debugger
		pumpmsgstr(4112, 1
			, props.FilePath.."|"..(line+1).."|"..(bkcur[line] and 1 or 0))
	end
	return true
end

-- =============================================== --
-- OnDwellStart event - used to implement hovering --
-- =============================================== --

local NoDwellStyles = {
	-- Some of these constants don't work due to an error in the ordering
	-- of the constants in 3.0.06.01 (which messes with binary search).
	--[SCLEX_AHK1] = {SCE_AHK_COMMENTBLOCK, SCE_AHK_COMMENTLINE, SCE_AHK_STRING, SCE_AHK_ESCAPE, SCE_AHK_LABEL},
	[SCLEX_AHK1] = {2, 1, 6, 3, 10},
}
function OnDwellStart(pos, word)
	if not prepared then return end
	if word ~= '' then
		if isInTable(NoDwellStyles[editor.Lexer], editor.StyleAt[pos]) then
			return
		end
		local line, wordpos, wordlen = GetCurLineAndWordPos(pos)
		pumpmsgstr(4112, 4, line..'\1'..wordpos..'\1'..wordlen)
	else
		pumpmsgstr(4112, 4, "")
	end
end

-- =========================================================== --
-- Get direction interface HWND function (used by the toolbar) --
-- =========================================================== --

function get_director_HWND()
	if prepared then return end
	
	if localizewin("scite4ahkToolbarTempWin") == false then
		print("Window doesn't exist.")
		return
	end
	
	pumpmsg(4099, 0, props['WindowID'])
end

-- ============== --
-- DBGp functions --
-- ============== --
-- The following are only reachable when an AutoHotkey script
-- is open so there's no need to check the lexer

function DBGp_Connect()
	if prepared then return end
	
	if localizewin("SciTEDebugStub") == false then
		print("Window doesn't exist.")
		return
	end
	
	-- Initialize
	pumpmsg(4112, 0, 0)
	prepared = true
	ClearCurrentLineMarkers()
end

function DBGp_BkReset()
	if not bkcur then return end
	
	local bkstr = {}
	for file, lines in pairs(bkall) do
		local bklines = {}
		for line in pairs(lines) do
			table.insert(bklines, line+1)
		end
		table.insert(bkstr, file .. "|" .. table.concat(bklines, " "))
	end
	
	-- Send all filenames|breakpoints as a single string
	pumpmsgstr(4112, 5, table.concat(bkstr, "\n"))
end

function DBGp_Disconnect()
	-- Deinitialize
	u = pumpmsg(4112, 255, 0)
	if u == 0 then return false end
	
	prepared = false
	ClearCurrentLineMarkers()
end

function DBGp_Inspect()
	if not prepared then return end
	
	local word = editor:GetSelText()
	if word == "" then
		local line, wordpos, wordlen = GetCurLineAndWordPos(pos)
		-- Prevent Inspect from taking the [] to the right of the word:
		line = line:sub(1, wordpos + wordlen - 1)
		word = line..'\1'..wordpos..'\1'..wordlen
	end
	pumpmsgstr(4112, 2, word)
end

function DBGp_Run()
	if not prepared then return end
	postmsg(4112, 3, 1)
end

function DBGp_Stop()
	if not prepared then return end
	postmsg(4112, 3, 2)
end

function DBGp_Pause()
	if not prepared then return end
	postmsg(4112, 3, 3)
end

function DBGp_StepInto()
	if not prepared then return end
	postmsg(4112, 3, 4)
end

function DBGp_StepOver()
	if not prepared then return end
	postmsg(4112, 3, 5)
end

function DBGp_StepOut()
	if not prepared then return end
	postmsg(4112, 3, 6)
end

function DBGp_Stacktrace()
	if not prepared then return end
	postmsg(4112, 3, 7)
end

function DBGp_Varlist()
	if not prepared then return end
	postmsg(4112, 3, 8)
end

-- ============================================================ --
-- AutoIndent section - it implements AutoIndent for AutoHotkey --
-- ============================================================ --

-- Patterns for syntax matching
--local varCharPat = "[#_@%w%[%]%$%?]"
local varCharPat = "[#_@%w%$]"
local ifPat = "[iI][fF]"
local altIfPat = ifPat.."%a+"
local whilePat = "[wW][hH][iI][lL][eE]"
local loopPat = "[lL][oO][oO][pP]"
local forPat = "[fF][oO][rR]"
local elsePat = "[eE][lL][sS][eE]"
local tryPat = "[tT][rR][yY]"
local catchPat = "[cC][aA][tT][cC][hH]"
local finallyPat = "[fF][iI][nN][aA][lL][lL][yY]"
local switchPat = "[sS][wW][iI][tT][cC][hH]"
local casePat = "[cC][aA][sS][eE]"

-- Functions to detect certain types of statements

function isOpenBraceLine(line)
	return string.find(line, "^%s*{") ~= nil
end

function isIfLine(line)
	return string.find(line, "^%s*"..ifPat.."%s+"..varCharPat) ~= nil
		or string.find(line, "^%s*"..ifPat.."%s*%(") ~= nil
		or string.find(line, "^%s*"..ifPat.."%s+!") ~= nil
		or string.find(line, "^%s*"..altIfPat.."%s*,") ~= nil
		or string.find(line, "^%s*"..altIfPat.."%s+") ~= nil
end

function isIfLineNoBraces(line)
	return isIfLine(line) and string.find(line, "{%s*$") == nil
end

function isTryLine(line)
	return string.find(line, "^%s*"..tryPat.."%s+$") ~= nil
end

function isTryLineAllowBraces(line)
	return isTryLine(line) or string.find(line, "^%s*"..tryPat.."%s*{%s*$") ~= nil
end

function isWhileLine(line)
	return string.find(line, "^%s*"..whilePat.."%s+") ~= nil
		or string.find(line, "^%s*"..whilePat.."%s*%(") ~= nil
end

function isLoopLine(line)
	return string.find(line, "^%s*"..loopPat.."%s*,") ~= nil
		or string.find(line, "^%s*"..loopPat.."%s+") ~= nil
end

function isForLine(line)
	return string.find(line, "^%s*"..forPat.."%s+"..varCharPat) ~= nil
end

function isLoopLineAllowBraces(line)
	return isLoopLine(line) or string.find(line, "^%s*"..loopPat.."%s*{%s*$") ~= nil
end

-- Minor annoyance: this way of doing ELSE detection makes the following
-- appear as an one-line indent statement:
-- else {commandWhichDoesNotInvolveIndention}
--
-- Examples:
-- else MsgBox
-- else var := value
--
-- Those cases seem rare enough not to attempt to fix them, the alternative
-- would be breaking "else if" indentation.

function isElseLine(line)
	return string.find(line, "^%s*"..elsePat.."%s*") ~= nil
		or isElseWithClosingBrace(line)
end

function isElseWithClosingBrace(line)
	return string.find(line, "^%s*}%s*"..elsePat.."%s*") ~= nil
end

function isElseLineAllowBraces(line)
	return isElseLine(line) or isElseWithClosingBrace(line)
		or string.find(line, "^%s*"..elsePat.."%s*{%s*$") ~= nil
		or string.find(line, "^%s*}%s*"..elsePat.."%s*{%s*$") ~= nil
end

function isCatchLine(line)
	return string.find(line, "^%s*"..catchPat.."%s*$") ~= nil
		or string.find(line, "^%s*"..catchPat.."%s+"..varCharPat.."+%s*$") ~= nil
end

function isCatchAllowClosingBrace(line)
	return isCatchLine(line)
		or string.find(line, "^%s*}%s*"..catchPat.."%s*$") ~= nil
		or string.find(line, "^%s*}%s*"..catchPat.."%s+"..varCharPat.."+%s*$") ~= nil
end

function isCatchLineAllowBraces(line)
	return isCatchAllowClosingBrace(line)
		or string.find(line, "^%s*"..catchPat.."%s*{%s*$") ~= nil
		or string.find(line, "^%s*"..catchPat.."%s+"..varCharPat.."+%s*{%s*$") ~= nil
		or string.find(line, "^%s*}%s*"..catchPat.."%s*{%s*$") ~= nil
		or string.find(line, "^%s*}%s*"..catchPat.."%s+"..varCharPat.."+%s*{%s*$") ~= nil
end

function isFinallyLine(line)
	return string.find(line, "^%s*"..finallyPat.."%s*$") ~= nil
end

function isFinallyAllowClosingBrace(line)
	return isFinallyLine(line)
		or string.find(line, "^%s*}%s*"..finallyPat.."%s*$") ~= nil
end

function isFinallyAllowBraces(line)
	return isFinallyAllowClosingBrace(line)
		or string.find(line, "^%s*}%s*"..finallyPat.."%s*{%s*$") ~= nil
end

function isFuncDef(line)
	return string.find(line, "^%s*"..varCharPat.."+%(.*%)%s*{%s*$") ~= nil
end

function isSingleLineIndentStatement(line)
	return isIfLineNoBraces(line) or isElseLine(line) or isElseWithClosingBrace(line)
		or isWhileLine(line) or isForLine(line) or isLoopLine(line)
		or isTryLine(line) or isCatchAllowClosingBrace(line) or isFinallyAllowClosingBrace(line)
end

function isIndentStatement(line)
	return isOpenBraceLine(line) or isIfLine(line) or isWhileLine(line) or isForLine(line)
		or isLoopLineAllowBraces(line) or isElseLineAllowBraces(line) or isFuncDef(line)
		or isTryLineAllowBraces(line) or isCatchLineAllowBraces(line) or isFinallyAllowBraces(line)
end

function isStartBlockStatement(line)
	return isIfLine(line) or isWhileLine(line) or isLoopLine(line)  or isForLine(line)
		or isElseLine(line) or isElseWithClosingBrace(line)
		or isTryLine(line) or isCatchLineAllowBraces(line) or isFinallyAllowBraces(line)
end

-- 来自 自动完成增强版.lua handleChar
-- This function is called when the user presses {Enter}
function AutoIndent_OnNewLine()
	local cmtLineStyle = SCE_AHK_COMMENTLINE
	local cmtBlockStyle = SCE_AHK_COMMENTBLOCK
	local prevprevPos = editor:LineFromPosition(editor.CurrentPos) - 2
	local prevPos = editor:LineFromPosition(editor.CurrentPos) - 1
	local prevLine = GetFilteredLine(prevPos, cmtLineStyle, cmtBlockStyle)
	local curPos = prevPos + 1
	local curLine = editor:GetLine(curPos)
	
	if curLine ~= nil and string.find(curLine, "^%s*[^%s]+") then return end
	
	if isIndentStatement(prevLine) then
		editor:Home()
		editor:Tab()
		editor:LineEnd()
	elseif prevprevPos >= 0 then
		local prevprevLine = GetFilteredLine(prevprevPos, cmtLineStyle, cmtBlockStyle)
		local reqLvl = editor.LineIndentation[prevprevPos] + editor.Indent
		local prevLvl = editor.LineIndentation[prevPos]
		local curLvl = editor.LineIndentation[curPos]
		if isSingleLineIndentStatement(prevprevLine) and prevLvl == reqLvl and curLvl == reqLvl then
			editor:Home()
			editor:BackTab()
			editor:LineEnd()
			return true
		end
	end
	return false
end

-- 来自 自动完成增强版.lua handleChar
-- This function is called when the user presses {
function AutoIndent_OnOpeningBrace()
	local cmtLineStyle = SCE_AHK_COMMENTLINE
	local cmtBlockStyle = SCE_AHK_COMMENTBLOCK
	local prevPos = editor:LineFromPosition(editor.CurrentPos) - 1
	local curPos = prevPos+1
	if prevPos == -1 then return false end
	
	if editor.LineIndentation[curPos] == 0 then return false end
	
	local prevLine = GetFilteredLine(prevPos, cmtLineStyle, cmtBlockStyle)
	local curLine = GetFilteredLine(curPos, cmtLineStyle, cmtBlockStyle)
	
	if string.find(curLine, "^%s*{%s*$") and isStartBlockStatement(prevLine)
		and (editor.LineIndentation[curPos] > editor.LineIndentation[prevPos]) then
		editor:Home()
		editor:BackTab()
		editor:LineEnd()
	end
end

-- 来自 自动完成增强版.lua handleChar
-- This function is called when the user presses }
function AutoIndent_OnClosingBrace()
	local cmtLineStyle = SCE_AHK_COMMENTLINE
	local cmtBlockStyle = SCE_AHK_COMMENTBLOCK
	local curPos = editor:LineFromPosition(editor.CurrentPos)
	local curLine = GetFilteredLine(curPos, cmtLineStyle, cmtBlockStyle)
	local prevPos = curPos - 1
	local prevprevPos = prevPos - 1
	local secondChance = false
	
	if curPos == 0 then return false end
	if editor.LineIndentation[curPos] == 0 then return false end
	
	if prevprevPos >= 0 then
		local prevprevLine = GetFilteredLine(prevprevPos, cmtLineStyle, cmtBlockStyle)
		local lowLvl = editor.LineIndentation[prevprevPos]
		local highLvl = lowLvl + editor.Indent
		local prevLvl = editor.LineIndentation[prevPos]
		local curLvl = editor.LineIndentation[curPos]
		if isSingleLineIndentStatement(prevprevLine) and prevLvl == highLvl and curLvl == lowLvl then
			secondChance = true
		end
	end
	
	if string.find(curLine, "^%s*}%s*$") and (editor.LineIndentation[curPos] >= editor.LineIndentation[prevPos] or secondChance) then
		editor:Home()
		editor:BackTab()
		editor:LineEnd()
	end
end

-- ====================== --
-- Script Backup Function --
-- ====================== --

function OnBeforeSave(filename)
	-- This function only works with the AutoHotkey lexer
	if not InAHKLexer() then return false end
	
	if props['make.backup'] == "1" then
		os.remove(filename .. ".bak")
		os.rename(filename, filename .. ".bak")
	end
	
	-- Also update breakpoints.  It's called from here and not OnSave
	-- because OnBeforeSave is more reliable.  OnSave is not called if
	-- the file is saved asynchronously and some other file is active
	-- when it completes (this happens with save.all.for.build=1).
	UpdateBreakpoints()
end

-- ============= --
-- Open #Include --
-- ============= --

function OpenInclude()
	-- This function only works with the AutoHotkey lexer
	if not InAHKLexer() then return false end
	
	local CurrentLine = editor:GetLine(editor:LineFromPosition(editor.CurrentPos))
	if not string.find(CurrentLine, "^%s*%#[Ii][Nn][Cc][Ll][Uu][Dd][Ee]") then
		print("Not an include line!")
		return
	end
	local place = string.find(CurrentLine, "%#[Ii][Nn][Cc][Ll][Uu][Dd][Ee]")
	local IncFile = string.sub(CurrentLine, place + 8)
	if string.find(IncFile, "^[Aa][Gg][Aa][Ii][Nn]") then
		IncFile = string.sub(IncFile, 6)
	end
	IncFile = string.gsub(IncFile, "\r", "")  -- strip CR
	IncFile = string.gsub(IncFile, "\n", "")  -- strip LF
	IncFile = string.sub(IncFile, 2)          -- strip space at the beginning
	IncFile = string.gsub(IncFile, "*i ", "") -- strip *i option
	IncFile = string.gsub(IncFile, "*I ", "")
	-- Delete comments
	local cplace = string.find(IncFile, "%s*;")
	if cplace then
		IncFile = string.sub(IncFile, 1, cplace-1)
	end
	
	-- Delete spaces at the beginning and the end
	IncFile = string.gsub(IncFile, "^%s*", "")
	IncFile = string.gsub(IncFile, "%s*$", "")
	
	-- Replace variables
	IncFile = string.gsub(IncFile, "%%[Aa]_[Ss][Cc][Rr][Ii][Pp][Tt][Dd][Ii][Rr]%%", props['FileDir'])
	IncFile = string.gsub(IncFile, "%%[Aa]_[Ll][Ii][Nn][Ee][Ff][Ii][Ll][Ee]%%", props['FilePath'])
	
	a,b,IncLib = string.find(IncFile, "^<(.+)>$")
	
	if IncLib ~= nil then
	
		local IncLib2 = IncLib
		local RawIncLib = IncLib
		a,b,whatmatch = string.find(IncLib, "^(.-)_")
		if whatmatch ~= nil and whatmatch ~= "" then
			IncLib2 = whatmatch
		end
		IncLib = "\\"..IncLib..".ahk"
		IncLib2 = "\\"..IncLib2..".ahk"
		
		local GlobalLib = props['AutoHotkeyDir'].."\\Lib"
		local UserLib = props['SciteUserHome'].."\\..\\Lib"
		local LocalLib = props['FileDir'].."\\Lib"
		
		for i,LibDir in ipairs({GlobalLib, UserLib, LocalLib}) do
			if FileExists(LibDir..IncLib) then
				scite.Open(LibDir..IncLib)
				return
			elseif FileExists(LibDir..IncLib2) then
				scite.Open(LibDir..IncLib2)
				return
			end
		end
		
		print("Library not found! Specified: '"..RawIncLib.."'")
		
	elseif FileExists(IncFile) then
		scite.Open(IncFile)
	else
		print("File not found! Specified: '"..IncFile.."'")
	end
end

-- ================ --
-- Helper Functions --
-- ================ --

function InAHKLexer()
	return editor.Lexer == SCLEX_AHK1
end

function GetWord(pos)
	from = editor:WordStartPosition(pos, true)
	to = editor:WordEndPosition(pos, true)
	return editor:textrange(from, to)
end

function GetCurWord()
	local word = editor:GetSelText()
	if word == "" then
		word = GetWord(editor.CurrentPos)
	end
	return word
end

function GetCurLineAndWordPos(pos)
	pos = pos or editor.CurrentPos
	local lineno = editor:LineFromPosition(pos)
	local linepos = editor:PositionFromLine(lineno)
	local wordpos = editor:WordStartPosition(pos, true)
	local wordend = editor:WordEndPosition(pos, true)
	return editor:GetLine(lineno)
		, wordpos - linepos + 1
		, wordend - wordpos
end

function getPrevLinePos()
	local line = editor:LineFromPosition(editor.CurrentPos)-1
	local linepos = editor:PositionFromLine(line)
	local linetxt = editor:GetLine(line)
	return linepos + string.len(linetxt) - 1
end

function isInTable(table, elem)
	if table == null then return false end
	for k,i in ipairs(table) do
		if i == elem then
			return true
		end
	end
	return false
end

function GetFilteredLine(linen, style1, style2)
	unline = editor:GetLine(linen)
	lpos = editor:PositionFromLine(linen)
	q = 0
	for i = 0, string.len(unline)-1 do
		if(editor.StyleAt[lpos+i] == style1 or editor.StyleAt[lpos+i] == style2) then
			unline = unline:sub(1, i).."\000"..unline:sub(i+2)
		end
	end
	unline = string.gsub(unline, "%z", "")
	return unline
end

function SetMarkerColors()
	editor:MarkerDefine(10, 0)  -- breakpoint
	editor.MarkerBack[10] = 0x0000FF
	editor:MarkerDefine(11, 2)  -- current line arrow
	editor.MarkerBack[11] = 0xFFFF00
	editor:MarkerDefine(12, 22) -- current line highlighting
	editor.MarkerBack[12] = 0xFFFF00
	editor.MarkerAlpha[12] = 32
end

function ClearCurrentLineMarkers()
	editor:MarkerDeleteAll(11)
	editor:MarkerDeleteAll(12)
end

-- ======================= --
-- User Lua script loading --
-- ======================= --

function FileExists(file)
	local fobj = io.open(file, "r")
	if fobj then
		fobj:close()
		return true
	else
		return false
	end
end

function RegisterEvents(events)
	-- Code originally written by Lexikos (AutoComplete.lua)
	for evt, func in pairs(events) do
		local oldfunc = _G[evt]
		if oldfunc then
			_G[evt] = function(...) return func(...) or oldfunc(...) end
		else
			_G[evt] = func
		end
	end
end

-- Globals for extensions
g_SettingsDir = props['SciteUserHome'].."/Settings"

local userlua = props['SciteUserHome'].."/UserLuaScript.lua"
local extlua = props['SciteUserHome'].."/_extensions.lua"
if FileExists(userlua) then
	dofile(userlua)
end
if FileExists(extlua) then
	dofile(extlua)
end

-- SciTE4AutoHotkey-Plus 的增强
-- dofile(props['SciteDefaultHome'].."/extensions/运行选区代码.lua")
dofile(props['SciteDefaultHome'].."/extensions/跳到新行.lua")
dofile(props['SciteDefaultHome'].."/extensions/自动完成增强版.lua")
dofile(props['SciteDefaultHome'].."/extensions/新建文件时默认UTF-8带BOM.lua")
-- 用于区分 lexers 加载 ahk 还是 ahk2
-- dofile(props['SciteUserHome']..'/lexers/lpeg_s4a.lua')