Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "WinMessages.nsh"
Name "Metro Last Light Redux next-gen magyarítás"
OutFile "MetroLastLightRedux_NextGen_HU.exe"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
!define MUI_ICON "metro.ico"
ShowInstDetails nevershow
; A verziómezőket a build.ps1 tölti ki a VERSION alapján.
VIProductVersion "0.0.0.0"
VIAddVersionKey /LANG=1038 "ProductName" "Metro Last Light Redux next-gen magyarítás"
VIAddVersionKey /LANG=1038 "FileVersion" "0.0.0"
VIAddVersionKey /LANG=1038 "ProductVersion" "0.0.0"
VIAddVersionKey /LANG=1038 "FileDescription" "Magyarítás és reklámpanel kezelése"
VIAddVersionKey /LANG=1038 "LegalCopyright" "Eredeti magyarítás: Lostprophet. Next-gen kiegészítő fordítás és telepítő: Harciropi."
Var State
Var Operation
Var SelectedOperation
Var SelectedComponents
Var ReportedComponents
Var ReportedVersion
Var ActionButton
Var ErrorText
Var FinishText
Var HuCheckbox
Var AdsCheckbox
Var HuChoice
Var AdsChoice
Var RemoveButton
Var RemoveMode
Var SummaryLabel
Var HelpLabel
Var LastFolder
Var SavedHuChoice
Var SavedAdsChoice
Var FinishTitle
!define MUI_ABORTWARNING
!define MUI_WELCOMEFINISHPAGE_BITMAP "intaller_image.bmp"
!define MUI_WELCOMEPAGE_TITLE "Metro Last Light Redux next-gen magyarítás"
!define MUI_WELCOMEPAGE_TEXT "Magyar feliratok és menük a Metro Last Light Redux Steam next-gen kiadásához.$\r$\n$\r$\nTelepítéshez, az összetevők módosításához és eltávolításhoz is ezt az EXE-t használd. A játékot előtte zárd be.$\r$\n$\r$\nEredeti magyarítás: Lostprophet.$\r$\n$\r$\nAz eredeti magyarítás óta megjelent új szövegek fordítását és az új telepítőt Harciropi készítette.$\r$\n$\r$\nNem hivatalos, közösségi magyarítás."
!insertmacro MUI_PAGE_WELCOME
!define MUI_DIRECTORYPAGE_TEXT_TOP "Válaszd ki a Metro Last Light Redux játék mappáját. A telepítő megállapítja, hogy telepítésre, frissítésre vagy eltávolításra van szükség."
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DirectoryLeave
!insertmacro MUI_PAGE_DIRECTORY
Page custom ComponentsShow ComponentsLeave
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ProgressShow
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$FinishTitle"
!define MUI_FINISHPAGE_TEXT "$FinishText"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "Hungarian"
Function RunBackend
 SetDetailsPrint none
 Delete "$PLUGINSDIR\result.ini"
 nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Kezeles.ps1" -Mode $Operation -Components "$SelectedComponents" -GameDir "$INSTDIR" -PayloadDir "$PLUGINSDIR\payload" -ReportPath "$PLUGINSDIR\result.ini"'
 Pop $0
 Pop $1
 ReadINIStr $State "$PLUGINSDIR\result.ini" "Result" "State"
 ReadINIStr $ReportedComponents "$PLUGINSDIR\result.ini" "Result" "InstalledComponents"
 ReadINIStr $ReportedVersion "$PLUGINSDIR\result.ini" "Result" "InstalledVersion"
 ${If} $ReportedComponents == ""
  StrCpy $ReportedComponents "None"
 ${EndIf}
 ${If} $State == ""
  StrCpy $State "OPERATION_FAILED"
 ${EndIf}
FunctionEnd
Function .onInit
 InitPluginsDir
 SetOutPath "$PLUGINSDIR"
 File "Kezeles.ps1"
 SetOutPath "$PLUGINSDIR\payload"
 File /r "payload\*.*"
 StrCpy $INSTDIR ""
 StrCpy $LastFolder ""
 StrCpy $SelectedComponents "None"
 StrCpy $Operation "Detect"
 Call RunBackend
 ReadINIStr $0 "$PLUGINSDIR\result.ini" "Result" "GameDir"
 ${If} $0 != ""
  StrCpy $INSTDIR $0
 ${Else}
  StrCpy $INSTDIR "$PROGRAMFILES32\Steam\steamapps\common\Metro Last Light Redux"
 ${EndIf}
FunctionEnd
Function ErrorMessage
 StrCpy $ErrorText "A művelet nem fejezhető be. Nem történt sikeres telepítés. A visszaállítási mentést őrizd meg."
 ${If} $State == "NOT_GAME"
  StrCpy $ErrorText "Ebben a mappában nem található a játék. Válaszd ki a metro.exe fájlt tartalmazó mappát."
 ${ElseIf} $State == "NOT_STEAM"
  StrCpy $ErrorText "A kiválasztott mappához nem található a Last Light Redux Steam-telepítése. Ellenőrizd a mappát."
 ${ElseIf} $State == "WRONG_VERSION"
  StrCpy $ErrorText "Ehhez a magyarításhoz a Metro Last Light Redux Steam next-gen kiadása szükséges."
 ${ElseIf} $State == "GAME_RUNNING"
  StrCpy $ErrorText "A folytatás előtt zárd be a játékot."
 ${ElseIf} $State == "BAD_PACKAGE"
  StrCpy $ErrorText "A telepítő csomagja sérült vagy hiányos. Kérj új példányt."
 ${ElseIf} $State == "BACKUP_CONFLICT"
  StrCpy $ErrorText "A visszaállítási mentés hiányzik vagy sérült. A telepítő nem írja felül."
 ${ElseIf} $State == "FILE_CONFLICT"
  StrCpy $ErrorText "Eltérő vagy más program által módosított célfájlt találtam. A telepítő nem írja felül őket."
 ${ElseIf} $State == "NEWER_INSTALLED"
  StrCpy $ErrorText "A magyarításból már újabb verzió van telepítve. Használd annak a telepítőjét."
 ${ElseIf} $State == "VERSION_CONFLICT"
  StrCpy $ErrorText "Azonos verziószámú, de eltérő csomag van telepítve. Használd a korábban telepített csomagot az eltávolításhoz."
 ${ElseIf} $State == "RECOVERY_NEEDED"
  StrCpy $ErrorText "Egy korábbi művelet félbeszakadt. A visszaállítási mentést őrizd meg, és kérj segítséget a helyreállításhoz."
 ${ElseIf} $State == "OPERATION_BUSY"
  StrCpy $ErrorText "Egy másik telepítési művelet már folyamatban van."
 ${ElseIf} $State == "UNSUPPORTED_LAYOUT"
  StrCpy $ErrorText "A játék fájlszerkezete eltér a támogatott next-gen szerkezettől. Frissített magyarítás szükséges."
 ${ElseIf} $State == "BANNER_UNSUPPORTED"
  StrCpy $ErrorText "A reklámpanel elrejtése ezzel a PROS-verzióval nem támogatott. Kapcsold ki ezt az opciót. A magyarítás külön telepíthető."
 ${ElseIf} $State == "BANNER_LAYOUT"
  StrCpy $ErrorText "A reklámpanel vezérlése eltér a támogatott változattól. A telepítő nem módosítja találomra."
 ${ElseIf} $State == "NO_COMPONENTS"
  StrCpy $ErrorText "Válassz legalább egy összetevőt."
 ${ElseIf} $State == "BAD_COMPONENTS"
  StrCpy $ErrorText "Az összetevők kiválasztása érvénytelen. Indítsd újra a telepítőt."
 ${ElseIf} $State == "CLEANUP_FAILED"
  StrCpy $ErrorText "Az eredeti játékfájlok visszaálltak, de a telepítő mentéseinek törlése nem sikerült. Ellenőrizd, hogy más program nem használja-e őket."
 ${EndIf}
FunctionEnd
Function DirectoryLeave
 StrCpy $Operation "Detect"
 StrCpy $SelectedComponents "None"
 Call RunBackend
 ${If} $State == "READY_INSTALL"
 ${OrIf} $State == "READY_UPGRADE"
 ${OrIf} $State == "READY_REBASE"
 ${OrIf} $State == "READY_REMOVE"
  Return
 ${EndIf}
 Call ErrorMessage
 MessageBox MB_OK|MB_ICONEXCLAMATION "$ErrorText"
 Abort
FunctionEnd
Function ComponentsShow
 !insertmacro MUI_HEADER_TEXT "Összetevők kiválasztása" "Válaszd ki, mit szeretnél használni."
 ${If} $LastFolder != $INSTDIR
  StrCpy $LastFolder $INSTDIR
  StrCpy $RemoveMode 0
  StrCpy $HuChoice ${BST_CHECKED}
  StrCpy $AdsChoice ${BST_UNCHECKED}
  ${If} $ReportedComponents != "None"
   StrCpy $HuChoice ${BST_UNCHECKED}
   ${If} $ReportedComponents == "Translation"
   ${OrIf} $ReportedComponents == "Translation,HideAds"
    StrCpy $HuChoice ${BST_CHECKED}
   ${EndIf}
   ${If} $ReportedComponents == "HideAds"
   ${OrIf} $ReportedComponents == "Translation,HideAds"
    StrCpy $AdsChoice ${BST_CHECKED}
   ${EndIf}
  ${EndIf}
 ${EndIf}
 nsDialogs::Create 1018
 Pop $0
 ${If} $0 == error
  Abort
 ${EndIf}
 ${NSD_CreateLabel} 0 0u 100% 8u "Kiválasztott játékmappa:"
 Pop $0
 ${NSD_CreateLabel} 0 13u 100% 14u "$INSTDIR"
 Pop $0
 ${NSD_CreateLabel} 0 32u 100% 8u "A két összetevő egymástól függetlenül telepíthető."
 Pop $0
 ${NSD_CreateCheckbox} 0 45u 100% 10u "Magyarítás telepítése"
 Pop $HuCheckbox
 ${NSD_SetState} $HuCheckbox $HuChoice
 ${NSD_OnClick} $HuCheckbox ComponentsChanged
 ${NSD_CreateCheckbox} 0 60u 100% 10u "Főmenü reklámpanel elrejtése"
 Pop $AdsCheckbox
 ${NSD_SetState} $AdsCheckbox $AdsChoice
 ${NSD_OnClick} $AdsCheckbox ComponentsChanged
 ${NSD_CreateLabel} 0 75u 100% 25u ""
 Pop $HelpLabel
 ${NSD_CreateLabel} 0 105u 100% 16u ""
 Pop $SummaryLabel
 StrCpy $RemoveButton 0
 ${If} $ReportedComponents != "None"
  ${NSD_CreateButton} 0 126u 205u 12u "Minden telepített összetevő eltávolítása"
  Pop $RemoveButton
  ${NSD_OnClick} $RemoveButton ToggleRemoval
 ${EndIf}
 Call UpdateActions
 nsDialogs::Show
FunctionEnd
Function ComponentsChanged
 Pop $0
 Call UpdateActions
FunctionEnd
Function ToggleRemoval
 Pop $0
 ${If} $RemoveMode == 1
  StrCpy $RemoveMode 0
  ${NSD_SetState} $HuCheckbox $SavedHuChoice
  ${NSD_SetState} $AdsCheckbox $SavedAdsChoice
 ${Else}
  ${NSD_GetState} $HuCheckbox $SavedHuChoice
  ${NSD_GetState} $AdsCheckbox $SavedAdsChoice
  StrCpy $RemoveMode 1
  ${NSD_SetState} $HuCheckbox ${BST_UNCHECKED}
  ${NSD_SetState} $AdsCheckbox ${BST_UNCHECKED}
 ${EndIf}
 Call UpdateActions
FunctionEnd
Function UpdateActions
 ${NSD_GetState} $HuCheckbox $HuChoice
 ${NSD_GetState} $AdsCheckbox $AdsChoice
 StrCpy $SelectedComponents ""
 ${If} $HuChoice == ${BST_CHECKED}
  StrCpy $SelectedComponents "Translation"
 ${EndIf}
 ${If} $AdsChoice == ${BST_CHECKED}
  ${If} $SelectedComponents == ""
   StrCpy $SelectedComponents "HideAds"
  ${Else}
   StrCpy $SelectedComponents "$SelectedComponents,HideAds"
  ${EndIf}
 ${EndIf}
 ${If} $SelectedComponents == ""
  StrCpy $SelectedComponents "None"
 ${EndIf}
 GetDlgItem $0 $HWNDPARENT 1
 EnableWindow $0 1
 EnableWindow $HuCheckbox 1
 EnableWindow $AdsCheckbox 1
 ${If} $RemoveMode == 1
  EnableWindow $HuCheckbox 0
  EnableWindow $AdsCheckbox 0
  StrCpy $Operation "Remove"
  StrCpy $SelectedComponents "None"
  StrCpy $ActionButton "Eltávolítás"
  ${NSD_SetText} $HelpLabel "A telepített összetevők eltávolításával visszaállnak a mentett eredeti fájlok."
  ${NSD_SetText} $SummaryLabel "A játékmentéseid és beállításaid megmaradnak."
  ${NSD_SetText} $RemoveButton "Mégsem távolítok el mindent"
 ${Else}
  StrCpy $Operation "Apply"
  ${If} $RemoveButton != 0
   ${NSD_SetText} $RemoveButton "Minden telepített összetevő eltávolítása"
  ${EndIf}
  ${If} $ReportedComponents == "None"
   ${NSD_SetText} $HelpLabel "Magyarításhoz a játékban az ANGOL feliratnyelvet válaszd. A panel elrejtése önmagában is használható."
   StrCpy $ActionButton "Telepítés"
  ${Else}
   ${NSD_SetText} $HelpLabel "A bejelölt összetevők maradnak telepítve. A kikapcsolt összetevőket a telepítő visszaállítja."
   StrCpy $ActionButton "Alkalmazás"
   ${If} $State == "READY_UPGRADE"
    StrCpy $ActionButton "Frissítés"
   ${ElseIf} $State == "READY_REBASE"
    StrCpy $ActionButton "Újratelepítés"
   ${EndIf}
  ${EndIf}
  ${If} $SelectedComponents == "None"
   ${NSD_SetText} $SummaryLabel "Válassz legalább egy összetevőt, vagy használd az eltávolítás gombját."
   EnableWindow $0 0
  ${ElseIf} $State == "READY_REMOVE"
  ${AndIf} $SelectedComponents == $ReportedComponents
   ${NSD_SetText} $SummaryLabel "A kiválasztott összetevők már naprakészek. Változtass a kijelölésen, vagy válaszd az eltávolítást."
   EnableWindow $0 0
  ${Else}
   ${NSD_SetText} $SummaryLabel "A folytatáskor a kiválasztott összetevőket állítjuk be. Az eredeti fájlokról ellenőrzött mentés marad."
  ${EndIf}
 ${EndIf}
 ${If} $RemoveMode != 1
  ${NSD_GetText} $HelpLabel $1
  ${NSD_SetText} $HelpLabel "$1 A reklámpanel elrejtésével nem jelenik meg a PROS fiók QR kódja sem."
 ${EndIf}
 GetDlgItem $0 $HWNDPARENT 1
 SendMessage $0 ${WM_SETTEXT} 0 "STR:$ActionButton"
FunctionEnd
Function ComponentsLeave
 StrCpy $SelectedOperation $Operation
 StrCpy $Operation "Detect"
 Call RunBackend
 StrCpy $Operation $SelectedOperation
 ${If} $State == "READY_INSTALL"
 ${OrIf} $State == "READY_UPGRADE"
 ${OrIf} $State == "READY_REBASE"
 ${OrIf} $State == "READY_REMOVE"
  Return
 ${EndIf}
 Call ErrorMessage
 MessageBox MB_OK|MB_ICONEXCLAMATION "$ErrorText"
 Abort
FunctionEnd
Function ProgressShow
 !insertmacro MUI_HEADER_TEXT "$ActionButton" "Kérlek, várj, amíg a művelet befejeződik."
 SendMessage $mui.InstFilesPage.Text ${WM_SETTEXT} 0 "STR:A kiválasztott művelet folyamatban van..."
FunctionEnd
Section
 Call RunBackend
 ${If} $State == "INSTALLED"
  StrCpy $FinishTitle "Az összetevők beállítása elkészült"
  StrCpy $FinishText ""
  ${If} $HuChoice == ${BST_CHECKED}
   StrCpy $FinishText "Indítsd el a játékot, és a szövegnyelvnél válaszd az angolt.$\r$\n$\r$\nA menük és feliratok magyarul jelennek meg. A fegyvernevek angolul maradnak."
  ${Else}
   StrCpy $FinishText "A játék szövege és hangja az eredeti nyelven marad."
  ${EndIf}
  ${If} $AdsChoice == ${BST_CHECKED}
   StrCpy $FinishText "$FinishText$\r$\n$\r$\nA főmenü reklámpanelje és a PROS fiók QR kódja nem jelenik meg."
  ${Else}
   StrCpy $FinishText "$FinishText$\r$\n$\r$\nA főmenü reklámpanelje az eredeti módon működik."
  ${EndIf}
  StrCpy $FinishText "$FinishText$\r$\n$\r$\nAz összetevők módosításához vagy eltávolításához indítsd el újra ezt az EXE-t."
 ${ElseIf} $State == "REMOVED"
  StrCpy $FinishTitle "Az összetevők eltávolítása elkészült"
  StrCpy $FinishText "Visszaálltak az eredeti játékfájlok.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradtak.$\r$\n$\r$\nA magyarítást és a reklámpanel elrejtését később ugyanezzel az EXE-vel ismét telepítheted."
 ${ElseIf} $State == "UNCHANGED"
  StrCpy $FinishTitle "Nincs szükség módosításra"
  StrCpy $FinishText "A kiválasztott összetevők már naprakészek. Nem történt módosítás."
 ${Else}
  Call ErrorMessage
  MessageBox MB_OK|MB_ICONEXCLAMATION "$ErrorText"
  SetErrorLevel 1
  Abort
 ${EndIf}
SectionEnd
