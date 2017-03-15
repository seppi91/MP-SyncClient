#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=Sync1.ico
#AutoIt3Wrapper_Outfile=SyncClient.exe
#AutoIt3Wrapper_UseUpx=n
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_Res_Description=SyncClient
#AutoIt3Wrapper_Res_Fileversion=1.2.5.6
#AutoIt3Wrapper_Res_Language=1031
#AutoIt3Wrapper_Run_After=D:\Benutzer\Seppi\Documents\AutoIT\SetTxtVersion.exe -SyncClient
#AutoIt3Wrapper_Run_Tidy=y
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
;
; AutoIt Version: 3.0
; Language:       deutsch
; Platform:       WinNT/2000/XP/Vista
; Author:         Jochen Mittnacht
;
; Script Function:
; Überwacht den PC auf Powerevents (Suspend, Resume) und führt je nach Einstellung anschließend folgende Befehle aus:
; Nach Resume:
; - Analysiert die MovingPictures und TVSeries Datenbanken auf ihren Stand und synchronisiert diese falls veraltet mit den neueren Masterdatenbanken
; - Startet den TV-Service (von MediaPortal) neu und hält dabei den MediaPortal-Prozess an, damit es zu keiner Fehlermeldung kommt.
; - Startet Mediaportal neu
; - Führt einen Hardware-Reset über Devcon aus
; - Startet ein vom Benutzer frei wählbares Programm neu
;
; Vor Suspend:
; - Beendet den TV-Service (von MediaPortal)
; - Beendet MediaPortal
; - Startet ein vom Benutzer frei wählbares Programm neu

#Region Variablen
;-------------------------------
;-----------Variablen-----------
;-------------------------------

;-------------------------------------------------------
;UDFs, die nicht bei Autoit-Installation enthalten sind:
#include <Services.au3>
#include <DeviceAPI.au3>
#include <SuspendProcess.au3>
#include <TrayMsgBox.au3>
;-------------------------------------------------------
;UDFs, bei Autoit-Installation enthalten:
#include <SQLite.au3>
#include <SQLite.dll.au3>
#include <Process.au3>
#include <File.au3>
#include <GuiIPAddress.au3>
#include <GuiListView.au3>
#include <GuiButton.au3>
#include <Date.au3>
;Includes für SyncTool
#include <Array.au3>
#include <Crypt.au3>
;-------------------------------------------------------
;Pfadvariablen
Dim $MPConfigDir = RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Team MediaPortal\MediaPortal", "ConfigDir")
If $MPConfigDir = "" Then $MPConfigDir = @AppDataCommonDir & "\Team MediaPortal\MediaPortal"

Dim $MPAppDir = RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MediaPortal", "InstallPath")
Dim $MPdbLc, $MPdbSc, $TVdbLc, $TVdbSc, $MPexe, $Other1Exe, $Other2Exe, $DevconExe, $SQliteExe, $MusicdbLc, $MusicdbSc
;Checkboxen
Dim $ResDev, $ResMP, $ResProg, $ResTV, $SuspMP, $SuspProg, $SuspTV, $DevName, $DevID, $SyncTV, $SyncMP, $SyncMusic, $Wol
;RadioButtons
Dim $Kill, $Stop, $Tray, $Splash
;Comboboxinhalt - Geräteliste, Updatefunktion, Suspendmodes
Dim $DevArray[1][1], $Update, $Suspendmode
;Eingabefelder
Dim $Profil1, $Profil2, $Profil3, $Profil4, $Profil5, $Profil6
;Sammelt Zahl aufgetretener Fehler
Dim $ErrorValue = 0
;Array, Beinhaltet die jeweils zu synchronisierenden Tabellen
Dim $TablesMp, $TablesTv, $TablesMusic
;Speichert vorangegangene TaskLables
Dim $LastTask = ""
;WOL-Server Variablen
Dim $DefaultIP = "192.168.0.0"
Dim $IP, $MACAddress
;TCP-Variablen
Dim $Port = 56789
;Powerstatus Variablen
Global $LastPwrStatus = ""

#Region SyncTool-Variablen
;~ configure all options nexessary for start
Dim $started = False
Dim $marqueeScroll = False
Dim $marqueeProgress = 0

Dim $elapsedSeconds = 0
Dim $elapsedMinutes = 0
Dim $elapsedHours = 0

Dim $syncedFiles = 0
Dim $skippedFiles = 0

Dim $size = 0
Dim $fileCount = 0
Dim $totalSize = 0
Dim $copySize = 0
Dim $showPercent = 0

Dim $verifyMethod = "Nothing"
Dim $finishedAction = "Nothing"
Dim $deleteAfterSync = False
Dim $time = 0
Dim $showElapsedTime = 0

Local $array, $oldTitle, $PID, $copySource, $copyDestination
Local $failedFiles[1] = [0]
Local $stats[8] = [7, 0, 0, 0, 0, 0, 0, 0]

Local $rKey = "HKCU\Control Panel\International"
Local $sThousands = ',', $sDecimal = '.'
If $sDecimal = -1 Then $sDecimal = RegRead($rKey, "sDecimal")
If $sThousands = -1 Then $sThousands = RegRead($rKey, "sThousand")

Dim $syncedFilesize = 0
#EndRegion SyncTool-Variablen


;DefaultStrings, falls Schlüssel nicht gelesen werden kann, bzw. .ini nicht existiert

#Region DefaultStrings
If FileExists($MPConfigDir & "\database\movingpictures.db3") Then
	$MPdbLcDefault = $MPConfigDir & "\database\movingpictures.db3"
Else
	$MPdbLcDefault = ""
EndIf

If FileExists($MPConfigDir & "\database\TVSeriesDatabase4.db3") Then
	$TVdbLcDefault = $MPConfigDir & "\database\TVSeriesDatabase4.db3"
Else
	$TVdbLcDefault = ""
EndIf

If FileExists($MPConfigDir & "\database\MusicDatabaseV11.db3") Then
	$MusicdbLcDefault = $MPConfigDir & "\database\MusicDatabaseV11.db3"
Else
	$MusicdbLcDefault = ""
EndIf

If FileExists(@ScriptDir & "\devcon.exe") Then
	$DevconExeDefault = @ScriptDir & '\devcon.exe'
Else
	$DevconExeDefault = ""
EndIf

If FileExists(@ScriptDir & "\sqlite3.exe") Then
	$SQliteExeDefault = @ScriptDir & "\sqlite3.exe"
Else
	$SQliteExeDefault = ""
EndIf

If FileExists($MPAppDir & "\Mediaportal.exe") Then
	$MPexeDefault = $MPAppDir & "\Mediaportal.exe"
Else
	$MPexeDefault = ""
EndIf


#EndRegion DefaultStrings
#EndRegion Variablen

#Region Eventüberwachung
;-------------------------------
;-------Eventüberwachung--------
;-------------------------------
Global Const $WM_POWERBROADCAST = 0x218
Global Const $PBT_APMRESUMESUSPEND = 0x7 ;Operation is resuming from a low-power state. This message is sent after PBT_APMRESUMEAUTOMATIC if the resume is triggered by user input, such as pressing a key.
Global Const $PBT_APMSUSPEND = 0x4 ; System is suspending operation.
Global Const $PBT_APMRESUMEAUTOMATIC = 0x12 ;Operation is resuming automatically from a low-power state. This message is sent every time the system resumes.

;------ Weitere Powerevents ------
;Global Const $PBT_APMPOWERSTATUSCHANGE = 0xA ; Power status has changed.
;Global Const $PBT_APMRESUMEAUTOMATIC = 0x12 ; Operation is resuming automatically from a low-power state. This message is sent every time the system resumes.
;Global Const $PBT_POWERSETTINGCHANGE = 0x8013 ; A power setting change event has been received.

;Windows Server 2003, Windows XP, and Windows 2000:  The following event identifiers are also supported.
;Global Const $PBT_APMBATTERYLOW = 0x9 ; Battery power is low. In Windows Server 2008 and Windows Vista, use PBT_APMPOWERSTATUSCHANGE instead.
;Global Const $PBT_APMOEMEVENT = 0xB ; OEM-defined event occurred. In Windows Server 2008 and Windows Vista, this event is not available because these operating systems support only ACPI; APM BIOS events are not supported.
;Global Const $PBT_APMQUERYSUSPEND = 0x0 ; Request for permission to suspend. In Windows Server 2008 and Windows Vista, use the SetThreadExecutionState function instead.
;Global Const $PBT_APMQUERYSUSPENDFAILED = 0x2 ; Suspension request denied. In Windows Server 2008 and Windows Vista, use SetThreadExecutionState instead.
;Global Const $PBT_APMRESUMECRITICAL = 0x6 ; Operation resuming after critical suspension. In Windows Server 2008 and Windows Vista, use PBT_APMRESUMEAUTOMATIC instead.
;Global Const $BROADCAST_QUERY_DENY = 0x424D5144
;-----------------------------------

GUIRegisterMsg($WM_POWERBROADCAST, "MY_WM_POWERBROADCAST")

Func MY_WM_POWERBROADCAST($hWnd, $uMsg, $wParam, $lParam)
	; Beschreibgungen auf http://msdn.microsoft.com/en-us/library/aa373247(VS.85).aspx
	_FileWriteLog("log.txt", "[INFO]:  " & $wParam)
	Select
		Case $wParam = $PBT_APMRESUMESUSPEND And $LastPwrStatus <> $PBT_APMRESUMESUSPEND
			StartResTasks()
		Case $wParam = $PBT_APMSUSPEND And $LastPwrStatus <> $PBT_APMSUSPEND
			StartSusTasks()
	EndSelect
	$LastPwrStatus = $wParam
EndFunc   ;==>MY_WM_POWERBROADCAST
#EndRegion Eventüberwachung


#Region Gui
;-------------------------------
;--------------GUI--------------
;-------------------------------
#Region Settings-Form
#include <ButtonConstants.au3>
#include <Constants.au3>
#include <EditConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <TabConstants.au3>
#include <GuiEdit.au3>
#include <GUIComboBox.au3>
;Includes für SyncTool
#include <ProgressConstants.au3>


Opt("GUIOnEventMode", 1)
Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)
#Region ### START Koda GUI section ### Form=syncclient.kxf
Global $FormSettings = GUICreate("Einstellungen", 411, 490, 463, 246)
GUISetIcon("C:\Dokumente und Einstellungen\Jochen\Eigene Dateien\AutoIT\SyncClient\Source\Sync1.ico")
GUISetOnEvent($GUI_EVENT_CLOSE, "AbbrechenBtn")
Global $ButtonAbr = GUICtrlCreateButton("Abbrechen", 248, 456, 74, 28, $WS_GROUP)
GUICtrlSetOnEvent($ButtonAbr, "AbbrechenBtn")
Global $ButtonOk = GUICtrlCreateButton("OK", 333, 456, 74, 28, $WS_GROUP)
GUICtrlSetOnEvent($ButtonOk, "OkBtn")
Global $Tab = GUICtrlCreateTab(8, 4, 401, 449)
GUICtrlSetResizing($Tab, $GUI_DOCKWIDTH + $GUI_DOCKHEIGHT)
Global $TabSheet1 = GUICtrlCreateTabItem("Syncronisation")
Global $ChkMPSync = GUICtrlCreateCheckbox("Synchronize MovingPictures database", 25, 40, 217, 17)
GUICtrlSetOnEvent($ChkMPSync, "ChkMPSyncClick")
Global $ChkTVSync = GUICtrlCreateCheckbox("Synchronize TVSeries database", 25, 60, 209, 17)
GUICtrlSetOnEvent($ChkTVSync, "ChkTVSyncClick")
Global $ConfigMpDb = GUICtrlCreateButton("Database", 322, 40, 67, 18, $WS_GROUP)
GUICtrlSetState($ConfigMpDb, $GUI_DISABLE)
GUICtrlSetOnEvent($ConfigMpDb, "ConfigMpDbClick")
Global $ConfigTvDb = GUICtrlCreateButton("Database", 322, 61, 67, 18, $WS_GROUP)
GUICtrlSetState($ConfigTvDb, $GUI_DISABLE)
GUICtrlSetOnEvent($ConfigTvDb, "ConfigTvDbClick")
Global $ChkMusicSync = GUICtrlCreateCheckbox("Synchronize Music database", 25, 80, 209, 17)
GUICtrlSetOnEvent($ChkMusicSync, "ChkMusicSyncClick")
Global $ConfigMusicDb = GUICtrlCreateButton("Database", 322, 81, 67, 18, $WS_GROUP)
GUICtrlSetState($ConfigMusicDb, $GUI_DISABLE)
GUICtrlSetOnEvent($ConfigMusicDb, "ConfigMusicDbClick")
Global $Group1 = GUICtrlCreateGroup("Profiles", 16, 108, 385, 297)
Global $ListViewProfiles = GUICtrlCreateListView("Name|Source|Destination|Type", 32, 224, 353, 137, -1, BitOR($WS_EX_CLIENTEDGE, $LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT))
GUICtrlSendMsg($ListViewProfiles, $LVM_SETCOLUMNWIDTH, 0, 100)
GUICtrlSendMsg($ListViewProfiles, $LVM_SETCOLUMNWIDTH, 1, 100)
GUICtrlSendMsg($ListViewProfiles, $LVM_SETCOLUMNWIDTH, 2, 100)
GUICtrlSendMsg($ListViewProfiles, $LVM_SETCOLUMNWIDTH, 3, 50)
Global $InputSource = GUICtrlCreateInput("", 96, 167, 161, 21)
Global $Label1 = GUICtrlCreateLabel("Source", 32, 168, 38, 17)
Global $BtnProfileAdd = GUICtrlCreateButton("Add", 320, 165, 67, 57, $WS_GROUP)
GUICtrlSetOnEvent($BtnProfileAdd, "BtnProfileAddClick")
Global $BtnProfileUnmark = GUICtrlCreateButton("Un-Mark All", 32, 368, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent($BtnProfileUnmark, "BtnProfileUnmarkClick")
Global $BtnProfileMark = GUICtrlCreateButton("Mark All", 112, 368, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent($BtnProfileMark, "BtnProfileMarkClick")
Global $BtnProfileDel = GUICtrlCreateButton("Delete", 312, 368, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent($BtnProfileDel, "BtnProfileDelClick")
Global $InputDestination = GUICtrlCreateInput("", 96, 199, 161, 21)
Global $Label2 = GUICtrlCreateLabel("Destination", 32, 200, 57, 17)
Global $Button13 = GUICtrlCreateButton("Browse", 256, 165, 59, 25, $WS_GROUP)
GUICtrlSetOnEvent($Button13, "BtnSourceBrowseClick")
Global $Button14 = GUICtrlCreateButton("Browse", 256, 197, 59, 25, $WS_GROUP)
GUICtrlSetOnEvent($Button14, "BtnDestinationBrowseClick")
Global $Label3 = GUICtrlCreateLabel("Name", 32, 136, 32, 17)
Global $InputProfileName = GUICtrlCreateInput("", 96, 135, 121, 21)
Global $BtnProfileEdit = GUICtrlCreateButton("Edit", 232, 368, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent($BtnProfileEdit, "BtnProfileEditClick")
Global $Label10 = GUICtrlCreateLabel("Type", 224, 136, 28, 17)
Global $ComboProfileTypes = GUICtrlCreateCombo("", 256, 136, 129, 25, BitOR($CBS_DROPDOWNLIST, $CBS_AUTOHSCROLL))
GUICtrlSetData($ComboProfileTypes, "MovingPictures|TVSeries|Music|Other")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $TabSheet2 = GUICtrlCreateTabItem("Resume/Suspend")
Global $Group2 = GUICtrlCreateGroup("Resume", 16, 36, 385, 217)
Global $ChkResMP = GUICtrlCreateCheckbox("Restart MediaPortal", 32, 71, 137, 17)
Global $ChkResDev = GUICtrlCreateCheckbox("Reinitialize device:", 32, 87, 137, 17)
GUICtrlSetOnEvent($ChkResDev, "ChkResDevClick")
Global $Combo1 = GUICtrlCreateCombo("", 48, 105, 273, 25)
GUICtrlSetState($Combo1, $GUI_DISABLE)
Global $ChkResProg = GUICtrlCreateCheckbox("Execute specific program:", 32, 132, 169, 17)
Global $InputOther1Exe = GUICtrlCreateInput("", 48, 150, 273, 21)
GUICtrlSetState($InputOther1Exe, $GUI_DISABLE)
Global $Button2 = GUICtrlCreateButton("Browse", 327, 152, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button2, "BrowseOther1Exe")
Global $ChkResTV = GUICtrlCreateCheckbox("Restart TV Service", 32, 55, 129, 17)
Global $ChkWOL = GUICtrlCreateCheckbox("WOL Server", 32, 180, 169, 17)
Global $Label18 = GUICtrlCreateLabel("PC-name:", 50, 203, 50, 17)
Global $InputClient = GUICtrlCreateInput("", 106, 200, 121, 21)
Global $BtnGetIP = GUICtrlCreateButton("Get IP/MAC", 232, 201, 67, 17, $WS_GROUP)
GUICtrlSetOnEvent($BtnGetIP, "BtnGetIPClick")
Global $InputMac = GUICtrlCreateInput("", 275, 225, 121, 21)
Global $Label19 = GUICtrlCreateLabel("MAC:", 242, 228, 30, 17)
Global $IPAddress = _GUICtrlIpAddress_Create($FormSettings, 106, 224, 122, 21)
_GUICtrlIpAddress_Set($IPAddress, "192.168.0.0")
Global $Label20 = GUICtrlCreateLabel("IP-address:", 50, 227, 57, 17)
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group3 = GUICtrlCreateGroup("Suspend", 16, 260, 385, 105)
Global $ChkSuspTV = GUICtrlCreateCheckbox("Exit TV Service", 29, 280, 121, 17)
Global $ChkSuspMP = GUICtrlCreateCheckbox("Exit MediaPortal", 29, 297, 137, 17)
Global $ChkSuspProg = GUICtrlCreateCheckbox("Execute specific program:", 29, 313, 169, 17)
Global $InputOther2Exe = GUICtrlCreateInput("", 45, 331, 273, 21)
GUICtrlSetState($InputOther2Exe, $GUI_DISABLE)
Global $Button1 = GUICtrlCreateButton("Browse", 324, 333, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button1, "BrowseOther2Exe")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $TabSheet3 = GUICtrlCreateTabItem("Path Settings")
GUICtrlSetState($TabSheet3, $GUI_SHOW)
Global $Group4 = GUICtrlCreateGroup("Mediaportal", 16, 36, 385, 81)
Global $Label4 = GUICtrlCreateLabel("MediaPortal.exe", 28, 63, 80, 17)
Global $InputMPexe = GUICtrlCreateInput("", 111, 61, 225, 21)
Global $Button3 = GUICtrlCreateButton("Browse", 341, 63, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button3, "BrowseMPexe")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group5 = GUICtrlCreateGroup("Master Datenbank", 16, 127, 385, 105)
Global $Label7 = GUICtrlCreateLabel("MovingPictures", 29, 153, 77, 17)
Global $InputMPdbSc = GUICtrlCreateInput("", 112, 151, 225, 21)
Global $Label8 = GUICtrlCreateLabel("TVSeries", 29, 179, 47, 17)
Global $InputTVdbSc = GUICtrlCreateInput("", 112, 177, 225, 21)
Global $Button6 = GUICtrlCreateButton("Browse", 342, 153, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button6, "BrowseMPdbSc")
Global $Button7 = GUICtrlCreateButton("Browse", 342, 179, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button7, "BrowseTVdbSc")
Global $Label14 = GUICtrlCreateLabel("Music", 29, 205, 32, 17)
Global $InputMusicdbSc = GUICtrlCreateInput("", 112, 203, 225, 21)
Global $Button4 = GUICtrlCreateButton("Browse", 342, 205, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button4, "BrowseMusicdbSc")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group6 = GUICtrlCreateGroup("Tools", 16, 355, 385, 81)
Global $Label6 = GUICtrlCreateLabel("SQLite3.exe", 29, 373, 62, 17)
Global $InputSQliteExe = GUICtrlCreateInput("", 112, 371, 225, 21)
Global $Label9 = GUICtrlCreateLabel("Devcon.exe", 29, 399, 62, 17)
Global $InputDevconExe = GUICtrlCreateInput("", 112, 397, 225, 21)
Global $Button5 = GUICtrlCreateButton("Browse", 342, 373, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button5, "BrowseSQLiteExe")
Global $Button8 = GUICtrlCreateButton("Browse", 342, 399, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button8, "BrowseDevconExe")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group8 = GUICtrlCreateGroup("Lokale Datenbank", 16, 241, 385, 105)
Global $Label11 = GUICtrlCreateLabel("MovingPictures", 29, 267, 77, 17)
Global $InputMPdbLc = GUICtrlCreateInput("", 112, 265, 225, 21)
Global $Label12 = GUICtrlCreateLabel("TVSeries", 29, 293, 47, 17)
Global $InputTVdbLc = GUICtrlCreateInput("", 112, 291, 225, 21)
Global $Button10 = GUICtrlCreateButton("Browse", 342, 267, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button10, "BrowseMPdbLc")
Global $Button11 = GUICtrlCreateButton("Browse", 342, 293, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button11, "BrowseTVdbLc")
Global $InputMusicdbLc = GUICtrlCreateInput("", 112, 318, 225, 21)
Global $Label15 = GUICtrlCreateLabel("Music", 29, 320, 32, 17)
Global $Button12 = GUICtrlCreateButton("Browse", 342, 320, 51, 17, $WS_GROUP)
GUICtrlSetOnEvent($Button12, "BrowseMusicdbLc")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $TabSheet4 = GUICtrlCreateTabItem("Settings")
Global $Group9 = GUICtrlCreateGroup("Message style", 16, 95, 385, 49)
Global $RadioTray = GUICtrlCreateRadio("Tray", 232, 114, 55, 17)
Global $RadioSPlash = GUICtrlCreateRadio("Splashscreen", 136, 114, 89, 17)
GUICtrlSetState($RadioSPlash, $GUI_CHECKED)
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Mode = GUICtrlCreateGroup("Exit mode", 16, 36, 385, 49)
Global $RadioKill = GUICtrlCreateRadio("Kill Service", 136, 57, 73, 17)
GUICtrlSetState($RadioKill, $GUI_CHECKED)
Global $RadioStop = GUICtrlCreateRadio("Stop Service", 232, 57, 89, 17)
Global $Label5 = GUICtrlCreateLabel("TV Service:", 44, 58, 60, 17)
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group10 = GUICtrlCreateGroup("Internet Update", 16, 149, 385, 49)
Global $ComboUpdate = GUICtrlCreateCombo("No Update", 136, 169, 257, 25)
GUICtrlSetData($ComboUpdate, "Check for SVN|Check for Stable")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group11 = GUICtrlCreateGroup("Suspendmode", 16, 205, 385, 49)
Global $ComboSuspend = GUICtrlCreateCombo("Standby (S3)", 136, 225, 257, 25)
GUICtrlSetData($ComboSuspend, "Hibernate (S4)|Shutdown (S5)")
GUICtrlCreateGroup("", -99, -99, 1, 1)
Global $Group7 = GUICtrlCreateGroup("Verifymethod", 16, 261, 385, 49)
Global $ComboVerifyMethod = GUICtrlCreateCombo("Exist & Size", 136, 281, 257, 25)
GUICtrlSetData($ComboVerifyMethod, "Exist|Size|MD5 (slow)")
GUICtrlCreateGroup("", -99, -99, 1, 1)
GUICtrlCreateTabItem("")
GUICtrlSetOnEvent($Tab, "TabSheetChange")
Global $LblVersion = GUICtrlCreateLabel("Version:", 11, 458, 189, 20)
GUICtrlSetFont($LblVersion, 10, 400, 0, "MS Sans Serif")
TraySetClick("9")
Global $Test = TrayCreateMenu("Testen")
Global $TestResTray = TrayCreateItem("Resume", $Test)
Global $TestSuspTray = TrayCreateItem("Suspend", $Test)
Global $Settings = TrayCreateItem("Einstellungen")
Global $Exit = TrayCreateItem("Exit")
TrayItemSetOnEvent($TestResTray, "TestResTray")
TrayItemSetOnEvent($TestSuspTray, "TestSuspTray")
TrayItemSetOnEvent($Settings, "SettingsTray")
TrayItemSetOnEvent($Exit, "ExitTray")
GUISetState(@SW_SHOW)
#EndRegion ### END Koda GUI section ###
TraySetIcon(@ScriptDir & "\Sync1.ico")
GUICtrlSetData($LblVersion, "Version: " & FileGetVersion(@ScriptFullPath))
#EndRegion Settings-Form

#Region Suspend-Form ;Dunkelt Bildschirm ab
Global $Suspend = GUICreate("", @DesktopWidth + 5, @DesktopHeight + 5, -5, -5, 0x80000000, 0x00000080);$WS_POPUP , $WS_EX_TOOLWINDOW
GUISetBkColor(0x0)
WinSetOnTop($Suspend, "", 1)
WinSetTrans($Suspend, "", 220)
Global $LabelTask = GUICtrlCreateLabel("", 10, @DesktopHeight / 2 - 200, @DesktopWidth - 10, 100, $SS_CENTER)
Global $LabelMsg = GUICtrlCreateLabel("", 10, @DesktopHeight / 2 - 50, @DesktopWidth - 10, 100, $SS_CENTER)
GUICtrlSetFont($LabelTask, 34, 800, 0, "Arial")
GUICtrlSetFont($LabelMsg, 30, 400, 2, "Arial")
GUISetState(@SW_HIDE, $Suspend)
#EndRegion Suspend-Form ;Dunkelt Bildschirm ab

#Region Database-Forms
;Fenster zur Konfiguration der zu synchronisiernden Databasetabellen
#include <TreeViewConstants.au3>
#include <GuiTreeView.au3>
#Region ### START Koda GUI section ### Form=databasemp.kxf
$FormDbMp = GUICreate("MovingPictures Database", 348, 224, 208, 127, BitOR($WS_SYSMENU, $WS_CAPTION, $WS_POPUP, $WS_POPUPWINDOW, $WS_BORDER, $WS_CLIPSIBLINGS), BitOR($WS_EX_TOPMOST, $WS_EX_WINDOWEDGE), $FormSettings)
GUISetIcon("C:\Dokumente und Einstellungen\Jochen\Eigene Dateien\AutoIT\SyncClient\Source\Sync1.ico")
GUISetOnEvent($GUI_EVENT_CLOSE, "CloseFormDbMp")
$TreeViewDbMp = GUICtrlCreateTreeView(8, 8, 249, 209, BitOR($TVS_HASBUTTONS, $TVS_HASLINES, $TVS_LINESATROOT, $TVS_DISABLEDRAGDROP, $TVS_SHOWSELALWAYS, $TVS_CHECKBOXES, $WS_GROUP, $WS_TABSTOP))
$MpDbStandard = GUICtrlCreateButton("Standard", 264, 8, 75, 25)
GUICtrlSetOnEvent(-1, "StandardMP")
$MpDbSelectAll = GUICtrlCreateButton("Select All", 264, 164, 75, 25)
GUICtrlSetOnEvent(-1, "SelectAllMp")
$MpDbUnselectAll = GUICtrlCreateButton("Unselect All", 264, 192, 75, 25)
GUICtrlSetOnEvent(-1, "UnselectAllMp")
#EndRegion ### END Koda GUI section ###

#Region ### START Koda GUI section ### Form=databasetv.kxf
$FormDbTv = GUICreate("TV-Series Database", 348, 224, 231, 176, BitOR($WS_SYSMENU, $WS_CAPTION, $WS_POPUP, $WS_POPUPWINDOW, $WS_BORDER, $WS_CLIPSIBLINGS), BitOR($WS_EX_TOPMOST, $WS_EX_WINDOWEDGE), $FormSettings)
GUISetIcon("C:\Dokumente und Einstellungen\Jochen\Eigene Dateien\AutoIT\SyncClient\Source\Sync1.ico")
GUISetOnEvent($GUI_EVENT_CLOSE, "CloseFormDbTv")
$TreeViewDbTv = GUICtrlCreateTreeView(8, 8, 249, 209, BitOR($TVS_HASBUTTONS, $TVS_HASLINES, $TVS_LINESATROOT, $TVS_DISABLEDRAGDROP, $TVS_SHOWSELALWAYS, $TVS_CHECKBOXES, $WS_GROUP, $WS_TABSTOP))
$TvDbStandard = GUICtrlCreateButton("Standard", 264, 8, 75, 25)
GUICtrlSetOnEvent(-1, "StandardTv")
$TvDbSelectAll = GUICtrlCreateButton("Select All", 264, 164, 75, 25)
GUICtrlSetOnEvent(-1, "SelectAllTv")
$TvDbUnselectAll = GUICtrlCreateButton("Unselect All", 264, 192, 75, 25)
GUICtrlSetOnEvent(-1, "UnselectAllTv")
#EndRegion ### END Koda GUI section ###

#Region ### START Koda GUI section ### Form=DatabaseMusic.kxf
$FormDbMusic = GUICreate("Music Database", 340, 220, 231, 176, BitOR($WS_SYSMENU, $WS_CAPTION, $WS_POPUP, $WS_POPUPWINDOW, $WS_BORDER, $WS_CLIPSIBLINGS), BitOR($WS_EX_TOPMOST, $WS_EX_WINDOWEDGE), $FormSettings)
GUISetIcon("C:\Dokumente und Einstellungen\Jochen\Eigene Dateien\AutoIT\SyncClient\Source\Sync1.ico")
GUISetOnEvent($GUI_EVENT_CLOSE, "CloseFormDbMusic")
$TreeViewDbMusic = GUICtrlCreateTreeView(8, 8, 249, 209, BitOR($TVS_HASBUTTONS, $TVS_HASLINES, $TVS_LINESATROOT, $TVS_DISABLEDRAGDROP, $TVS_SHOWSELALWAYS, $TVS_CHECKBOXES, $WS_GROUP, $WS_TABSTOP))
$MusicDbStandard = GUICtrlCreateButton("Standard", 264, 8, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent(-1, "StandardMusic")
$MusicDbSelectAll = GUICtrlCreateButton("Select All", 264, 164, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent(-1, "SelectAllTv")
$MusicDbUnselectAll = GUICtrlCreateButton("Unselect All", 264, 192, 75, 25, $WS_GROUP)
GUICtrlSetOnEvent(-1, "UnselectAllTv")
#EndRegion ### END Koda GUI section ###

#EndRegion Database-Forms

#EndRegion Gui


#Region GuiEventFunktionen
;-------------------------------
;------GUIEvent-FUNCTIONS-------
;-------------------------------
#Region Settings-Form

Func TabSheetChange()
	Switch GUICtrlRead($Tab, 1)
		Case $TabSheet2
			_GUICtrlIpAddress_ShowHide($IPAddress, @SW_SHOW)
		Case Else
			_GUICtrlIpAddress_ShowHide($IPAddress, @SW_HIDE)
	EndSwitch
EndFunc   ;==>TabSheetChange

;-------------------------------
;GUIBtn (OK) -> Prüfe Änderungen und speicher in Settings.ini
;Return: 0: Prüfung ok
;		 1: Prüfung nicht ok
;-------------------------------
Func OkBtn()
	Local $Problem = ""
	If GUICtrlRead($ChkMPSync) = $GUI_CHECKED Then
		If Not FileExists(GUICtrlRead($InputMPdbLc)) Then $Problem &= "- Pfad zu Lokaler MovingPictures Datenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputMPdbSc)) Then $Problem &= "- Pfad zu Master MovingPictures Datenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputSQliteExe)) Then $Problem &= "- Pfad zu SQLite3.exe prüfen/setzen." & @CRLF

		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Synchronisation der MovingPictures Datenbank gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return 1
		EndIf
	EndIf

	If GUICtrlRead($ChkTVSync) = $GUI_CHECKED Then
		If Not FileExists(GUICtrlRead($InputTVdbLc)) Then $Problem &= "- Pfad zu Lokaler TV-Series Datenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputTVdbSc)) Then $Problem &= "- Pfad zu Master TV-Series Datenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputSQliteExe)) Then $Problem &= "- Pfad zu SQLite3.exe prüfen/setzen." & @CRLF

		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Synchronisation der TV-Series Datenbank gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return 1
		EndIf
	EndIf

	If GUICtrlRead($ChkMusicSync) = $GUI_CHECKED Then
		If Not FileExists(GUICtrlRead($InputMusicdbSc)) Then $Problem &= "- Pfad zu Master Musikdatenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputMusicdbLc)) Then $Problem &= "- Pfad zu Lokaler Musikdatenbank prüfen/setzen." & @CRLF
		If Not FileExists(GUICtrlRead($InputSQliteExe)) Then $Problem &= "- Pfad zu SQLite3.exe prüfen/setzen." & @CRLF

		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Synchronisation der Musik Datenbank gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return 1
		EndIf
	EndIf


	If GUICtrlRead($ChkResMP) = 1 Then
		If Not FileExists($MPexe) Then $Problem &= "- MediaPortal [http://www.team-mediaportal.de/] installieren, bzw. Pfad setzen." & @CRLF

		If $Problem <> "" Then
			MsgBox(16, "Fehler", "MediaPortal neustarten gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return 1
		EndIf
	EndIf

	If GUICtrlRead($ChkResTV) = 1 Then
		If _Service_Exists("TVService") = 0 Then $Problem &= "- Der TV-Service existiert nicht. Installieren Sie Mediaportal [http://www.team-mediaportal.de/] neu." & @CRLF

		If $Problem <> "" Then
			MsgBox(16, "Fehler", "TV-Service neustarten gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf


	If GUICtrlRead($ChkResDev) = 1 Then
		If _GUICtrlEdit_GetText($Combo1) = "" Then $Problem &= "- Bitte erst ein Gerät zum neu initialisieren wählen." & @CRLF
		If Not FileExists($DevconExe) Then $Problem &= "- Pfad zu Devcon.exe prüfen/setzen." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Gerät neu initalisieren gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	If GUICtrlRead($ChkResProg) = 1 Then
		If Not FileExists($Other1Exe) Then $Problem &= "- Pfad zu beliebigen Programm, das bei Resume ausgeführt werden soll, prüfen/setzen." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Beliebiges Programm ausführen gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	If GUICtrlRead($ChkSuspMP) = 1 Then
		If Not FileExists($MPexe) Then $Problem &= "- MediaPortal [http://www.team-mediaportal.de/] installieren, bzw. Pfad setzen." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "MediaPortal beenden gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	If GUICtrlRead($ChkSuspTV) = 1 Then
		If _Service_Exists("TVService") = 0 Then $Problem &= "- Der TV-Service existiert nicht. Installieren Sie Mediaportal [http://www.team-mediaportal.de/] neu." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "TV-Service beenden gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	If GUICtrlRead($ChkSuspProg) = 1 Then
		If Not FileExists($Other2Exe) Then $Problem &= "- Pfad zu beliebigen Programm, das bei Suspend ausgeführt werden soll, prüfen/setzen." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "Beliebiges Programm ausführen gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	If GUICtrlRead($ChkWOL) = 1 Then
		If _GUICtrlEdit_GetText($InputMac) = "" Then $Problem &= "- Bitte MAC-Adresse des Servers eintragen." & @CRLF
		If _GUICtrlIpAddress_Get($IPAddress) = "" Then $Problem &= "- Bitte IP-Adresse des Servers eintragen." & @CRLF
		If $Problem <> "" Then
			MsgBox(16, "Fehler", "WOL des Servers gewählt." & @CRLF & @CRLF & "Folgende Konflikte sind dabei aufgetreten:" & @CRLF & $Problem)
			Return
		EndIf
	EndIf

	Write()
EndFunc   ;==>OkBtn

;GUIBtn (Abbrechen) -> Verwerfe Eingetragene Profilnamen & verstecke GUI!
Func AbbrechenBtn()
	GUISetState(@SW_HIDE, $FormSettings)
EndFunc   ;==>AbbrechenBtn

Func ChkMPSyncClick()
	If GUICtrlRead($ChkMPSync) = 1 Then
		GUICtrlSetState($ConfigMpDb, $GUI_ENABLE)

		If FileExists($MPConfigDir & "\thumbs\MovingPictures\") Then
			Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
			For $i = 0 To $Items - 1
				Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
				If $itemTxt[1] = "MovingPictures Thumbs" Then Return
			Next

			GUICtrlSetData($InputProfileName, "MovingPictures Thumbs")
			GUICtrlSetData($ComboProfileTypes, "MovingPictures")
			GUICtrlSetData($InputDestination, $MPConfigDir & "\thumbs\MovingPictures\")

			$MpdbScSplit = StringSplit(GUICtrlRead($InputMPdbSc), "\", 2)
			Local $SourceDir = ""
			For $j = 1 To UBound($MpdbScSplit) - 3
				$SourceDir = $SourceDir & "\" & $MpdbScSplit[$j]
			Next
			$SourceDir = $SourceDir & "\thumbs\MovingPictures\"

			If FileExists($SourceDir) Then
				GUICtrlSetData($InputSource, $SourceDir)
				BtnProfileAddClick()
			EndIf
		EndIf

	Else
		GUICtrlSetState($ConfigMpDb, $GUI_DISABLE)

		Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
		For $i = 0 To $Items - 1
			Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
			If $itemTxt[4] = "MovingPictures" Then
				Switch MsgBox(4, "Request", "Do you like also to delete the regarding Syncronisationprofile(s)?")
					Case 6 ;ja
						_GUICtrlListView_DeleteItem(GUICtrlGetHandle($ListViewProfiles), $i)
						$i -= 1
					Case 7 ;nein
						ExitLoop
				EndSwitch
			EndIf
		Next
	EndIf
EndFunc   ;==>ChkMPSyncClick

Func ChkTVSyncClick()
	If GUICtrlRead($ChkTVSync) = 1 Then
		GUICtrlSetState($ConfigTvDb, $GUI_ENABLE)

		If FileExists($MPConfigDir & "\thumbs\MPTVSeriesBanners\") Then
			Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
			For $i = 0 To $Items - 1
				Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
				If $itemTxt[1] = "TVSeries Thumbs" Then Return
			Next

			GUICtrlSetData($InputProfileName, "TVSeries Thumbs")
			GUICtrlSetData($ComboProfileTypes, "TVSeries")
			GUICtrlSetData($InputDestination, $MPConfigDir & "\thumbs\MPTVSeriesBanners\")

			$TVdbScSplit = StringSplit(GUICtrlRead($InputTVdbSc), "\", 2)
			Local $SourceDir = ""
			For $j = 1 To UBound($TVdbScSplit) - 3
				$SourceDir = $SourceDir & "\" & $TVdbScSplit[$j]
			Next
			$SourceDir = $SourceDir & "\thumbs\MPTVSeriesBanners\"

			If FileExists($SourceDir) Then
				GUICtrlSetData($InputSource, $SourceDir)
				BtnProfileAddClick()
			EndIf


			Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
			For $i = 0 To $Items - 1
				Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
				If $itemTxt[1] = "TVSeries Fanarts" Then Return
			Next

			GUICtrlSetData($InputProfileName, "TVSeries Fanarts")
			GUICtrlSetData($ComboProfileTypes, "TVSeries")
			GUICtrlSetData($InputDestination, $MPConfigDir & "\thumbs\Fan Art\")

			$TVdbScSplit = StringSplit(GUICtrlRead($InputTVdbSc), "\", 2)
			Local $SourceDir = ""
			For $j = 1 To UBound($TVdbScSplit) - 3
				$SourceDir = $SourceDir & "\" & $TVdbScSplit[$j]
			Next
			$SourceDir = $SourceDir & "\thumbs\Fan Art\"

			If FileExists($SourceDir) Then
				GUICtrlSetData($InputSource, $SourceDir)
				BtnProfileAddClick()
			EndIf
		EndIf

	Else
		GUICtrlSetState($ConfigTvDb, $GUI_DISABLE)

		Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
		For $i = 0 To $Items - 1
			Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
			If $itemTxt[4] = "TVSeries" Then
				Switch MsgBox(4, "Request", "Do you like also to delete the regarding Syncronisationprofile(s)?")
					Case 6 ;ja
						_GUICtrlListView_DeleteItem(GUICtrlGetHandle($ListViewProfiles), $i)
						$i -= 1
					Case 7 ;nein
						ExitLoop
				EndSwitch
			EndIf
		Next
	EndIf
EndFunc   ;==>ChkTVSyncClick

Func ChkMusicSyncClick()
	If GUICtrlRead($ChkMusicSync) = 1 Then
		GUICtrlSetState($ConfigMusicDb, $GUI_ENABLE)

		If FileExists($MPConfigDir & "\thumbs\Music\") Then
			Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
			For $i = 0 To $Items - 1
				Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
				If $itemTxt[1] = "Music Thumbs" Then Return
			Next

			GUICtrlSetData($InputProfileName, "Music Thumbs")
			GUICtrlSetData($ComboProfileTypes, "Music")
			GUICtrlSetData($InputDestination, $MPConfigDir & "\thumbs\Music\")

			$MusicdbScSplit = StringSplit(GUICtrlRead($InputMusicdbSc), "\", 2)
			Local $SourceDir = ""
			For $j = 1 To UBound($MusicdbScSplit) - 3
				$SourceDir = $SourceDir & "\" & $MusicdbScSplit[$j]
			Next
			$SourceDir = $SourceDir & "\thumbs\Music\"

			If FileExists($SourceDir) Then
				GUICtrlSetData($InputSource, $SourceDir)
				BtnProfileAddClick()
			EndIf
		EndIf

	Else
		GUICtrlSetState($ConfigMusicDb, $GUI_DISABLE)

		Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
		For $i = 0 To $Items - 1
			Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
			If $itemTxt[4] = "Music" Then
				Switch MsgBox(4, "Request", "Do you like also to delete the regarding Syncronisationprofile(s)?")
					Case 6 ;ja
						_GUICtrlListView_DeleteItem(GUICtrlGetHandle($ListViewProfiles), $i)
						$i -= 1
					Case 7 ;nein
						ExitLoop
				EndSwitch
			EndIf
		Next
	EndIf
EndFunc   ;==>ChkMusicSyncClick

Func BtnSourceBrowseClick()
	$var = FileSelectFolder("Please choose your source directory:", "", 7, "")
	If @error <> 1 Then
		$Source = $var
		_GUICtrlEdit_SetText($InputSource, $Source)
	EndIf
EndFunc   ;==>BtnSourceBrowseClick

Func BtnDestinationBrowseClick()
	$var = FileSelectFolder("Please choose your destination directory:", "", 7, "")
	If @error <> 1 Then
		$Destination = $var
		_GUICtrlEdit_SetText($InputDestination, $Destination)
	EndIf
EndFunc   ;==>BtnDestinationBrowseClick

Func BtnProfileAddClick()
	Local $Profilename = GUICtrlRead($InputProfileName)
	Local $Source = GUICtrlRead($InputSource)
	Local $Destination = GUICtrlRead($InputDestination)
	Local $ProfileType = GUICtrlRead($ComboProfileTypes)

	;Prüfung ob Source/Destination-Path existiert
	Select
		Case $Source = "" Or $Destination = "" Or FileExists($Source) = 0 Or FileExists($Destination) = 0
			MsgBox(65, "Error", "Please enter a valid Source/Destination path!")
			Return
		Case $ProfileType = ""
			MsgBox(65, "Error", "Please enter a valid Profiletype!")
		Case $Profilename = ""
			MsgBox(65, "Error", "Please enter a valid Profilename!")
	EndSelect

	Select
		Case _GUICtrlButton_GetText($BtnProfileAdd) = "Confirm"
			Local $EditItem = _GUICtrlListView_GetSelectedIndices($ListViewProfiles, True)

			_GUICtrlListView_SetItem($ListViewProfiles, $Profilename, $EditItem[1], 0)
			_GUICtrlListView_SetItem($ListViewProfiles, $Source, $EditItem[1], 1)
			_GUICtrlListView_SetItem($ListViewProfiles, $Destination, $EditItem[1], 2)
			_GUICtrlListView_SetItem($ListViewProfiles, $ProfileType, $EditItem[1], 3)

			_GUICtrlButton_SetText($BtnProfileAdd, "Add")
			_GUICtrlButton_Enable($BtnProfileEdit, True)
			_GUICtrlButton_Enable($BtnProfileDel, True)
			_GUICtrlButton_Enable($BtnProfileMark, True)
			_GUICtrlButton_Enable($BtnProfileUnmark, True)

			GUICtrlSetState($ListViewProfiles, $GUI_ENABLE)

		Case _GUICtrlButton_GetText($BtnProfileAdd) = "Add"

			;Prüfung ob Profilname bereits vergeben
			Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
			For $i = 0 To $Items - 1
				Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
				If $itemTxt[1] = $Profilename Then
					MsgBox(0, "Invalid profile name!", "Profile name already used!")
					Return
				EndIf
			Next

			;Profil wird zur Listview hinzugefügt
			Local $row = _GUICtrlListView_AddItem($ListViewProfiles, $Profilename)
			_GUICtrlListView_AddSubItem($ListViewProfiles, $row, $Source, 1)
			_GUICtrlListView_AddSubItem($ListViewProfiles, $row, $Destination, 2)
			_GUICtrlListView_AddSubItem($ListViewProfiles, $row, $ProfileType, 3)
	EndSelect

	GUICtrlSetData($InputSource, "")
	GUICtrlSetData($InputDestination, "")
	GUICtrlSetData($InputProfileName, "")
	AutosizeColumns($ListViewProfiles)
EndFunc   ;==>BtnProfileAddClick

Func BtnProfileEditClick()
	Local $Edititems = _GUICtrlListView_GetSelectedIndices($ListViewProfiles, True)
	If $Edititems[0] = 0 Then
		MsgBox(0, "Error", "No item selected!")
	Else
		GUICtrlSetState($ListViewProfiles, $GUI_DISABLE)
		Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, _GUICtrlListView_GetSelectedColumn($ListViewProfiles))
		GUICtrlSetData($InputProfileName, $itemTxt[1])
		GUICtrlSetData($InputSource, $itemTxt[2])
		GUICtrlSetData($InputDestination, $itemTxt[3])
		GUICtrlSetData($ComboProfileTypes, $itemTxt[4])
		_GUICtrlButton_SetText($BtnProfileAdd, "Confirm")
		_GUICtrlButton_Enable($BtnProfileEdit, False)
		_GUICtrlButton_Enable($BtnProfileDel, False)
		_GUICtrlButton_Enable($BtnProfileMark, False)
		_GUICtrlButton_Enable($BtnProfileUnmark, False)
	EndIf
EndFunc   ;==>BtnProfileEditClick

Func BtnProfileDelClick()
	Local $DelItem = _GUICtrlListView_GetSelectedIndices($ListViewProfiles, True)
	If Not $DelItem[0] = 0 Then
		_GUICtrlListView_DeleteItem(GUICtrlGetHandle($ListViewProfiles), $DelItem[1])
	Else
		MsgBox(0, "Error", "No item selected!")
	EndIf
EndFunc   ;==>BtnProfileDelClick

Func BtnProfileMarkClick()
	_GUICtrlListView_SetItemChecked($ListViewProfiles, -1, True)
EndFunc   ;==>BtnProfileMarkClick

Func BtnProfileUnmarkClick()
	_GUICtrlListView_SetItemChecked($ListViewProfiles, -1, False)
EndFunc   ;==>BtnProfileUnmarkClick

Func ConfigMpDbClick()
	ShowMpDbForm()
EndFunc   ;==>ConfigMpDbClick

Func ConfigTvDbClick()
	ShowTvDbForm()
EndFunc   ;==>ConfigTvDbClick

Func ConfigMusicDbClick()
	ShowMusicDbForm()
EndFunc   ;==>ConfigMusicDbClick

Func ConfigMpFilesClick()
	ShowFilesForm()
EndFunc   ;==>ConfigMpFilesClick

Func ConfigTvFilesClick()
	ShowFilesForm()
EndFunc   ;==>ConfigTvFilesClick

Func ConfigMusicFilesClick()
	ShowFilesForm()
EndFunc   ;==>ConfigMusicFilesClick

Func BtnGetIPClick()
	Local $IP, $Mac = ""
	$IP = get_ip(GUICtrlRead($InputClient))
	_GUICtrlIpAddress_Set($IPAddress, $IP)
	If $IP <> $DefaultIP Then $Mac = get_mac(_GUICtrlIpAddress_Get($IPAddress))
	GUICtrlSetData($InputMac, $Mac)
EndFunc   ;==>BtnGetIPClick

Func BrowseMPexe()
	$var = FileOpenDialog("Durchsuchen", $MPAppDir, "(*.exe)", 1)
	If @error <> 1 Then
		$MPexe = $var
		_GUICtrlEdit_SetText($InputMPexe, $MPexe)
	EndIf
EndFunc   ;==>BrowseMPexe

Func BrowseMPdbSc()
	$var = FileOpenDialog("Durchsuchen", "\", "(*.db3)", 1)
	If @error <> 1 Then
		$MPdbSc = $var
		_GUICtrlEdit_SetText($InputMPdbSc, $MPdbSc)
	EndIf
EndFunc   ;==>BrowseMPdbSc

Func BrowseTVdbSc()
	$var = FileOpenDialog("Durchsuchen", "\", "(*.db3)", 1)
	If @error <> 1 Then
		$TVdbSc = $var
		_GUICtrlEdit_SetText($InputTVdbSc, $TVdbSc)
	EndIf
EndFunc   ;==>BrowseTVdbSc

Func BrowseMusicdbSc()
	$var = FileOpenDialog("Durchsuchen", "\", "(*.db3)", 1)
	If @error <> 1 Then
		$MusicdbSc = $var
		_GUICtrlEdit_SetText($InputMusicdbSc, $MusicdbSc)
	EndIf
EndFunc   ;==>BrowseMusicdbSc

Func BrowseMPdbLc()
	$var = FileOpenDialog("Durchsuchen", $MPConfigDir, "(*.db3)", 1)
	If @error <> 1 Then
		$MPdbLc = $var
		_GUICtrlEdit_SetText($InputMPdbLc, $MPdbLc)
	EndIf
EndFunc   ;==>BrowseMPdbLc

Func BrowseTVdbLc()
	$var = FileOpenDialog("Durchsuchen", $MPConfigDir, "(*.db3)", 1)
	If @error <> 1 Then
		$TVdbLc = $var
		_GUICtrlEdit_SetText($InputTVdbLc, $TVdbLc)
	EndIf
EndFunc   ;==>BrowseTVdbLc

Func BrowseMusicdbLc()
	$var = FileOpenDialog("Durchsuchen", $MPConfigDir, "(*.db3)", 1)
	If @error <> 1 Then
		$MusicdbLc = $var
		_GUICtrlEdit_SetText($InputMusicdbLc, $MusicdbLc)
	EndIf
EndFunc   ;==>BrowseMusicdbLc

Func BrowseSQLiteExe()
	$var = FileOpenDialog("Durchsuchen", @ScriptDir, "(*.exe)", 1)
	If @error <> 1 Then
		$SQliteExe = $var
		_GUICtrlEdit_SetText($InputSQliteExe, $SQliteExe)
	EndIf
EndFunc   ;==>BrowseSQLiteExe

Func BrowseDevconExe()
	$var = FileOpenDialog("Durchsuchen", @ScriptDir, "(*.exe)", 1)
	If @error <> 1 Then
		$DevconExe = $var
		_GUICtrlEdit_SetText($InputDevconExe, $DevconExe)
	EndIf
EndFunc   ;==>BrowseDevconExe

Func BrowseOther1Exe()
	$var = FileOpenDialog("Durchsuchen", "\", "(*.exe)", 1)
	If @error <> 1 Then
		$Other1Exe = $var
		_GUICtrlEdit_SetText($InputOther1Exe, $Other1Exe)
	EndIf
EndFunc   ;==>BrowseOther1Exe

Func BrowseOther2Exe()
	$var = FileOpenDialog("Durchsuchen", "\", "(*.exe)", 1)
	If @error <> 1 Then
		$Other2Exe = $var
		_GUICtrlEdit_SetText($InputOther2Exe, $Other2Exe)
	EndIf
EndFunc   ;==>BrowseOther2Exe

Func ChkResDevClick()
	If GUICtrlRead($ChkResDev) = 1 Then
		GUICtrlSetState($Combo1, $GUI_ENABLE)
	Else
		GUICtrlSetState($Combo1, $GUI_DISABLE)
	EndIf



EndFunc   ;==>ChkResDevClick

#EndRegion Settings-Form

#Region Tray
Func TestResTray()
	StartResTasks()
EndFunc   ;==>TestResTray

Func TestSuspTray()
	StartSusTasks()
EndFunc   ;==>TestSuspTray

;TrayBtn (Settings) -> Aufruf des SettingsGUI
Func SettingsTray()
	Read()
	TabSheetChange()
	GUISetState(@SW_SHOW, $FormSettings)
EndFunc   ;==>SettingsTray

;TrayBtn (Exit) -> Beende Skript!
Func ExitTray()
	FileCopy("log.txt", "log.bak", 1)
	FileDelete("log.txt")
	Exit
EndFunc   ;==>ExitTray
#EndRegion Tray

#Region Files-Forms
Func ShowFilesForm()

EndFunc   ;==>ShowFilesForm


#EndRegion Files-Forms

#Region Database-Forms
Func ShowMpDbForm()
	_GUICtrlTreeView_DeleteAll($TreeViewDbMp)
	If FileExists($MPdbSc) Then
		GetDbTables($TreeViewDbMp, $MPdbSc)
		SetChecked($TreeViewDbMp, $TablesMp)
		GUISetState(@SW_DISABLE, $FormSettings)
		GUISetState(@SW_SHOW, $FormDbMp)
	Else
		MsgBox(0, "MovingPictures Master-Dantenbank Fehler!", "Kein korrekter Pfad zur MovingPictures Master-Dantenbank angegeben.")
	EndIf

EndFunc   ;==>ShowMpDbForm

Func ShowTvDbForm()
	If FileExists($TVdbSc) Then
		_GUICtrlTreeView_DeleteAll($TreeViewDbTv)
		GetDbTables($TreeViewDbTv, $TVdbSc)
		SetChecked($TreeViewDbTv, $TablesTv)
		GUISetState(@SW_DISABLE, $FormSettings)
		GUISetState(@SW_SHOW, $FormDbTv)
	Else
		MsgBox(0, "TV-Series Master-Dantenbank Fehler!", "Kein korrekter Pfad zur TV-Series Master-Dantenbank angegeben.")
	EndIf

EndFunc   ;==>ShowTvDbForm

Func ShowMusicDbForm()
	If FileExists($MusicdbSc) Then
		_GUICtrlTreeView_DeleteAll($TreeViewDbMusic)
		GetDbTables($TreeViewDbMusic, $MusicdbSc)
		SetChecked($TreeViewDbMusic, $TablesMusic)
		GUISetState(@SW_DISABLE, $FormSettings)
		GUISetState(@SW_SHOW, $FormDbMusic)
	Else
		MsgBox(0, "Musik Master-Dantenbank Fehler!", "Kein korrekter Pfad zur Musik Master-Dantenbank angegeben.")
	EndIf

EndFunc   ;==>ShowMusicDbForm

Func GetDbTables($TreeViewHandle, $DB)
	Local $abfrage, $ArrayLine

	_SQLite_Startup()
	_SQLite_Open($DB)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		MsgBox(0, "Fehler", "Master-Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf
	_SQLite_Query(-1, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;", $abfrage)
	While _SQLite_FetchData($abfrage, $ArrayLine) = $SQLITE_OK
		$TableName = _ArrayToString($ArrayLine)
		GUICtrlCreateTreeViewItem($TableName, $TreeViewHandle)
	WEnd
	_SQLite_Close()
	_SQLite_Shutdown()
EndFunc   ;==>GetDbTables

Func CloseFormDbMp()
	$TablesMp = GetChecked($TreeViewDbMp)
	GUISetState(@SW_ENABLE, $FormSettings)
	GUISetState(@SW_HIDE, $FormDbMp)

EndFunc   ;==>CloseFormDbMp

Func CloseFormDbTv()
	$TablesTv = GetChecked($TreeViewDbTv)
	GUISetState(@SW_ENABLE, $FormSettings)
	GUISetState(@SW_HIDE, $FormDbTv)
EndFunc   ;==>CloseFormDbTv

Func CloseFormDbMusic()
	$TablesMusic = GetChecked($TreeViewDbMusic)
	GUISetState(@SW_ENABLE, $FormSettings)
	GUISetState(@SW_HIDE, $FormDbMusic)
EndFunc   ;==>CloseFormDbMusic

Func GetChecked($TreeViewHandle)
	Local $item
	Local $itemCount = _GUICtrlTreeView_GetCount($TreeViewHandle)
	;MsgBox(0,"",$itemCount)
	Local $ArrayChecked[1]
	$item = _GUICtrlTreeView_GetFirstItem($TreeViewHandle)
	If _GUICtrlTreeView_GetChecked($TreeViewHandle, $item) = True Then
		$itemTxt = _GUICtrlTreeView_GetText($TreeViewHandle, $item)
		_ArrayAdd($ArrayChecked, $itemTxt)
	EndIf
	Do
		$item = _GUICtrlTreeView_GetNext($TreeViewHandle, $item)
		If _GUICtrlTreeView_GetChecked($TreeViewHandle, $item) = True Then
			$itemTxt = _GUICtrlTreeView_GetText($TreeViewHandle, $item)
			_ArrayAdd($ArrayChecked, $itemTxt)
		EndIf
	Until _GUICtrlTreeView_GetNext($TreeViewHandle, $item) = 0
	_ArrayDelete($ArrayChecked, 0)
	Return $ArrayChecked
EndFunc   ;==>GetChecked

Func StandardMp()
	Local $StandardMp[16] = ["criteria", "criteria__filters", "filters", "filters__movie_info__black_list", "filters__movie_info__white_list", "menu", "menu_node", "movie_info__user_movie_settings", "movie_info__watched_history", "movie_node_settings", "node", "node__node", "settings", "sort_preferences", "user_movie_settings", "watched_history"]
	SetChecked($TreeViewDbMp, $StandardMp)
EndFunc   ;==>StandardMp

Func StandardTv()
	Local $StandardTv[5] = ["Views", "ignored_downloaded_files", "news", "options", "torrent"]
	SetChecked($TreeViewDbTv, $StandardTv)
EndFunc   ;==>StandardTv

Func StandardMusic()
	Local $StandardMusic[5] = ["sqlite_sequence", "scrobblemode", "scrobblesettings", "scrobbletags", "scrobbleusers"]
	SetChecked($TreeViewDbMusic, $StandardMusic)
EndFunc   ;==>StandardMusic

Func SetChecked($TreeViewHandle, $TablesArray)
	Local $item
	SelectAll($TreeViewHandle, False)
	If IsArray($TablesArray) Then
		For $element In $TablesArray
			$item = _GUICtrlTreeView_FindItem($TreeViewHandle, $element)
			If $item <> 0 Then _GUICtrlTreeView_SetChecked($TreeViewHandle, $item)
		Next
	EndIf
EndFunc   ;==>SetChecked

Func SelectAllMp()
	SelectAll($TreeViewDbMp, True)
EndFunc   ;==>SelectAllMp

Func UnselectAllMp()
	SelectAll($TreeViewDbMp, False)
EndFunc   ;==>UnselectAllMp

Func SelectAllTv()
	SelectAll($TreeViewDbTv, True)
EndFunc   ;==>SelectAllTv

Func UnselectAllTv()
	SelectAll($TreeViewDbTv, False)
EndFunc   ;==>UnselectAllTv

Func SelectAll($TreeViewHandle, $Status)
	Local $item
	$item = _GUICtrlTreeView_GetFirstItem($TreeViewHandle)
	_GUICtrlTreeView_SetChecked($TreeViewHandle, $item, $Status)
	Do
		$item = _GUICtrlTreeView_GetNext($TreeViewHandle, $item)
		_GUICtrlTreeView_SetChecked($TreeViewHandle, $item, $Status)
	Until _GUICtrlTreeView_GetNext($TreeViewHandle, $item) = 0
EndFunc   ;==>SelectAll
#EndRegion Database-Forms

#EndRegion GuiEventFunktionen

#Region GuiFunktionen

Func Abdunkeln()
	If $Splash = 1 Then GUISetState(@SW_SHOW, $Suspend)
EndFunc   ;==>Abdunkeln

Func Aufhellen()
	If $Splash = 1 Then GUISetState(@SW_HIDE, $Suspend)
EndFunc   ;==>Aufhellen

Func SetMsg($RetValue, $Task = $LastTask, $Msg = "", $Delete = 0)
	WriteLog($RetValue, $Task, $LastTask, $Msg)
	If $Task = "" Then $Task = $LastTask

	Select
		Case $Splash = 1
			SplashSetMsg($RetValue, $Task, $Msg)
		Case $Tray = 1
			TraySetMsg($RetValue, $Task, $Msg)
			If $Delete = 1 Then
				Sleep(3000)
				_TrayMsgBoxDelete()
			EndIf
	EndSelect
	$LastTask = $Task
EndFunc   ;==>SetMsg

;Variante SplashScreen
Func SplashSetMsg($RetValue, $Task, $Msg = "")
	GUICtrlSetData($LabelTask, $Task)
	GUICtrlSetColor($LabelTask, 0xC0C0C0)
	GUICtrlSetData($LabelMsg, $Msg)
	If $RetValue = 0 Then
		GUICtrlSetColor($LabelMsg, 0xC0C0C0)
	Else
		GUICtrlSetColor($LabelMsg, 0xCC0000)
		Sleep(2000)
	EndIf
	GUICtrlSetColor($LabelMsg, 0xC0C0C0)
EndFunc   ;==>SplashSetMsg

;Variante TraySlider
Func TraySetMsg($RetValue, $Task, $Msg = "")
	If _TrayMsgBoxExists() = 0 Then _TrayMsgBoxCreate("SyncClient", "", "", 400, 100, 0)

	If $RetValue = 0 Then
		_TrayMsgBoxSetBG("standard")
		_TrayMsgBoxSetNew($Task, $Msg)
	Else
		_TrayMsgBoxSetBG("error")
		_TrayMsgBoxSetNew($Task, $Msg)
		Sleep(2000)
	EndIf
EndFunc   ;==>TraySetMsg

Func WriteLog($RetValue, $Task, $LastTask, $Msg)
	Select
		Case $Task <> $LastTask And $Task <> ""
			_FileWriteLog("log.txt", "[Task]:  " & $Task)
		Case $RetValue = 0 And $Msg <> ""
			_FileWriteLog("log.txt", "[INFO]:  " & $Msg)
		Case $RetValue <> 0 And $Msg <> ""
			_FileWriteLog("log.txt", "[ERROR]:  " & $Msg)
		Case Else
	EndSelect
EndFunc   ;==>WriteLog

Func GetDevices()
	Local $Count = 0, $ArrayCount = 0, $total_devices = 0

	;liste löschen
	_GUICtrlComboBox_ResetContent($Combo1)

	;Build list of ALL device classes
	_DeviceAPI_GetClassDevices()

	;Anzahl der Devices bestimmen
	While _DeviceAPI_EnumDeviceInfo($Count)
		$total_devices += 1
		$Count += 1
	WEnd

	Dim $DevArray[$total_devices][2]
	$Count = 0

	While _DeviceAPI_EnumDeviceInfo($Count)
		$DevID = _DeviceAPI_GetDeviceRegistryProperty($SPDRP_HARDWAREID)
		$description = _DeviceAPI_GetDeviceRegistryProperty($SPDRP_DEVICEDESC)
		$friendly_name = _DeviceAPI_GetDeviceRegistryProperty($SPDRP_FRIENDLYNAME)
		If $friendly_name <> "" Then $description = $friendly_name

		If $DevID <> "" Then
			$DevArray[$ArrayCount][0] = $description
			$DevArray[$ArrayCount][1] = $DevID
			$ArrayCount += 1
		EndIf
		$Count += 1
	WEnd

	;Leere Einträge aus Array löschen
	Local $i = 0
	While $i <= UBound($DevArray) - 1
		If $DevArray[$i][1] = "" Or StringIsSpace($DevArray[$i][1]) = 1 Then
			_ArrayDelete($DevArray, $i)
		Else
			$i += 1
		EndIf
	WEnd

	;Array nach Alphabet sortieren
	_ArraySort($DevArray)

	;MsgBox(1,"enable",$DevArray[1][0])
	For $j = 0 To UBound($DevArray) - 1
		_GUICtrlComboBox_AddString($Combo1, $DevArray[$j][0])
	Next

EndFunc   ;==>GetDevices

Func AutosizeColumns($ListView)
	For $i = 0 To _GUICtrlListView_GetColumnCount($ListView) - 1
		_GUICtrlListView_SetColumnWidth($ListView, $i, $LVSCW_AUTOSIZE)
	Next
EndFunc   ;==>AutosizeColumns

Func Read()
	GetDevices()
	$DevID = IniRead(@ScriptDir & "\settings.ini", "Resume", "DeviceID", "")

	$TablesMp = StringSplit(IniRead(@ScriptDir & "\settings.ini", "Sync", "MP_Tables", ""), "|", 2)

	$TablesTv = StringSplit(IniRead(@ScriptDir & "\settings.ini", "Sync", "TV_Tables", ""), "|", 2)

	$TablesMusic = StringSplit(IniRead(@ScriptDir & "\settings.ini", "Sync", "Music_Tables", ""), "|", 2)

	$SyncMP = IniRead(@ScriptDir & "\settings.ini", "Sync", "MovingPictures", "")
	GUICtrlSetState($ChkMPSync, $SyncMP)

	If GUICtrlRead($ChkMPSync) = 1 Then
		GUICtrlSetState($ConfigMpDb, $GUI_ENABLE)
	Else
		GUICtrlSetState($ConfigMpDb, $GUI_DISABLE)
	EndIf

	$SyncTV = IniRead(@ScriptDir & "\settings.ini", "Sync", "TVSeries", "")
	GUICtrlSetState($ChkTVSync, $SyncTV)
	ChkTVSyncClick()

	$SyncMusic = IniRead(@ScriptDir & "\settings.ini", "Sync", "Music", "")
	GUICtrlSetState($ChkMusicSync, $SyncMusic)
	ChkMusicSyncClick()

	$ResMP = IniRead(@ScriptDir & "\settings.ini", "Resume", "Mediaportal", "")
	GUICtrlSetState($ChkResMP, $ResMP)

	$ResTV = IniRead(@ScriptDir & "\settings.ini", "Resume", "TVService", "")
	GUICtrlSetState($ChkResTV, $ResTV)

	$ResProg = IniRead(@ScriptDir & "\settings.ini", "Resume", "Program", "")
	GUICtrlSetState($ChkResProg, $ResProg)

	$ResDev = IniRead(@ScriptDir & "\settings.ini", "Resume", "Reset", "")
	GUICtrlSetState($ChkResDev, $ResDev)
	ChkResDevClick()

	$Wol = IniRead(@ScriptDir & "\settings.ini", "Resume", "Wol", "")
	GUICtrlSetState($ChkWOL, $Wol)

	$Server = IniRead(@ScriptDir & "\settings.ini", "Resume", "WolName", "")
	_GUICtrlEdit_SetText($InputClient, $Server)

	$IP = IniRead(@ScriptDir & "\settings.ini", "Resume", "WolIP", "")
	_GUICtrlIpAddress_Set($IPAddress, $IP)

	$MACAddress = IniRead(@ScriptDir & "\settings.ini", "Resume", "WolMac", "")
	_GUICtrlEdit_SetText($InputMac, $MACAddress)


	$SuspMP = IniRead(@ScriptDir & "\settings.ini", "Suspend", "Mediaportal", "")
	GUICtrlSetState($ChkSuspMP, $SuspMP)

	$SuspTV = IniRead(@ScriptDir & "\settings.ini", "Suspend", "TVService", "")
	GUICtrlSetState($ChkSuspTV, $SuspTV)

	$SuspProg = IniRead(@ScriptDir & "\settings.ini", "Suspend", "Program", "")
	GUICtrlSetState($ChkSuspProg, $SuspProg)

	$DevName = IniRead(@ScriptDir & "\settings.ini", "Resume", "DeviceName", "")
	_GUICtrlComboBox_SelectString($Combo1, $DevName)

	$MPdbLc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "MovingPicturesDBLc", $MPdbLcDefault)
	_GUICtrlEdit_SetText($InputMPdbLc, $MPdbLc)

	$TVdbLc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "TVSeriesDBLc", $TVdbLcDefault)
	_GUICtrlEdit_SetText($InputTVdbLc, $TVdbLc)

	$MusicdbLc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "MusicDBLc", $MusicdbLcDefault)
	_GUICtrlEdit_SetText($InputMusicdbLc, $MusicdbLc)

	$MPdbSc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "MovingPicturesDBSc", "")
	_GUICtrlEdit_SetText($InputMPdbSc, $MPdbSc)

	$TVdbSc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "TVSeriesDBSc", "")
	_GUICtrlEdit_SetText($InputTVdbSc, $TVdbSc)

	$MusicdbSc = IniRead(@ScriptDir & "\settings.ini", "DbPfade", "MusicDBSc", "")
	_GUICtrlEdit_SetText($InputMusicdbSc, $MusicdbSc)


	$MPexe = IniRead(@ScriptDir & "\settings.ini", "PrgmPfade", "MediaPortalExe", $MPexeDefault)
	_GUICtrlEdit_SetText($InputMPexe, $MPexe)

	$SQliteExe = IniRead(@ScriptDir & "\settings.ini", "PrgmPfade", "SQLiteExe", $SQliteExeDefault)
	_GUICtrlEdit_SetText($InputSQliteExe, $SQliteExe)

	$DevconExe = IniRead(@ScriptDir & "\settings.ini", "PrgmPfade", "DevconExe", $DevconExeDefault)
	_GUICtrlEdit_SetText($InputDevconExe, $DevconExe)

	$Other1Exe = IniRead(@ScriptDir & "\settings.ini", "PrgmPfade", "Other1Exe", "")
	_GUICtrlEdit_SetText($InputOther1Exe, $Other1Exe)

	$Other2Exe = IniRead(@ScriptDir & "\settings.ini", "PrgmPfade", "Other2Exe", "")
	_GUICtrlEdit_SetText($InputOther2Exe, $Other2Exe)

	$Kill = IniRead(@ScriptDir & "\settings.ini", "Exit", "Kill", "")
	GUICtrlSetState($RadioKill, $Kill)

	$Stop = IniRead(@ScriptDir & "\settings.ini", "Exit", "Stop", "")
	GUICtrlSetState($RadioStop, $Stop)

	$Tray = IniRead(@ScriptDir & "\settings.ini", "Message", "Tray", "")
	GUICtrlSetState($RadioTray, $Tray)

	$Splash = IniRead(@ScriptDir & "\settings.ini", "Message", "Splash", "")
	GUICtrlSetState($RadioSPlash, $Splash)

	$Update = IniRead(@ScriptDir & "\settings.ini", "Settings", "Update", "Check for Stable")
	GUICtrlSetData($ComboUpdate, $Update)

	$Suspendmode = IniRead(@ScriptDir & "\settings.ini", "Settings", "Suspendmode", "Standby (S3)")
	GUICtrlSetData($ComboSuspend, $Suspendmode)

	$verifyMethod = IniRead(@ScriptDir & "\settings.ini", "Settings", "Verifymethod", "Exist & Size")
	GUICtrlSetData($ComboVerifyMethod, $verifyMethod)
	;--------------------;
	;------Profiles------;
	;--------------------;
	_GUICtrlListView_DeleteAllItems(GUICtrlGetHandle($ListViewProfiles))
	Local $Items = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Count", "0")
	If $Items > 0 Then
		Local $Txt[$Items][4]
		For $i = 0 To $Items - 1
			For $j = 0 To UBound($Txt, 2) - 1
				$Txt[$i][$j] = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i & $j + 1, "")
			Next
		Next
		_GUICtrlListView_AddArray($ListViewProfiles, $Txt)

		For $i = 0 To $Items - 1
			$Selected = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i, "False")
			If $Selected = "True" Then
				_GUICtrlListView_SetItemChecked($ListViewProfiles, $i)
			EndIf
		Next
		AutosizeColumns($ListViewProfiles)
	EndIf

	;--------------------;
	;--------------------;

	GUISetState(@SW_HIDE, $FormSettings)


	If Not FileExists(@ScriptDir & "\settings.ini") Then GUISetState(@SW_SHOW, $FormSettings)
EndFunc   ;==>Read

Func Write()
	$DevName = _GUICtrlEdit_GetText($Combo1)
	If Not $DevName = "" Then $DevID = $DevArray[_ArraySearch($DevArray, $DevName)][1]

	IniWrite(@ScriptDir & "\settings.ini", "Resume", "DeviceName", $DevName)
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "DeviceID", $DevID)
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "Mediaportal", GUICtrlRead($ChkResMP))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "TVService", GUICtrlRead($ChkResTV))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "Program", GUICtrlRead($ChkResProg))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "Reset", GUICtrlRead($ChkResDev))

	IniWrite(@ScriptDir & "\settings.ini", "Resume", "Wol", GUICtrlRead($ChkWOL))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "WolName", _GUICtrlEdit_GetText($InputClient))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "WolIP", _GUICtrlIpAddress_Get($IPAddress))
	IniWrite(@ScriptDir & "\settings.ini", "Resume", "WolMac", _GUICtrlEdit_GetText($InputMac))

	IniWrite(@ScriptDir & "\settings.ini", "Suspend", "Mediaportal", GUICtrlRead($ChkSuspMP))
	IniWrite(@ScriptDir & "\settings.ini", "Suspend", "TVService", GUICtrlRead($ChkSuspTV))
	IniWrite(@ScriptDir & "\settings.ini", "Suspend", "Program", GUICtrlRead($ChkSuspProg))

	IniWrite(@ScriptDir & "\settings.ini", "Sync", "MP_Tables", _ArrayToString($TablesMp))
	IniWrite(@ScriptDir & "\settings.ini", "Sync", "TV_Tables", _ArrayToString($TablesTv))
	IniWrite(@ScriptDir & "\settings.ini", "Sync", "Music_Tables", _ArrayToString($TablesMusic))
	IniWrite(@ScriptDir & "\settings.ini", "Sync", "MovingPictures", GUICtrlRead($ChkMPSync))
	IniWrite(@ScriptDir & "\settings.ini", "Sync", "TVSeries", GUICtrlRead($ChkTVSync))
	IniWrite(@ScriptDir & "\settings.ini", "Sync", "Music", GUICtrlRead($ChkMusicSync))

	IniWrite(@ScriptDir & "\settings.ini", "PrgmPfade", "MediaPortalExe", $MPexe)
	IniWrite(@ScriptDir & "\settings.ini", "PrgmPfade", "SQLiteExe", $SQliteExe)
	IniWrite(@ScriptDir & "\settings.ini", "PrgmPfade", "DevconExe", $DevconExe)
	IniWrite(@ScriptDir & "\settings.ini", "PrgmPfade", "Other1Exe", $Other1Exe)
	IniWrite(@ScriptDir & "\settings.ini", "PrgmPfade", "Other2Exe", $Other2Exe)
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "MovingPicturesDBLc", GUICtrlRead($InputMPdbLc))
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "TVSeriesDBLc", GUICtrlRead($InputTVdbLc))
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "MusicDBLc", GUICtrlRead($InputMusicdbLc))
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "MovingPicturesDBSc", GUICtrlRead($InputMPdbSc))
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "TVSeriesDBSc", GUICtrlRead($InputTVdbSc))
	IniWrite(@ScriptDir & "\settings.ini", "DbPfade", "MusicDBSc", GUICtrlRead($InputMusicdbSc))

	IniWrite(@ScriptDir & "\settings.ini", "Exit", "Kill", GUICtrlRead($RadioKill))
	IniWrite(@ScriptDir & "\settings.ini", "Exit", "Stop", GUICtrlRead($RadioStop))

	IniWrite(@ScriptDir & "\settings.ini", "Message", "Splash", GUICtrlRead($RadioSPlash))
	IniWrite(@ScriptDir & "\settings.ini", "Message", "Tray", GUICtrlRead($RadioTray))

	IniWrite(@ScriptDir & "\settings.ini", "Settings", "Update", GUICtrlRead($ComboUpdate))
	IniWrite(@ScriptDir & "\settings.ini", "Settings", "Suspendmode", GUICtrlRead($ComboSuspend))
	IniWrite(@ScriptDir & "\settings.ini", "Settings", "Verifymethod", GUICtrlRead($ComboVerifyMethod))

	;------------------;
	;-----Profiles-----;
	;------------------;
	IniDelete(@ScriptDir & "\settings.ini", "Profiles")
	Local $Items = _GUICtrlListView_GetItemCount($ListViewProfiles)
	IniWrite(@ScriptDir & "\settings.ini", "Profiles", "Count", $Items)
	For $i = 0 To $Items - 1
		Local $itemTxt = _GUICtrlListView_GetItemTextArray($ListViewProfiles, $i)
		IniWrite(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i, _GUICtrlListView_GetItemChecked($ListViewProfiles, $i))
		For $j = 0 To UBound($itemTxt) - 1
			IniWrite(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i & $j, $itemTxt[$j])
		Next
	Next
	;-----------------;
	;-----------------;
	Read()
EndFunc   ;==>Write

#EndRegion GuiFunktionen

;-------------------------------
;---- Allgemeine-FUNCTIONS -----
;-------------------------------
#Region AllgemeineFunktionen

#Region Netzwerkfunktionen

; ===================================================================
; Function: WOL($IP,$MAC)
;          $IP       --- is ipadress of Server
;          $MAC     --- is the macadress
; ===================================================================

; Wake up on Lan Function (Open connection and broadcast to Lan)
Func WOL($IP, $Mac)
	SetMsg(0, "WOL", "Wecke Server...")
	$IPADRESS = StringSplit($IP, ".")
	$Broadcast = $IPADRESS[1] & "." & $IPADRESS[2] & "." & $IPADRESS[3] & "." & "255"
	$String = ""
	UDPStartup()
	$connexion = UDPOpen($Broadcast, 7)
	UDPSend($connexion, GenerateMagicPacket($Mac))
	UDPCloseSocket($connexion)
	UDPShutdown()
EndFunc   ;==>WOL

; This function generate the "Magic Packet"
Func GenerateMagicPacket($strMACAddress)

	$MagicPacket = ""
	$MACData = ""

	For $p = 1 To 11 Step 2
		$MACData = $MACData & HexToChar(StringMid($strMACAddress, $p, 2))
	Next

	For $p = 1 To 6
		$MagicPacket = HexToChar("ff") & $MagicPacket
	Next

	For $p = 1 To 16
		$MagicPacket = $MagicPacket & $MACData
	Next

	Return $MagicPacket

EndFunc   ;==>GenerateMagicPacket

; ===================================================================
; Function: get_mac($remote_ip)
;           $remote_ip      --- remote ip
; ===================================================================
Func get_mac($remote_ip)
	Ping($remote_ip, 1000)
	If @error = 0 Then
		$arpinfo = Run(@ComSpec & " /c ARP -a " & $remote_ip, @SystemDir, @SW_HIDE, 2)
		Sleep(400)
		$output = StdoutRead($arpinfo, -1)
		$aOutputLine = StringSplit($output, @CRLF)
		If UBound($aOutputLine) > 5 Then ; <=== added so script doesn't choke when processing the IP for the computer it's running on
			$macadress = StringMid($aOutputLine[7], 25, 17)
			$macadress = StringReplace($macadress, "-", "")
			Return $macadress
		EndIf ; <=== and this one...

	Else
		Return ""
	EndIf
EndFunc   ;==>get_mac

Func get_ip($ClientName)
	TCPStartup()
	$ClientIP = TCPNameToIP($ClientName)
	TCPShutdown()
	If $ClientIP = "" Then
		MsgBox(0, "Error", 'Client "' & $ClientName & '" not exists or is not reachable at this time!')
		Return $DefaultIP
	Else
		Return $ClientIP
	EndIf
EndFunc   ;==>get_ip

Func GetUserSID($ComputerName, $Username)
	Dim $UserSID, $oWshNetwork, $oUserAccount
	$objWMIService = ObjGet("winmgmts:{impersonationLevel=impersonate}!//" & $ComputerName & "/root/cimv2")
	$oUserAccounts = $objWMIService.ExecQuery("Select Name, SID from Win32_UserAccount")
	For $oUserAccount In $oUserAccounts
		If $Username = $oUserAccount.Name Then Return $oUserAccount.SID
	Next
	Return ""
EndFunc   ;==>GetUserSID

Func PingHost($Domain, $timeout = 500)
	SetMsg(0, "Prüfe Verbindung zu " & $Domain, "Warte...")

	If Ping($Domain, $timeout) <> 0 Then
		SetMsg(0, "", "Verbindung hergestellt!")
		Return 1
	Else
		SetMsg(1, "", "Verbindung konnte nicht hergestellt werden! Error:" & @error)
		Return 0
	EndIf
EndFunc   ;==>PingHost

;Wartet bis mind. ein Netzwerkadapter Connected ist.
Func WaitForConnection()
	Local $wbemFlagReturnImmediately = 0x10
	Local $wbemFlagForwardOnly = 0x20
	Local $colItems = ""
	Local $output = ""
	Local $strComputer = "localhost"
	Local $Count

	;Prüft ob Netzwerkverbindung besteht
	SetMsg(0, "Warte auf Netzwerkverbindung...", '')
	For $j = 0 To 20
		Local $Caption[1], $Index[1], $IP[1], $Status[1]
		$Caption[0] = 0
		$Index[0] = 0
		$IP[0] = 0
		$Status[0] = 0

		$objWMIService = ObjGet("winmgmts:\\" & $strComputer & "\root\CIMV2")
		$colItems = $objWMIService.ExecQuery("SELECT Description,Index FROM Win32_NetworkAdapter WHERE NetConnectionStatus is not null", "WQL", $wbemFlagReturnImmediately + $wbemFlagForwardOnly)

		For $objItem In $colItems
			_ArrayAdd($Caption, $objItem.Description)
			$Caption[0] = $Caption[0] + 1

			_ArrayAdd($Index, $objItem.Index)
			$Index[0] = $Index[0] + 1
		Next

		$Count = $Caption[0]

		For $i = 1 To $Count
			$colItems = $objWMIService.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE Index = " & $Index[$i], "WQL", $wbemFlagReturnImmediately + $wbemFlagForwardOnly)
			For $objItem In $colItems
				_ArrayAdd($IP, $objItem.IPAddress(0))
				$IP[0] = $IP[0] + 1
			Next
		Next

		$minus = 0

		For $i = 1 To $Count

			Select
				Case $IP[$i] = '0'
					$minus += 1
					_ArrayAdd($Status, "loos")
				Case $IP[$i] = '0.0.0.0'
					_ArrayAdd($Status, "offline")
				Case Else
					_ArrayAdd($Status, "online")
			EndSelect
		Next

		For $i = 1 To $Count
			If $Status[$i] = "online" Then
				SetMsg(0, "", 'Netzwerkadapter "' & $Caption[$i] & '"(IP:' & $IP[$i] & ') ist verbunden!')
				Return 1
			EndIf
		Next

		Sleep(300)
	Next

	SetMsg(1, "", 'Keine Netzwerkverbindung verfügbar!')
	Return 0

EndFunc   ;==>WaitForConnection
#EndRegion Netzwerkfunktionen


#Region Prozess-/Programmaufgaben
Func SuspendProcess($Process)
	_ProcessSuspend($Process)
EndFunc   ;==>SuspendProcess

Func ResumeProcess($Process)
	_ProcessResume($Process)
EndFunc   ;==>ResumeProcess

Func RunProg($ProgPath)
	Local $exe = StringTrimLeft($ProgPath, StringInStr($ProgPath, '\', 1, -1))
	Local $Name = StringTrimRight($exe, StringLen($exe) - StringInStr($exe, '.', 1, 1) + 1)
	SetMsg(0, $Name & " starten", "")
	Run('"' & $ProgPath & '"')

	If @error <> 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", $Name & " kann nicht gestartet werden!")
		Return $RetValue
	Else
		$RetValue = 0
		SetMsg($RetValue, "", $Name & " wurde gestartet!")
		Return $RetValue
	EndIf
EndFunc   ;==>RunProg

Func MPRestart()
	SetMsg(0, "MediaPortal neustarten", "")
	Local $RetValue = CloseProg("Mediaportal.exe")
	If $RetValue = 1 Then
		GetErrors($RetValue)
		SetMsg($RetValue, "", "MediaPortal wird nicht neugestartet!")
		Return $RetValue
	Else
		RunProg($MPAppDir & "\Mediaportal.exe")
		If @error = 0 Then
			$RetValue = 0
			SetMsg($RetValue, "", "MediaPortal erfolgreich gestartet!")
			Return $RetValue
		Else
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "MediaPortal konnte nicht gestartet werden!")
			Return $RetValue
		EndIf
	EndIf
EndFunc   ;==>MPRestart

Func CloseProg($Process) ; Beendet einen Process
	Local $Name = StringReplace($Process, ".exe", "", -1, 0)
	SetMsg(0, $Name & " beenden.", "")

	$PID = ProcessExists($Process)
	If $PID <> 0 Then
		ProcessClose($PID)
		For $t = 0 To 40 ; 4 sek bis Timeout
			If ProcessExists($PID) Then
				Sleep(100)
			Else
				$RetValue = 0
				SetMsg($RetValue, "", $Name & " wurde beendet!")
				Return $RetValue
			EndIf
		Next

		$RetValue = KillProg($Process)
		Return $RetValue
	Else
		$RetValue = 1
		SetMsg($RetValue, "", $Name & " ist nicht gestartet.")
		Return $RetValue
	EndIf
EndFunc   ;==>CloseProg


Func KillProg($Process) ;Killt einen Prozess (Forced)
	Local $Name = StringReplace($Process, ".exe", "", -1, 0)
	If ProcessExists($Process) Then
		$PID = ProcessExists($Process)
		Run(@ComSpec & " /c taskkill /F /PID " & $PID & " /T", @SystemDir, @SW_HIDE)

		For $t = 0 To 40 ; 4 sek bis Timeout
			If ProcessExists($PID) Then
				Sleep(100)
			Else
				$RetValue = 0
				GetErrors($RetValue)
				SetMsg($RetValue, "", $Name & " wurde beendet!")
				Return $RetValue
			EndIf
		Next

		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", $Name & " konnte NICHT beendet werden!")
	Else
		$RetValue = 0
		SetMsg($RetValue, "", $Name & " ist nicht gestartet.")
		Return $RetValue
	EndIf
EndFunc   ;==>KillProg


Func StartService($Service)
	SetMsg(0, $Service & " starten", "")
	If _Service_Exists($Service) Then
		_Service_Start($Service)
		For $t = 0 To 100 ; 10sek bis Timeout
			If _Service_Running($Service) Then
				$RetValue = 0
				SetMsg($RetValue, "", "Der " & $Service & "-Service wurde gestartet!")
				Return $RetValue
			EndIf
			Sleep(100)
		Next
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Der " & $Service & "-Service konnte nicht gestartet werden!")
		Return $RetValue
	Else
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Der " & $Service & "-Service wurde nicht gefunden!")
		Return $RetValue
	EndIf
EndFunc   ;==>StartService

Func StopService($Service)
	SetMsg(0, $Service & " stoppen", "")
	If _Service_Exists($Service) Then
		If _Service_Running($Service) Then _Service_Stop($Service)
		For $t = 0 To 100 ; 10sek bis Timeout
			If Not _Service_Running($Service) Then
				$RetValue = 0
				SetMsg($RetValue, "", "Der " & $Service & "-Service wurde gestoppt!")
				Return $RetValue
			EndIf
			Sleep(100)
		Next
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Der " & $Service & "-Service konnte nicht gestoppt werden!")
		Return $RetValue
	Else
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Der " & $Service & "-Service wurde nicht gefunden!")
		Return $RetValue
	EndIf
EndFunc   ;==>StopService
#EndRegion Prozess-/Programmaufgaben


Func GetErrors($RetValue)
	$ErrorValue += $RetValue
	Return $ErrorValue
EndFunc   ;==>GetErrors

Func ResetDevice()
	SetMsg(0, $DevName & " neu initialisieren", "")

	Local $out = ""
	$DevconExeDos = StringReplace($DevconExe, '\', '\"', 1)
	$CommandRestart = $DevconExeDos & '" restart ' & '"' & $DevID & '"'

	Local $PID = Run(@ComSpec & " /C " & $CommandRestart, "", @SW_HIDE, $STDOUT_CHILD)
	If @error <> 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Devcon.exe Runerror bei Initialisierung des Geräts: " & $DevName)
		Return $RetValue
	EndIf

	While 1
		Local $line = StdoutRead($PID)
		$out &= $line
		If @error Then ExitLoop
	WEnd

	If StringInStr($out, "device(s) restarted.") <> 0 Then
		$RetValue = 0
		SetMsg($RetValue, "", "Das Gerät: " & $DevName & " wurde neu initialisiert!")
		Return $RetValue
	Else
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Das Gerät: " & $DevName & " konnte nicht neu initialisiert werden!")
		Return $RetValue
	EndIf
EndFunc   ;==>ResetDevice

; This function convert a MAC Address Byte (e.g. "1f") to a char
Func HexToChar($strHex)
	Return Chr(Dec($strHex))
EndFunc   ;==>HexToChar

;Dateidatum abgleichen!
Func Datumsvergleich()
	SetMsg(0, "Datenbanken auf Aktualität prüfen", "")
	Local $hQuery, $Ausgabe1, $Ausgabe2, $Ausgabe3
	Local $RetValue, $RetValue1, $RetValue2, $RetValue3, $RetValue4, $RetValue5
	Local $MP = 0
	Local $TV = 0
	Local $Music = 0

	;--------------------------------------------------------------------------------------------------------------------------------------------
	;Neue Prüfmethode, nach Datenbankveränderung - Neuester Datenbankeintrag wird verglichen
	;--------------------------------------------------------------------------------------------------------------------------------------------
	If $SyncMP = 1 Then
		_SQLite_Startup()
		_SQLite_Open($MPdbSc)
		If @error = -1 Then SetMsg(1, "", "Auf Master Moving-Pictures Datenbank kann nicht zugegriffen werden")
		Local $MPdbScDate
		_SQLite_Query(-1, "SELECT date_added FROM movie_info ORDER BY date_added DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $MPdbScDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()

		_SQLite_Open($MPdbLc)
		Local $MPdbLcDate
		If @error = -1 Then SetMsg(1, "", "Auf lokale Moving-Pictures Datenbank kann nicht zugegriffen werden")
		_SQLite_Query(-1, "SELECT date_added FROM movie_info ORDER BY date_added DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $MPdbLcDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()
		_SQLite_Shutdown()

		$MPdbLcDate = StringTrimRight(StringReplace($MPdbLcDate[0], "-", "/"), 1)
		$MPdbScDate = StringTrimRight(StringReplace($MPdbScDate[0], "-", "/"), 1)

		SetMsg(0, "", "Moving-Pictues:          Lokales Datum:" & $MPdbLcDate & " <--> Server Datum:" & $MPdbScDate)

		If _DateDiff('s', $MPdbScDate, $MPdbLcDate) <> 0 Then $MP = 1
	EndIf

	If $SyncTV = 1 Then
		_SQLite_Startup()
		_SQLite_Open($TVdbSc)
		If @error = -1 Then SetMsg(1, "", "Auf Master TV-Series Datenbank kann nicht zugegriffen werden")
		Local $TVdbScDate
		_SQLite_Query(-1, "SELECT FileDateAdded FROM local_episodes ORDER BY FileDateAdded DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $TVdbScDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()

		_SQLite_Open($TVdbLc)
		Local $TVdbLcDate
		If @error = -1 Then SetMsg(1, "", "Auf lokale TV-Series Datenbank kann nicht zugegriffen werden")
		_SQLite_Query(-1, "SELECT FileDateAdded FROM local_episodes ORDER BY FileDateAdded DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $TVdbLcDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()
		_SQLite_Shutdown()

		$TVdbLcDate = StringReplace($TVdbLcDate[0], "-", "/")
		$TVdbScDate = StringReplace($TVdbScDate[0], "-", "/")

		SetMsg(0, "", "TV-Series:          Lokales Datum:" & $TVdbLcDate & " <--> Server Datum:" & $TVdbScDate)

		If _DateDiff('s', $TVdbScDate, $TVdbLcDate) <> 0 Then $TV = 1
	EndIf


	If $SyncMusic = 1 Then
		_SQLite_Startup()
		_SQLite_Open($MusicdbSc)
		If @error = -1 Then SetMsg(1, "", "Auf Master Musikdatenbank kann nicht zugegriffen werden")
		Local $MusicdbScDate
		_SQLite_Query(-1, "SELECT dateAdded FROM tracks ORDER BY dateAdded DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $MusicdbScDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()

		_SQLite_Open($MusicdbLc)
		Local $MusicdbLcDate
		If @error = -1 Then SetMsg(1, "", "Auf lokale Musikdatenbank kann nicht zugegriffen werden")
		_SQLite_Query(-1, "SELECT dateAdded FROM tracks ORDER BY dateAdded DESC LIMIT 1;", $hQuery)
		_SQLite_FetchData($hQuery, $MusicdbLcDate)
		_SQLite_QueryFinalize($hQuery)
		_SQLite_Close()
		_SQLite_Shutdown()

		$MusicdbLcDate = StringReplace($MusicdbLcDate[0], "-", "/")
		$MusicdbScDate = StringReplace($MusicdbScDate[0], "-", "/")

		SetMsg(0, "", "Musik:          Lokales Datum:" & $MusicdbLcDate & " <--> Server Datum:" & $MusicdbScDate)

		If _DateDiff('s', $MusicdbScDate, $MusicdbLcDate) <> 0 Then
			$Music = 1
			SetMsg(0, "", "Musikdatenbank wird aktualisiert ...")
		EndIf
	EndIf


	;Ergebnisse ausgeben
	$RetValue = 0
	If $MP = 1 Then $RetValue1 = SyncMP()
	If $TV = 1 Then $RetValue2 = SyncTV()
	If $Music = 1 Then $RetValue3 = SyncMusic()
	$RetValue4 = Sync("Other")
	If $MP + $TV + $Music > 1 And $ResMP <> 1 Then $RetValue5 = MPRestart()
	Return $RetValue + $RetValue1 + $RetValue2 + $RetValue3 + $RetValue4 + $RetValue5


EndFunc   ;==>Datumsvergleich

;Synchronisieren von Moving Pictures (Export;Delete;Import)!

Func SyncMP()
	SetMsg(0, "MovingPictures Datenbanken synchronisieren", "Öffnen der Datenbanken")

	Local $sOut, $MPVersionSc, $MPVersionLc, $abfrage

	_SQLite_Startup()

	;Lokale Datenbank öffnen
	_SQLite_Open($MPdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Lokale MovingPictures Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf

	;Benutzerdaten aus der Lokalen DB auslesen und als dump speichern.
	SetMsg(0, "", "Benutzerdaten werden aus Lokal-Datenbank ausgelesen")
	For $element In $TablesMp
		_SQLite_SQLiteExe($MPdbLc, ".output " & $element & ".dump" & @CRLF & ".dump " & $element, $sOut)
		If @error > 0 Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Benutzerdaten konnten nicht komplett ausgelesen werden. Problem:" & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()

	;MasterDatenbank überschreibt LokalDatenbank
	SetMsg(0, "", "Ersetze Lokal-Datenbank mit Master-Datenbank")
	If FileCopy($MPdbSc, $MPdbLc, 1) = 0 Then SetMsg(1, "", "Kopieren der Master-Datenbank nicht möglich!")
	_SQLite_Open($MPdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "MovingPictures Lokal-Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf
	;Benutzerdaten aus der lokalen DB löschen, User Settings nicht.
	SetMsg(0, "", "Benutzerdaten werden aus Datenbank gelöscht")
	For $element In $TablesMp
		_SQLite_SQLiteExe($MPdbLc, "delete from " & $element & ";", $sOut)
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Tabelle " & $element & @CRLF & "Tabelle evt. nicht vorhanden. Code:" & @error)
	Next

	;Benutzerdaten werden in die lokale DB reinschreiben.
	SetMsg(0, "", "Lokale-Datenbank wird aktualisiert")
	For $element In $TablesMp
		_SQLite_SQLiteExe($MPdbLc, ".read " & $element & ".dump " & @CRLF & ".dump", $sOut)
		If (@error > 0) Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Fehler beim schreiben in Lokale Datenbank bei " & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()
	_SQLite_Shutdown()

	;VersionsMeldung
	If Not $MPVersionSc = $MPVersionLc Then
		SetMsg(0, "", "Neuere Version auf Server gefunden, prüfen Sie ggf. die Table-Settings!")
		Sleep(1000)
	EndIf

	;Dateien Löschen
	SetMsg(0, "", "Temporäre Dateien werden gelöscht")
	For $element In $TablesMp
		FileDelete(@ScriptDir & "\" & $element & ".dump")
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Datei " & $element & ".dump" & @CRLF & "Bei Bedarf Datei bitte manuell löschen.")
	Next

	;Dateien Synchronisieren mit passendem Profiltyp
	Sync("MovingPictures")

EndFunc   ;==>SyncMP

;Synchroniseren von MP-TV-Series (Export;Delete;Import)!
Func SyncTV()
	SetMsg(0, "TV-Series Datenbanken synchronisieren", "Öffnen der Datenbanken")

	Local $sOut

	_SQLite_Startup()

	;Lokale Datenbank öffnen
	_SQLite_Open($TVdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Lokale TV-Series Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf

	;Benutzerdaten aus der Lokalen DB auslesen und als dump speichern.
	SetMsg(0, "", "Benutzerdaten werden aus Lokal-Datenbank ausgelesen")
	For $element In $TablesTv
		_SQLite_SQLiteExe($TVdbLc, ".output " & $element & ".dump" & @CRLF & ".dump " & $element, $sOut)
		If @error > 0 Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Benutzerdaten konnten nicht komplett ausgelesen werden. Problem:" & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()

	;MasterDatenbank überschreibt LokalDatenbank
	SetMsg(0, "", "Ersetze Lokal-Datenbank mit Master-Datenbank")
	FileCopy($TVdbSc, $TVdbLc, 1)

	_SQLite_Open($TVdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "TV-Series Lokal-Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf

	;Benutzerdaten aus der lokalen DB löschen, User Settings nicht.
	SetMsg(0, "", "Benutzerdaten werden aus Datenbank gelöscht")
	For $element In $TablesTv
		_SQLite_SQLiteExe($TVdbLc, "delete from " & $element & ";", $sOut)
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Tabelle " & $element & @CRLF & "Tabelle evt. nicht vorhanden. Kein Grund für Abbruch!")
	Next

	;Benutzerdaten werden in die lokale DB reinschreiben.
	SetMsg(0, "", "Lokale-Datenbank wird aktualisiert")
	For $element In $TablesTv
		_SQLite_SQLiteExe($TVdbLc, ".read " & $element & ".dump " & @CRLF & ".dump", $sOut)
		If (@error > 0) Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Fehler beim schreiben in Lokale Datenbank bei " & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()
	_SQLite_Shutdown()

	;Dateien Löschen
	SetMsg(0, "", "Temporäre Dateien werden gelöscht")
	For $element In $TablesTv
		FileDelete(@ScriptDir & "\" & $element & ".dump")
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Datei " & $element & ".dumb" & @CRLF & "Bei Bedarf Datei bitte manuell löschen.")
	Next

	;Dateien Synchronisieren mit passendem Profiltyp
	Sync("TVSeries")
EndFunc   ;==>SyncTV

Func SyncMusic()
	SetMsg(0, "Music Datenbanken synchronisieren", "Öffnen der Datenbanken")

	Local $sOut

	_SQLite_Startup()

	;Lokale Datenbank öffnen
	_SQLite_Open($MusicdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Lokale Music Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf

	;Benutzerdaten aus der Lokalen DB auslesen und als dump speichern.
	SetMsg(0, "", "Benutzerdaten werden aus Lokal-Datenbank ausgelesen")
	For $element In $TablesMusic
		_SQLite_SQLiteExe($MusicdbLc, ".output " & $element & ".dump" & @CRLF & ".dump " & $element, $sOut)
		If @error > 0 Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Benutzerdaten konnten nicht komplett ausgelesen werden. Problem:" & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()

	;MasterDatenbank überschreibt LokalDatenbank
	SetMsg(0, "", "Ersetze Lokal-Datenbank mit Master-Datenbank")
	FileCopy($MusicdbSc, $MusicdbLc, 1)

	_SQLite_Open($MusicdbLc)
	If @error > 0 Then
		$RetValue = 1
		GetErrors($RetValue)
		SetMsg($RetValue, "", "Music Lokal-Datenbank kann nicht geöffnet werden.")
		_SQLite_Close()
		Return $RetValue
	EndIf

	;Benutzerdaten aus der lokalen DB löschen, User Settings nicht.
	SetMsg(0, "", "Benutzerdaten werden aus Datenbank gelöscht")
	For $element In $TablesMusic
		_SQLite_SQLiteExe($MusicdbLc, "delete from " & $element & ";", $sOut)
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Tabelle " & $element & @CRLF & "Tabelle evt. nicht vorhanden. Kein Grund für Abbruch!")
	Next

	;Benutzerdaten werden in die lokale DB reinschreiben.
	SetMsg(0, "", "Lokale-Datenbank wird aktualisiert")
	For $element In $TablesMusic
		_SQLite_SQLiteExe($MusicdbLc, ".read " & $element & ".dump " & @CRLF & ".dump", $sOut)
		If (@error > 0) Then
			$RetValue = 1
			GetErrors($RetValue)
			SetMsg($RetValue, "", "Fehler beim schreiben in Lokale Datenbank bei " & $element)
			_SQLite_Close()
			Return $RetValue
		EndIf
	Next
	_SQLite_Close()
	_SQLite_Shutdown()

	;Dateien Löschen
	SetMsg(0, "", "Temporäre Dateien werden gelöscht")
	For $element In $TablesMusic
		FileDelete(@ScriptDir & "\" & $element & ".dump")
		If (@error > 0) Then SetMsg(1, "", "Fehler beim Löschen der Datei " & $element & ".dumb" & @CRLF & "Bei Bedarf Datei bitte manuell löschen.")
	Next

	;Dateien Synchronisieren mit passendem Profiltyp
	Sync("Music")

EndFunc   ;==>SyncMusic

;Dateisynchronisation wird vorgenommen
Func Sync($PluginProfile)
	Local $Items = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Count", "0")
	If $Items > 0 Then
		Local $Txt[$Items][3]
		For $i = 0 To $Items - 1
			$Selected = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i, "False")
			$ProfileType = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i & "4", "Other")
			If $Selected = "True" And $ProfileType = $PluginProfile Then
				For $j = 0 To UBound($Txt, 2) - 1
					$Txt[$i][$j] = IniRead(@ScriptDir & "\settings.ini", "Profiles", "Data" & $i & $j + 1, "")
				Next
				SetMsg(0, "Das Profil " & $Txt[$i][0] & " wird Synchronisiert!", "Warte...")
				If SyncFiles($Txt[$i][1], $Txt[$i][2], $verifyMethod) = 1 Then
					SetMsg(0, "", "Das Profil " & $Txt[$i][0] & " wurde erfolgreich synchronisiert!")
					Sleep(600)
				Else
					SetMsg(1, "", "Das Profil " & $Txt[$i][0] & " konnte nicht synchronisiert werden!")
					Sleep(1000)
				EndIf
			EndIf
		Next
	EndIf
EndFunc   ;==>Sync

Func CheckVersion()
	Local $VersionOnline, $VersionLocal, $DownAdr, $remote_size, $lokal_size, $Progress = 0, $Status, $Success = 0

	SetMsg(0, "Prüfe auf Neue MP-SyncClient Version", "Warte...")
	Select
		Case $Update = "No Update"
			Return
		Case $Update = "Check for SVN"
			$DownAdr = 'http://sync-mp.googlecode.com/svn/trunk/MP-SyncClient/'
		Case $Update = "Check for Stable"
			$DownAdr = 'http://sync-mp.googlecode.com/files/'
	EndSelect

	For $i = 20 To 0 Step -1
		$VersionOnline = BinaryToString(InetRead($DownAdr & 'ClientVersion.txt', 17))
		$VersionLocal = FileGetVersion(@ScriptFullPath)
		If $VersionOnline <> "" Then
			SetMsg(0, "", "Lokale Version:" & $VersionLocal & " <--> Version Online:" & $VersionOnline)
			$Success = 1
			ExitLoop
		EndIf
		Sleep(200)
	Next
	If $Success = 0 Then SetMsg(1, "", "Versionsnummer der Online-version kann nicht ermittelt werden!")
	$remote_size = InetGetSize($DownAdr & 'SyncClient.exe')
	If $VersionOnline > $VersionLocal Then
		SetMsg(0, "Prüfe auf Neue MP-SyncClient Version", "Neue Version verfügbar!")
		Sleep(300)
		$DownloadProg = InetGet($DownAdr & 'SyncClient.exe', @ScriptDir & '\SyncClient_new.exe', 17, 1)
		Do
			$lokal_size = InetGetInfo($DownloadProg, 0)
			$Progress = Round(($lokal_size / $remote_size) * 100, 2)
			$Status = InetGetInfo($DownloadProg, 4)
			SetMsg(0, "Lade neue MP-SyncClient Version", $Progress & " %  (" & $lokal_size & " of " & $remote_size & ")")
			Sleep(150)
		Until InetGetInfo($DownloadProg, 2)
		InetClose($DownloadProg)

		If $Status = 0 Then
			SetMsg(0, "", "Download erfolgreich!")
			Sleep(200)
			$RunUpdate = Run(@ScriptDir & "\Updater.exe -SyncClient")
			If $RunUpdate <> 0 Then
				Exit
			Else
				SetMsg(1, "Starte externen Updater", "Updater.exe konnte nicht gestartet werden!")
			EndIf
		Else
			SetMsg(1, "", "Downloadfehler!")
		EndIf

	Else
		SetMsg(0, "", "Keine neue Version verfügbar!")
	EndIf
EndFunc   ;==>CheckVersion

;Wandelt eine Zahl mit Datumsinformation im Format (YYYYMMDDHHMMSS) in (DD/MM/YYYY HH:MM)
Func DigitToTime($Digit)
	Local $Format
	$Format = StringMid($Digit, 7, 2) & "/" & StringMid($Digit, 5, 2) & "/" & StringMid($Digit, 1, 4) & " " & StringMid($Digit, 9, 2) & ":" & StringMid($Digit, 11, 2)
	Return $Format
EndFunc   ;==>DigitToTime

Func StartResTasks()
	Local $RetValue
	$ErrorValue = 0

	Abdunkeln()
	SuspendProcess("MediaPortal.exe")
	SetMsg(0, "Resume erkannt", "Prüfe Aufgabenliste...")

	If $ResTV = 1 Then
		Select
			Case $Kill = 1
				$RetValue = KillProg("TVService.exe")
			Case $Stop = 1
				$RetValue = StopService("TVService")
		EndSelect

		Select
			Case $ResDev <> 1 And $RetValue = 0
				StartService("TVService")

			Case $ResDev = 1 And $RetValue = 0
				ResetDevice()
				Sleep(1000)
				StartService("TVService")
		EndSelect
	EndIf

	If $ResDev = 1 And $ResTV <> 1 Then
		ResetDevice()
	EndIf

	If $ResProg = 1 Then
		RunProg($Other1Exe)
	EndIf

	$conn = WaitForConnection()
	Sleep(5000)
	If $conn = 1 Then
		If $Wol = 1 Then
			WOL($IP, $MACAddress)
			PingHost($IP, 20000)
		EndIf

		If ($SyncMP = 1 Or $SyncTV = 1) Or $SyncMusic = 1 Then
			Select
				Case StringLeft($TVdbSc, 2) = "\\"
					$Host = StringSplit($TVdbSc, "\")
				Case StringLeft($MPdbSc, 2) = "\\"
					$Host = StringSplit($MPdbSc, "\")
				Case StringLeft($MusicdbSc, 2) = "\\"
					$Host = StringSplit($MusicdbSc, "\")
				Case Else
					Dim $Host[4]
					$Host[3] = "127.0.0.1"
			EndSelect
			If PingHost($Host[3], 4000) = 1 Then ;Prüfen ob  Ping möglich -> Datumvergleich möglich!
				SetMsg(0, "Verbindung zu " & $Host[3] & " besteht", "Prüfe Dateidatum...")
				Sleep(500)
				Datumsvergleich()
			Else
				SetMsg(0, "Verbindung besteht NICHT!", "Dateiprüfung nicht möglich...")
				Sleep(500)
			EndIf

		EndIf

		CheckVersion()
	EndIf

	ResumeProcess("MediaPortal.exe")

	If $ResMP = 1 Then
		MPRestart()
	EndIf

	If $ErrorValue = 0 Then
		SetMsg($ErrorValue, "Alle Resume-Aufgaben erfolgreich abgeschlossen", "Warte bis auf nächstes Ereignis", 1)
	Else
		SetMsg($ErrorValue, "Resume-Aufgaben NICHT erfolgreich abgeschlossen", "Es sind " & $ErrorValue & " Fehler aufgetreten!", 1)
	EndIf
	Sleep(500)
	Aufhellen()

	Local $PID = ProcessWait("MediaPortal.exe", 10)
	If ProcessExists($PID) Then
		Local $title = WinGetTitle("MediaPortal")
		WinActivate($title)
	EndIf

EndFunc   ;==>StartResTasks

Func StartSusTasks()
	Local $RetValue
	$ErrorValue = 0

	Abdunkeln()
	SetMsg(0, "Suspend erkannt", "Prüfe Aufgabenliste...")

	If $SuspProg = 1 Then
		RunProg($Other2Exe)
	EndIf

	If $SuspMP = 1 Then
		CloseProg("Mediaportal.exe")
	EndIf

	If $SuspTV = 1 Then
		Select
			Case $Kill = 1
				KillProg("TvService.exe")
			Case $Stop = 1
				StopService("TvService")
		EndSelect
	EndIf

	If $ErrorValue = 0 Then SetMsg($ErrorValue, "Alle Suspend-Aufgaben erfolgreich abgeschlossen", "Gehe in Standby!", 1)
	If $ErrorValue <> 0 Then SetMsg($ErrorValue, "Suspend-Aufgaben NICHT erfolgreich abgeschlossen", "Es sind " & $ErrorValue & " Fehler aufgetreten!", 1)

	Aufhellen()
EndFunc   ;==>StartSusTasks

#EndRegion AllgemeineFunktionen




;-------------------------------
;--------Functionaufrufe--------
;-------------------------------


Read()
TCPStartup() ; TCP wird initialisiert
$mainsocket = TCPListen(@IPAddress1, $Port) ; Den mainsocket erstellen
If $mainsocket < 1 Then WriteLog(1, "TCP-Verbindung herstellen", "TCP-Verbindung herstellen", "Abhöranschluss konnte nicht geöffnet werden! Firewalleinstellungen prüfen! Errorcode:" & @error)

;Programm läuft dauerhaft im Hintergrund
;und prüft auf TCP-Verbindung mit Server ggf. Remote-Herunterfahren
While 1
	$acceptedSocket = TCPAccept($mainsocket) ; Wir versuchen eine mögliche Verbindung anzunehmen

	If $acceptedSocket <> -1 Then ; Wenn $acceptedSocket ungleich -1 ist, ...
		$received = TCPRecv($acceptedSocket, 1024) ; Socketverbindung hergestellt, empfange ein Paket vom Client (in $received)
		TCPCloseSocket($acceptedSocket)
		Select
			Case $received = "standby"
				Select
					Case $Suspendmode = "Standby (S3)"
						Shutdown(32)
					Case $Suspendmode = "Hibernate (S4)"
						Shutdown(64)
					Case $Suspendmode = "Shutdown (S5)"
						Shutdown(9)

				EndSelect
		EndSelect
	EndIf

	Sleep(100)
WEnd


;--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Region SyncTool
;--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
;~ Coded by Ian Maxwell (llewxam)
;~ Autoit 3.3.6.1
;~ Coded with many ideas and some code contributions by many people in the forum, thanks to all contributors and people who give their time answering questions!!!
;~ Also, sorry if some variables and the $stats array seem odd, it has been said before (rightly) that I could improve upon that!!  :D   Questions, just ask!





Func SyncFiles($Source, $target, $verifyMethod)
	If $Splash = 1 Then
		Global $ProgressBar = GUICtrlCreateProgress(@DesktopWidth / 4, @DesktopHeight / 2 + 50, @DesktopWidth / 2, @DesktopHeight / 15)
	EndIf

	;Sammle Dateien Msg Ausgeben
	AdlibRegister("_SpeedCalc")
	;GUICtrlSetState($marqueeBanner, $GUI_SHOW)
	$result = _FileListToArrayXT($Source, Default, 1, 2, True)
	AdlibUnRegister("_SpeedCalc")
	$stats[7] = $totalSize

	$put = $target

;~      get to work!
	AdlibRegister("_SpeedCalc")

	$started = True
	$time = TimerInit()
	For $a = 1 To $result[0] Step 2
		$copySource = $result[$a]
		$subdir = StringTrimLeft($copySource, StringLen($Source))
		$Destination = $put & $subdir
		$lastDir = StringMid($Destination, 1, StringInStr($Destination, "\", 2, -1) - 1)
		If Not FileExists($lastDir) Then DirCreate($lastDir)
		$copySize = $result[$a + 1]
		_MarqueeScroll()
		_copy($copySource, $copySize, $Destination)
	Next
;~      done... all this code, and all for THIS!!  :)
	AdlibUnRegister("_SpeedCalc")
	$started = False

	$synced = _StringAddThousandsSep($syncedFiles)
	$skipped = _StringAddThousandsSep($skippedFiles)
	$failed = _StringAddThousandsSep(UBound($failedFiles) - 1)


	If UBound($failedFiles) > 1 Then
		_ArrayDelete($failedFiles, 0)
		_ArrayDisplay($failedFiles, "Failed Items")
		Return 0
	EndIf



	If $Splash = 1 Then
		GUICtrlDelete($ProgressBar)
	EndIf

	Return 1

EndFunc   ;==>SyncFiles

Func _copy($copySource, $copySize, $copyDestination)
	$sync = False

	$syncedFilesize += $copySize

	If $verifyMethod == "Exist & Size" Then
		If Not FileExists($copyDestination) Or FileGetSize($copyDestination) <> $copySize Then $sync = True
	ElseIf $verifyMethod == "Exist" Then
		If Not FileExists($copyDestination) Then $sync = True
	ElseIf $verifyMethod == "Size" Then
		If FileGetSize($copyDestination) <> $copySize Then $sync = True
	ElseIf $verifyMethod == "MD5 (slow)" Then
		$sourceHash = _Crypt_HashFile($copySource, $CALG_MD5)
		If _Crypt_HashFile($copyDestination, $CALG_MD5) <> $sourceHash Then $sync = True
	EndIf

	If $sync == True Then
		$PID = Run(@ComSpec & " /c copy /y " & Chr(34) & $copySource & Chr(34) & " " & Chr(34) & $copyDestination & Chr(34), @ScriptDir, @SW_HIDE)
		$stats[1] = 0
		$stats[2] = 0
		Do
			$array = ProcessGetStats($PID, 1)
			If IsArray($array) Then
				$stats[1] = $array[4] - $stats[2]
				If $stats[1] > 0 Then $stats[3] += $stats[1]
				$stats[2] = $array[4]
				Sleep(75)
			EndIf
		Until Not ProcessExists($PID)

		If $verifyMethod == "Exist & Size" Then
			If Not FileExists($copyDestination) Then
				$attrib = FileGetAttrib($copySource)
				If StringInStr($attrib, "A") Then FileSetAttrib($copySource, "-A")
				If StringInStr($attrib, "H") Then FileSetAttrib($copySource, "-H")
				If StringInStr($attrib, "R") Then FileSetAttrib($copySource, "-R")
				If StringInStr($attrib, "S") Then FileSetAttrib($copySource, "-S")
				$PID = Run(@ComSpec & " /c copy /y " & Chr(34) & $copySource & Chr(34) & " " & Chr(34) & $copyDestination & Chr(34), @ScriptDir, @SW_HIDE)
				$stats[1] = 0
				$stats[2] = 0
				Do
					$array = ProcessGetStats($PID, 1)
					If IsArray($array) Then
						$stats[1] = $array[4] - $stats[2]
						If $stats[1] > 0 Then $stats[3] += $stats[1]
						$stats[2] = $array[4]
						Sleep(75)
					EndIf
				Until Not ProcessExists($PID)
				If Not FileExists($copyDestination) Then _ArrayAdd($failedFiles, $copySource)
			Else
				$syncedFiles += 1
			EndIf
		EndIf

		If $verifyMethod == "Exist" Then
			If Not FileExists($copyDestination) Then
				$attrib = FileGetAttrib($copySource)
				If StringInStr($attrib, "A") Then FileSetAttrib($copySource, "-A")
				If StringInStr($attrib, "H") Then FileSetAttrib($copySource, "-H")
				If StringInStr($attrib, "R") Then FileSetAttrib($copySource, "-R")
				If StringInStr($attrib, "S") Then FileSetAttrib($copySource, "-S")
				$PID = Run(@ComSpec & " /c copy /y " & Chr(34) & $copySource & Chr(34) & " " & Chr(34) & $copyDestination & Chr(34), @ScriptDir, @SW_HIDE)
				$stats[1] = 0
				$stats[2] = 0
				Do
					$array = ProcessGetStats($PID, 1)
					If IsArray($array) Then
						$stats[1] = $array[4] - $stats[2]
						If $stats[1] > 0 Then $stats[3] += $stats[1]
						$stats[2] = $array[4]
						Sleep(75)
					EndIf
				Until Not ProcessExists($PID)
				If Not FileExists($copyDestination) Then _ArrayAdd($failedFiles, $copySource)
			Else
				$syncedFiles += 1
			EndIf
		EndIf

		If $verifyMethod == "Size" Then
			If FileGetSize($copyDestination) <> $copySize Then
				$attrib = FileGetAttrib($copySource)
				If StringInStr($attrib, "A") Then FileSetAttrib($copySource, "-A")
				If StringInStr($attrib, "H") Then FileSetAttrib($copySource, "-H")
				If StringInStr($attrib, "R") Then FileSetAttrib($copySource, "-R")
				If StringInStr($attrib, "S") Then FileSetAttrib($copySource, "-S")
				$PID = Run(@ComSpec & " /c copy /y " & Chr(34) & $copySource & Chr(34) & " " & Chr(34) & $copyDestination & Chr(34), @ScriptDir, @SW_HIDE)
				$stats[1] = 0
				$stats[2] = 0
				Do
					$array = ProcessGetStats($PID, 1)
					If IsArray($array) Then
						$stats[1] = $array[4] - $stats[2]
						If $stats[1] > 0 Then $stats[3] += $stats[1]
						$stats[2] = $array[4]
						Sleep(75)
					EndIf
				Until Not ProcessExists($PID)
				If FileGetSize($copyDestination) <> $copySize Then _ArrayAdd($failedFiles, $copySource)
			Else
				$syncedFiles += 1
			EndIf
		EndIf
		If $verifyMethod == "MD5 (slow)" Then
			If _Crypt_HashFile($copyDestination, $CALG_MD5) <> $sourceHash Then
				$attrib = FileGetAttrib($copySource)
				If StringInStr($attrib, "A") Then FileSetAttrib($copySource, "-A")
				If StringInStr($attrib, "H") Then FileSetAttrib($copySource, "-H")
				If StringInStr($attrib, "R") Then FileSetAttrib($copySource, "-R")
				If StringInStr($attrib, "S") Then FileSetAttrib($copySource, "-S")
				$PID = Run(@ComSpec & " /c copy /y " & Chr(34) & $copySource & Chr(34) & " " & Chr(34) & $copyDestination & Chr(34), @ScriptDir, @SW_HIDE)
				$stats[1] = 0
				$stats[2] = 0
				Do
					$array = ProcessGetStats($PID, 1)
					If IsArray($array) Then
						$stats[1] = $array[4] - $stats[2]
						If $stats[1] > 0 Then $stats[3] += $stats[1]
						$stats[2] = $array[4]
						Sleep(75)
					EndIf
				Until Not ProcessExists($PID)
				If _Crypt_HashFile($copyDestination, $CALG_MD5) <> $sourceHash Then _ArrayAdd($failedFiles, $copySource)
			Else
				$syncedFiles += 1
			EndIf
		EndIf
	EndIf

	If $sync == False Then $skippedFiles += 1
	If $deleteAfterSync == True Then FileDelete($copySource)

	$stats[4] += $copySize
	$stats[3] = $stats[4]
	$fileCount -= 1
	$stats[7] -= $copySize
	Return
EndFunc   ;==>_copy


Func _FileListToArrayXT($sPath = @ScriptDir, $sFilter = "*", $iRetItemType = 0, $iRetPathType = 0, $bRecursive = False, $sExclude = "", $iRetFormat = 1)
	Local $hSearchFile, $sFile, $sFileList, $sWorkPath, $sRetPath, $iRootPathLen, $iPCount, $iFCount, $fDirFlag
	If $sPath = -1 Or $sPath = Default Then $sPath = @ScriptDir
	$sPath = StringRegExpReplace(StringRegExpReplace($sPath, "(\s*;\s*)+", ";"), "\A;|;\z", "")
	If $sPath = "" Then Return SetError(1, 1, "")
	If $sFilter = -1 Or $sFilter = Default Then $sFilter = "*"
	$sFilter = StringRegExpReplace(StringRegExpReplace($sFilter, "(\s*;\s*)+", ";"), "\A;|;\z", "")
	If StringRegExp($sFilter, "[\\/><:\|]|(?s)\A\s*\z") Then Return SetError(2, 2, "")
	If $bRecursive Then
		$sFilter = StringRegExpReplace($sFilter, '([\Q\.+[^]$(){}=!\E])', '\\$1')
		$sFilter = StringReplace($sFilter, "?", ".")
		$sFilter = StringReplace($sFilter, "*", ".*?")
		$sFilter = "(?i)\A(" & StringReplace($sFilter, ";", "$|") & "$)" ;case-insensitive, convert ';' to '|', match from first char, terminate strings
	EndIf
	If $iRetItemType <> "1" And $iRetItemType <> "2" Then $iRetItemType = "0"
	If $iRetPathType <> "1" And $iRetPathType <> "2" Then $iRetPathType = "0"
	$bRecursive = ($bRecursive = "1")
	If $sExclude = -1 Or $sExclude = Default Then $sExclude = ""
	If $sExclude Then
		$sExclude = StringRegExpReplace(StringRegExpReplace($sExclude, "(\s*;\s*)+", ";"), "\A;|;\z", "")
		$sExclude = StringRegExpReplace($sExclude, '([\Q\.+[^]$(){}=!\E])', '\\$1')
		$sExclude = StringReplace($sExclude, "?", ".")
		$sExclude = StringReplace($sExclude, "*", ".*?")
		$sExclude = "(?i)\A(" & StringReplace($sExclude, ";", "$|") & "$)" ;case-insensitive, convert ';' to '|', match from first char, terminate strings
	EndIf
	If Not ($iRetItemType = 0 Or $iRetItemType = 1 Or $iRetItemType = 2) Then Return SetError(3, 3, "")
	Local $aPath = StringSplit($sPath, ';', 1) ;paths array
	Local $aFilter = StringSplit($sFilter, ';', 1) ;filters array
	For $iPCount = 1 To $aPath[0] ;Path loop
		$sPath = StringRegExpReplace($aPath[$iPCount], "[\\/]+\z", "") & "\" ;ensure exact one trailing slash
		If Not FileExists($sPath) Then ContinueLoop
		$iRootPathLen = StringLen($sPath) - 1
		Local $aPathStack[1024] = [1, $sPath]
		While $aPathStack[0] > 0
			$sWorkPath = $aPathStack[$aPathStack[0]]
			$aPathStack[0] -= 1
			$hSearchFile = FileFindFirstFile($sWorkPath & '*')
			If @error Then
				FileClose($hSearchFile)
				ContinueLoop
			EndIf
			$sRetPath = $sWorkPath
			While True ;Files only
				$sFile = FileFindNextFile($hSearchFile)
				If @error Then
					FileClose($hSearchFile)
					ExitLoop
				EndIf
				If @extended Then
					$aPathStack[0] += 1
					If UBound($aPathStack) <= $aPathStack[0] Then ReDim $aPathStack[UBound($aPathStack) * 2]
					$aPathStack[$aPathStack[0]] = $sWorkPath & $sFile & "\"
					ContinueLoop
				EndIf
				If StringRegExp($sFile, $sFilter) Then
					$size = FileGetSize($sRetPath & $sFile)
					$fileCount += 1
					$totalSize += $size
					$sFileList &= $sRetPath & $sFile & "|" & $size & "|"
				EndIf
			WEnd
		WEnd
		FileClose($hSearchFile)
	Next ;$iPCount - next path
	If $sFileList Then
		Switch $iRetFormat
			Case 2 ;return a delimited string
				Return StringTrimRight($sFileList, 1)
			Case 0 ;return a 0-based array
				Return StringSplit(StringTrimRight($sFileList, 1), "|", 2)
			Case Else ;return a 1-based array
				Return StringSplit(StringTrimRight($sFileList, 1), "|", 1)
		EndSwitch
	Else
		Return SetError(4, 4, "")
	EndIf

EndFunc   ;==>_FileListToArrayXT


Func _MarqueeScroll()
	$marqueeProgress = $syncedFilesize / $totalSize * 100

	If $Splash = 1 Then GUICtrlSetData($ProgressBar, $marqueeProgress)

EndFunc   ;==>_MarqueeScroll


Func _SpeedCalc()

	If $marqueeScroll == True Then
		;GUICtrlSetData($showFileSize, _ByteSuffix($totalSize))
		If $fileCount > 1 Then
			;GUICtrlSetData($showFileCount, _StringAddThousandsSep($fileCount) & " Files")
		Else
			;GUICtrlSetData($showFileCount, _StringAddThousandsSep($fileCount) & " File")
		EndIf
		;GUICtrlSetData($sourceLabel, "Enumerating files, please wait")
	EndIf

	If $started == True Then

		$stats[6] = ($stats[3] - $stats[5]) * 4
		$stats[5] = $stats[3]
		;GUICtrlSetData($fileName, $copySource)
		;GUICtrlSetData($fileSize, "(" & _ByteSuffix($copySize) & ")")
		;GUICtrlSetData($fileProg, ($stats[2] / $copySize) * 100)
		;GUICtrlSetData($totalProg, ($stats[3] / $totalSize) * 100)
		If $fileCount > 1 Then
			;GUICtrlSetData($showFileCount, _StringAddThousandsSep($fileCount) & " Files")
		Else
			;GUICtrlSetData($showFileCount, _StringAddThousandsSep($fileCount) & " File")
		EndIf
		;GUICtrlSetData($showFileSize, _ByteSuffix($totalSize - (($stats[3] / $totalSize)) * $totalSize))
		;GUICtrlSetData($showSynced, _StringAddThousandsSep($syncedFiles) & " Synced")
		;GUICtrlSetData($showSkipped, _StringAddThousandsSep($skippedFiles) & " Skipped")
		;GUICtrlSetData($showFailed, _StringAddThousandsSep(UBound($failedFiles) - 1) & " Failed")
		;GUICtrlSetData($showSpeed, _ByteSuffix($stats[6]) & "/s")

		$elapsedSeconds = Int(TimerDiff($time) / 1000)
		$elapsedMinutes = 0
		$elapsedHours = 0
		Do
			If $elapsedSeconds >= 60 Then
				$elapsedSeconds -= 60
				$elapsedMinutes += 1
			EndIf
		Until $elapsedSeconds < 60
		Do
			If $elapsedMinutes >= 60 Then
				$elapsedMinutes -= 60
				$elapsedHours += 1
			EndIf
		Until $elapsedMinutes < 60
		If StringLen($elapsedSeconds) == 1 Then $elapsedSeconds = "0" & $elapsedSeconds
		If StringLen($elapsedMinutes) == 1 Then $elapsedMinutes = "0" & $elapsedMinutes
		If StringLen($elapsedHours) == 1 Then $elapsedHours = "0" & $elapsedHours
		GUICtrlSetData($showElapsedTime, $elapsedHours & ":" & $elapsedMinutes & ":" & $elapsedSeconds)


	EndIf
EndFunc   ;==>_SpeedCalc


Func _ByteSuffix($bytes)
	Local $x, $bytes_suffix[6] = [" B", " KB", " MB", " GB", " TB", " PB"]
	While $bytes > 1023
		$x += 1
		$bytes /= 1024
	WEnd
	Return StringFormat('%.2f', $bytes) & $bytes_suffix[$x]
EndFunc   ;==>_ByteSuffix


Func _StringAddThousandsSep($sText)
	If Not StringIsInt($sText) And Not StringIsFloat($sText) Then Return SetError(1)
	Local $aSplit = StringSplit($sText, "-" & $sDecimal)
	Local $iInt = 1, $iMod
	If Not $aSplit[1] Then
		$aSplit[1] = "-"
		$iInt = 2
	EndIf
	If $aSplit[0] > $iInt Then
		$aSplit[$aSplit[0]] = "." & $aSplit[$aSplit[0]]
	EndIf
	$iMod = Mod(StringLen($aSplit[$iInt]), 3)
	If Not $iMod Then $iMod = 3
	$aSplit[$iInt] = StringRegExpReplace($aSplit[$iInt], '(?<=\d{' & $iMod & '})(\d{3})', $sThousands & '\1')
	For $i = 2 To $aSplit[0]
		$aSplit[1] &= $aSplit[$i]
	Next
	Return $aSplit[1]
EndFunc   ;==>_StringAddThousandsSep

;--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#EndRegion SyncTool
;--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------