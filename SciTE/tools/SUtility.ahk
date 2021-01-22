;
; Scriptlet Utility
;

#NoEnv
#NoTrayIcon
#SingleInstance Ignore
DetectHiddenWindows, On
FileEncoding, UTF-8
Menu, Tray, Icon, %A_ScriptDir%\..\toolicon.icl, 11
progName := "�ű�Ƭ��"

scite := GetSciTEInstance()
if !scite
{
	MsgBox, 16, %progName%, û���ҵ� SciTE COM ����!
	ExitApp
}

textFont := scite.ResolveProp("default.text.font")
LocalSciTEPath := scite.UserDir
scitehwnd := scite.SciTEHandle

sdir = %LocalSciTEPath%\Scriptlets
IfNotExist, %sdir%
{
	MsgBox, 16, %progName%, Scriptlet �ļ���(Ŀ¼)������!
	ExitApp
}

; Check command line
if 1 = /insert
{
	if 2 =
	{
		MsgBox, 64, %progName%, ʾ��: %A_ScriptName% /insert �ű�Ƭ����
		ExitApp
	}
	IfNotExist, %sdir%\%2%.scriptlet
	{
		MsgBox, 52, %progName%,
		(LTrim
		��Ч�Ľű�Ƭ��: "%2%".
		������ͼ���Ӧ�Ľű�Ƭ�β�����.
		�����ȷ�����༭�������ļ�.
		)
		IfMsgBox, Yes
			scite.OpenFile(LocalSciTEPath "\UserToolbar.properties")
		ExitApp
	}
	FileRead, text2insert, %sdir%\%2%.scriptlet
	gosub InsertDirect
	ExitApp
}

if 1 = /addScriptlet
{
	defaultScriptlet := scite.Selection
	if defaultScriptlet =
	{
		MsgBox, 16, %progName%, û��ѡ������!
		ExitApp
	}
	gosub AddBut ; that does it all
	if !_RC
		ExitApp ; Maybe the user has cancelled the action.
	MsgBox, 68, %progName%, �ű�Ƭ���ѳɹ���ӡ� �Ƿ�򿪽ű�Ƭ�ι�����?
	IfMsgBox, Yes
		Reload ; no parameters are passed to script
	ExitApp
}

Gui, +MinSize Resize Owner%scitehwnd%
Gui, Add, Button, Section gAddBut, �½�
Gui, Add, Button, ys gRenBut, ������
Gui, Add, Button, ys gSubBut, ɾ��
Gui, Add, ListBox, xs w160 h240 vMainListbox gSelectLB HScroll
Gui, Add, Button, ys Section gToolbarBut, ��ӵ�������
Gui, Add, Button, ys gInsertBut, ���뵽 SciTE
Gui, Add, Button, ys gSaveBut, ����
Gui, Add, Button, ys gOpenInSciTE, �� SciTE �д�
Gui, Font, S9, %textFont%
Gui, Add, Edit, xs w320 h240 vScriptPane -Wrap WantTab HScroll
Gui, Show,, %progName%

selectQ =
defaultScriptlet =
gosub ListboxUpdate
return

GuiSize:
Anchor("MainListbox", "h")
Anchor("ScriptPane", "wh")
return

GuiGetPos(ctrl, guiId := "")
{
	guiId := guiId ? (guiId ":") : ""
	GuiControlGet, ov, %guiId%Pos, %ctrl%
	return { x: ovx, y: ovy, w: ovw, h: ovh }
}

GuiClose:
ExitApp

SelectLB:
GuiControlGet, fname2open,, MainListbox
FileRead, scriptletText, %sdir%\%fname2open%.scriptlet
GuiControl,, ScriptPane, % scriptletText
Return

AddBut:
Gui +OwnDialogs
InputBox, fname2create, %progName%, ����Ҫ�����Ľű�Ƭ�ε�����:
if ErrorLevel
	return
if !fname2create
	return
fname2create := ValidateFilename(fname2create)
IfExist, %sdir%\%fname2create%.scriptlet
{
	gosub CompleteUpdate
	return
}
FileAppend, % defaultScriptlet, %sdir%\%fname2create%.scriptlet
gosub CompleteUpdate
_RC = 1
Return

CompleteUpdate:
selectQ = %fname2create%
gosub ListboxUpdate
selectQ =
if defaultScriptlet =
	gosub SelectLB
return

SubBut:
Gui +OwnDialogs
GuiControlGet, selected,, MainListbox
if selected =
	return
MsgBox, 52, %progName%,ȷ��Ҫɾ�� '%selected%'?
IfMsgBox, No
	return
FileDelete, %sdir%\%selected%.scriptlet
fname2create =
gosub CompleteUpdate
return

RenBut:
Gui +OwnDialogs
GuiControlGet, selected,, MainListbox
if selected =
	return
InputBox, fname2create, %progName%, ����ű�Ƭ�ε�������:,,,,,,,, %selected%
if ErrorLevel
	return
if !fname2create
	return
if (fname2create = selected)
	return
fname2create := ValidateFilename(fname2create)
IfExist, %sdir%\%fname2create%.scriptlet
{
	MsgBox, 48, %progName%, �������Ѵ��ڣ�`n��ѡ����������.
	return
}
FileMove, %sdir%\%selected%.scriptlet, %sdir%\%fname2create%.scriptlet
gosub CompleteUpdate
return

ToolbarBut:
GuiControlGet, selected,, MainListbox
if selected =
	return

FileAppend, `n=Scriptlet: %selected%|`%LOCALAHK`% tools\SUtility.ahk /insert "%selected%"||`%ICONRES`%`,12, %LocalSciTEPath%\UserToolbar.properties
scite.Message(0x1000+2)
return

InsertBut:
GuiControlGet, text2insert,, ScriptPane
InsertDirect:
if text2insert =
	return
WinActivate, ahk_id %scitehwnd%
scite.InsertText(text2insert)
return

SaveBut:
GuiControlGet, fname2save,, MainListbox
GuiControlGet, text2save,, ScriptPane
FileDelete, %sdir%\%fname2save%.scriptlet
FileAppend, % text2save, %sdir%\%fname2save%.scriptlet
return

OpenInSciTE:
GuiControlGet, fname2open,, MainListbox
if fname2open =
	return
scite.OpenFile(sdir "\" fname2open ".scriptlet")
return

ListboxUpdate:
te =
Loop, %sdir%\*.scriptlet
{
	SplitPath, A_LoopFileName,,,, sn
	if sn =
		continue
	te = %te%|%sn%
	if selectQ = %sn%
		te .= "|"
}
GuiControl,, MainListbox, % te
return

ValidateFilename(fn)
{
	StringReplace, fn, fn, \, _, All
	StringReplace, fn, fn, /, _, All
	StringReplace, fn, fn, :, _, All
	StringReplace, fn, fn, *, _, All
	StringReplace, fn, fn, ?, _, All
	StringReplace, fn, fn, ", _, All
	StringReplace, fn, fn, <, _, All
	StringReplace, fn, fn, >, _, All
	StringReplace, fn, fn, |, _, All
	return fn
}
