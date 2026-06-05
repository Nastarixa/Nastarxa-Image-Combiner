#Requires AutoHotkey v2.0
#SingleInstance Force
TraySetIcon "Combiner.ico"

_FFMPEG := ResolveFFmpegPath()
_OUTPUT_DIR := EnvGet("USERPROFILE") "\Videos"
_imageList := []
_selectedRow := 0
_tempDir := ""
_PRESET_FILE := A_ScriptDir "\presets.ini"
_LAST_PROJECT_FILE := A_ScriptDir "\last_project.txt"
_cancelGenerate := false
_lastPrepareError := ""
_ffmpegEncoderCache := Map()
_previewCacheDir := A_Temp "\NastarxaIC_preview"
_timesheetLayers := []
_undoStack := []
_redoStack := []
_MAX_UNDO := 10
_isHistoryReplay := false
_activeTimesheetGui := ""

OnExit((*) => CleanupTemp())

BuildGui()

ResolveFFmpegPath() {
    candidates := GetFFmpegCandidates()
    for path in candidates {
        if FileExist(path)
            return path
    }
    return candidates[1]
}

GetFFmpegCandidates() {
    candidates := [
        A_ScriptDir "\ffmpeg\bin\ffmpeg.exe",
        A_ScriptDir "\ffmpeg\ffmpeg.exe",
        A_ScriptDir "\..\ffmpeg\bin\ffmpeg.exe",
        A_ScriptDir "\..\ffmpeg\ffmpeg.exe"
    ]
    found := []
    seen := Map()
    for path in candidates {
        if !seen.Has(path) {
            seen[path] := true
            found.Push(path)
        }
    }
    Loop Files, A_ScriptDir "\ffmpeg\**\ffmpeg.exe", "FR" {
        if !seen.Has(A_LoopFileFullPath) {
            seen[A_LoopFileFullPath] := true
            found.Push(A_LoopFileFullPath)
        }
    }
    return found
}

GetFFmpegPathForFormat(fmt := "") {
    if fmt = "MP4" || fmt = "AVI" {
        if path := FindFFmpegWithEncoder("libx264")
            return path
    } else if fmt = "MOV" {
        if path := FindFFmpegWithEncoder("qtrle")
            return path
    } else if fmt = "WebM" {
        if path := FindFFmpegWithEncoder("libvpx")
            return path
    }
    return _FFMPEG
}

FindFFmpegWithEncoder(encoder) {
    for path in GetFFmpegCandidates() {
        if FileExist(path) && FFmpegHasEncoder(path, encoder)
            return path
    }
    return ""
}

FFmpegHasEncoder(ffmpegPath, encoder) {
    global _ffmpegEncoderCache
    key := ffmpegPath "|" encoder
    if _ffmpegEncoderCache.Has(key)
        return _ffmpegEncoderCache[key]

    logFile := A_Temp "\NastarxaIC_enc_" A_TickCount ".log"
    ok := false
    try {
        RunFFmpegLogged("-hide_banner -encoders", logFile, "", ffmpegPath)
        if FileExist(logFile)
            ok := InStr(FileRead(logFile), encoder) > 0
    }
    try FileDelete(logFile)
    _ffmpegEncoderCache[key] := ok
    return ok
}

BuildGui() {
    ; =========================================================
    ; GUI
    ; =========================================================

    g := Gui("", "Nastarxa Image Combiner")

    g.DropFile := 1
    g.BackColor := "25282E"

    g.SetFont("s9", "Segoe UI")
    g.MarginX := 12
    g.MarginY := 10
    ; =========================================================
    ; LEFT PANEL
    ; =========================================================

    g.lblList := g.AddText("x12 y10 cFFFFFF", "Queue")

    ; -------------------------
    ; Toolbar
    ; -------------------------

    g.btnAdd        := g.AddButton("x12  y32 w74 h24", "Add Image")
    g.btnAddFolder  := g.AddButton("x90  yp w74 h24", "Folder")
    g.btnRemove     := g.AddButton("x168 yp w60 h24", "Remove")
    g.btnDup        := g.AddButton("x232 yp w52 h24", "Copy")
    g.btnClear      := g.AddButton("x288 yp w48 h24", "Clear")

    g.btnUp         := g.AddButton("x344 yp w28 h24", Chr(9650))
    g.btnDown       := g.AddButton("x376 yp w28 h24", Chr(9660))

    g.btnSort       := g.AddButton("x412 yp w40 h24", "A-Z")
    g.btnRev        := g.AddButton("x456 yp w44 h24", "Flip")

    g.btnSave       := g.AddButton("x508 yp w48 h24", "Save")
    g.btnLoad       := g.AddButton("x560 yp w48 h24", "Open")
    g.btnGuide      := g.AddButton("x616 yp w56 h24", "Guide")

    ; -------------------------
    ; List
    ; -------------------------

    g.lv := g.AddListView(
        "x14 y68 w740 h502 Multi BackgroundFFFFFF c000000 Grid",
        ["#", "File", "Exp", "Note", "Layer", "Cell", "Start", "End", "TS Dur"]
    )
    EnableListViewDoubleBuffer(g.lv)

    g.lv.ModifyCol(1, 35)
    g.lv.ModifyCol(2, 250)
    g.lv.ModifyCol(3, 50)
    g.lv.ModifyCol(4, 100)
    g.lv.ModifyCol(5, 72)
    g.lv.ModifyCol(6, 48)
    g.lv.ModifyCol(7, 52)
    g.lv.ModifyCol(8, 52)
    g.lv.ModifyCol(9, 58)

    ; -------------------------
    ; Exposure
    ; -------------------------

    g.lblExposure := g.AddText("x12 y372 cD0D0D0", "Frames")

    g.expEdit := g.AddEdit(
        "x70 y368 w42 h22 Number Center BackgroundFFFFFF c000000",
        "2"
    )

    g.btnExp1 := g.AddButton("x118 y367 w24 h22", "1")
    g.btnExp2 := g.AddButton("x146 yp w24 h22", "2")
    g.btnExp3 := g.AddButton("x174 yp w24 h22", "3")
    g.btnExp4 := g.AddButton("x202 yp w24 h22", "4")
    g.btnExp5 := g.AddButton("x230 yp w24 h22", "5")
    g.btnExp6 := g.AddButton("x258 yp w24 h22", "6")

    g.btnApplyExp := g.AddButton("x290 yp w50 h22", "Apply")
    g.btnApplyAll := g.AddButton("x344 yp w44 h22", "All")

    g.btnPresetSave := g.AddButton(
        "x444 yp w82 h22",
        "Save Preset"
    )

    g.btnPresetLoad := g.AddButton(
        "x526 yp w82 h22",
        "Load Preset"
    )

    g.btnRecent := g.AddButton(
        "x608 yp w86 h22",
        "Last Project"
    )
    ; -------------------------
    ; Note
    ; -------------------------

    g.lblNote := g.AddText("x12 y400 cD0D0D0", "Note")

    g.noteEdit := g.AddEdit(
        "x70 y396 w360 h22 BackgroundFFFFFF c000000"
    )

    g.btnApplyNote := g.AddButton(
        "x436 y395 w50 h24",
        "Set"
    )

    ; =========================================================
    ; RIGHT PANEL
    ; =========================================================

    rx := 700

    g.lblOutput := g.AddText("x" rx " y10 cFFFFFF", "Export")

    ; -------------------------
    ; FPS / LOOP
    ; -------------------------

    g.lblFps := g.AddText("x" rx " y34 cD0D0D0", "FPS")

    g.fpsEdit := g.AddEdit(
        "x" rx+34 " y30 w42 h22 Number Center BackgroundFFFFFF c000000",
        "24"
    )

    g.fpsEdit.Value := "24"

    g.lblLoop := g.AddText("x" rx+90 " y34 cD0D0D0", "Loop")

    g.loopEdit := g.AddEdit(
        "x" rx+130 " y30 w42 h22 Number Center BackgroundFFFFFF c000000",
        "0"
    )

    ; -------------------------
    ; FORMAT
    ; -------------------------

    g.lblFormats := g.AddText("x" rx " y64 cD0D0D0", "Formats")

    g.chkGIF  := g.AddCheckbox("x" rx+48  " y62 w46 cFFFFFF Checked", "GIF")
    g.chkMP4  := g.AddCheckbox("x" rx+96  " y62 w48 cFFFFFF Checked", "MP4")
    g.chkAVI  := g.AddCheckbox("x" rx+148 " y62 w42 cFFFFFF", "AVI")
    g.chkWebM := g.AddCheckbox("x" rx+194 " y62 w60 cFFFFFF", "WebM")
    g.chkMOV  := g.AddCheckbox("x" rx+260 " y62 w54 cFFFFFF", "MOV")

    g.chkPNG := g.AddCheckbox(
        "x" rx+48 " y84 w50 cFFFFFF",
        "PNG"
    )

    g.chkSheet := g.AddCheckbox(
        "x" rx+102 " y84 w70 cFFFFFF",
        "Sheet"
    )

    g.sheetCountEdit := g.AddEdit(
        "x" rx+176 " y82 w38 h22 Number Center BackgroundFFFFFF c000000",
        "16"
    )

    g.sheetCountEdit.Value := "16"

    g.lblSheetCount := g.AddText("x" rx+220 " y82 c909090", "frames per sheet")

    ; -------------------------
    ; SIZE
    ; -------------------------

    g.lblSize := g.AddText("x" rx " y118 cD0D0D0", "Canvas")

    g.widthEdit := g.AddEdit(
        "x" rx+40 " y114 w56 h22 Number Center BackgroundFFFFFF c000000",
        "1920"
    )

    g.lblSizeX := g.AddText("x" rx+102 " y118 c909090", Chr(215))

    g.heightEdit := g.AddEdit(
        "x" rx+116 " y114 w56 h22 Number Center BackgroundFFFFFF c000000",
        "1080"
    )

    ; -------------------------
    ; NAME
    ; -------------------------

    g.lblFilename := g.AddText("x" rx " y148 cD0D0D0", "Name")

    g.outEdit := g.AddEdit(
        "x" rx+40 " y144 w120 h22 BackgroundFFFFFF c000000",
        "animation"
    )

    g.chkTimestamp := g.AddCheckbox(
        "x" rx+166 " y146 w55 cFFFFFF",
        "+time"
    )
    g.chkTimesheet := g.AddCheckbox(
        "x" rx+244 " y146 w46 cFFFFFF",
        "TS"
    )
    g.btnTimesheet := g.AddButton(
        "x" rx+292 " y144 w68 h24",
        "Setup..."
    )

    ; -------------------------
    ; AUDIO
    ; -------------------------

    g.lblAudio := g.AddText("x" rx " y178 cD0D0D0", "Audio")

    g.audioEdit := g.AddEdit(
        "x" rx+40 " y174 w170 h22 ReadOnly BackgroundFFFFFF c000000"
    )

    g.btnAudio := g.AddButton(
        "x" rx+214 " y173 w46 h24",
        "Pick"
    )

    ; -------------------------
    ; QUALITY
    ; -------------------------

    g.lblQuality := g.AddText("x" rx " y208 cD0D0D0", "Quality")

    g.crfEdit := g.AddEdit(
        "x" rx+40 " y204 w42 h22 Number Center BackgroundFFFFFF c000000",
        "23"
    )

    g.lblQualityHint := g.AddText(
        "x" rx+88 " y208 c707070",
        "lower = better"
    )

    ; -------------------------
    ; FIT
    ; -------------------------

    g.lblFit := g.AddText("x" rx " y238 cD0D0D0", "Fit")

    g.fitDDL := g.AddDropDownList(
        "x" rx+40 " y234 w90 Choose1",
        ["stretch", "contain", "cover", "pad"]
    )

    g.lblBg := g.AddText("x" rx+140 " y238 c909090", "BG")

    g.bgEdit := g.AddEdit(
        "x" rx+164 " y234 w58 h22 BackgroundFFFFFF c000000",
        "#FFFFFF"
    )

    g.lblBgAlpha := g.AddText("x" rx+232 " y238 c909090", "A")
    g.bgAlphaEdit := g.AddEdit(
        "x" rx+240 " y234 w32 h22 BackgroundFFFFFF c000000",
        "FF"
    )

    ; -------------------------
    ; OUTPUT TO
    ; -------------------------

    g.lblOutputTo := g.AddText("x" rx " y268 cD0D0D0", "Save To")

    g.dirEdit := g.AddEdit(
        "x" rx+40 " y264 w170 h22 ReadOnly BackgroundFFFFFF c000000",
        _OUTPUT_DIR
    )

    g.btnBrowse := g.AddButton(
        "x" rx+214 " y263 w46 h24",
        "..."
    )

    ; -------------------------
    ; PREVIEW
    ; -------------------------

    g.lblPreview := g.AddText("x" rx " y300 cD8D8D8", "Preview")

    g.previewPic := g.AddPicture(
        "x" rx " y322 w190 h122 Background1E2127"
    )

    g.previewText := g.AddText(
        "x" rx+198 " y324 w110 h78 c909090",
        "No Preview"
    )

    g.previewFrameSlider := g.AddSlider(
        "x" rx " y448 w190 h22 Range1-100 ToolTip",
        1
    )

    g.previewFrameLabel := g.AddText(
        "x" rx+198 " y406 w110 h18 c909090",
        ""
    )
    g.previewFrameSlider.Visible := false
    g.previewFrameSlider.Enabled := false
    g.previewFrameLabel.Visible := false

    ; -------------------------
    ; TIMELINE
    ; -------------------------

    g.lblTimeline := g.AddText("x" rx " y432 cD8D8D8", "Timeline")

    g.timeText := g.AddText(
        "x" rx " y454 w270 cFFFFFF",
        "Items: 0  -  Frames: 0  -  Duration: 0.0s"
    )

    ; =========================================================
    ; BOTTOM
    ; =========================================================

    g.statText := g.AddText(
        "x12 y390 w790 c808080",
        "Ready"
    )

    g.Progress := g.AddProgress(
        "x12 y410 w790 h10 cFFD54F Background25282E"
    )

    ; -------------------------
    ; Bottom Buttons
    ; -------------------------


    g.btnGen := g.AddButton(
        "x530 y524 w100 h32",
        "Generate"
    )

    g.btnGen.Opt("+Default")

    g.btnCancel := g.AddButton(
        "x636 yp w64 h32",
        "Cancel"
    )

    g.btnOpenFolder := g.AddButton(
        "x706 yp w64 h32",
        "Open"
    )

    g.btnCancel.Enabled := false

    ; =========================================================
    ; EVENTS
    ; =========================================================

    g.btnAdd.OnEvent("Click", (*) => OnAddImages(g))
    g.btnAddFolder.OnEvent("Click", (*) => OnAddFolder(g))
    g.btnRemove.OnEvent("Click", (*) => RemoveSelected(g))
    g.btnDup.OnEvent("Click", (*) => DuplicateSelected(g))
    g.btnClear.OnEvent("Click", (*) => ClearAll(g))

    g.btnUp.OnEvent("Click", (*) => MoveItem(g, -1))
    g.btnDown.OnEvent("Click", (*) => MoveItem(g, 1))

    g.btnSort.OnEvent("Click", (*) => SortByName(g))
    g.btnRev.OnEvent("Click", (*) => ReverseOrder(g))

    g.btnSave.OnEvent("Click", (*) => SaveProject(g))
    g.btnLoad.OnEvent("Click", (*) => LoadProject(g))
    g.btnGuide.OnEvent("Click", (*) => ShowGuide())
    g.btnTimesheet.OnEvent("Click", (*) => ShowTimesheetSetup(g))

    g.lv.OnEvent("Click", (lv, row) => SelectRow(g, row))
    g.lv.OnEvent("DoubleClick", (lv, row) => SelectRow(g, row))
    g.lv.OnEvent("ItemFocus", (lv, row) => row ? SelectRow(g, row) : 0)

    g.btnExp1.OnEvent("Click", (*) => SetExposurePreset(g, 1))
    g.btnExp2.OnEvent("Click", (*) => SetExposurePreset(g, 2))
    g.btnExp3.OnEvent("Click", (*) => SetExposurePreset(g, 3))
    g.btnExp4.OnEvent("Click", (*) => SetExposurePreset(g, 4))
    g.btnExp5.OnEvent("Click", (*) => SetExposurePreset(g, 5))
    g.btnExp6.OnEvent("Click", (*) => SetExposurePreset(g, 6))

    g.btnApplyExp.OnEvent("Click", (*) => ApplyExposure(g, false))
    g.btnApplyAll.OnEvent("Click", (*) => ApplyExposure(g, true))

    g.btnApplyNote.OnEvent("Click", (*) => ApplyNote(g))

    g.fpsEdit.OnEvent("Change", (*) => OnFpsChanged(g))

    g.widthEdit.OnEvent("Change", (*) => UpdatePreview(g))
    g.heightEdit.OnEvent("Change", (*) => UpdatePreview(g))
    g.fitDDL.OnEvent("Change", (*) => UpdatePreview(g))
    g.previewFrameSlider.OnEvent("Change", (*) => OnPreviewFrameChanged(g))

    g.loopEdit.OnEvent("Change", (*) => g.Progress.Value := 0)
    g.crfEdit.OnEvent("Change", (*) => g.Progress.Value := 0)
    g.bgEdit.OnEvent("Change", (*) => g.Progress.Value := 0)
    g.bgAlphaEdit.OnEvent("Change", (*) => g.Progress.Value := 0)
    g.audioEdit.OnEvent("Change", (*) => g.Progress.Value := 0)
    g.chkTimestamp.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkGIF.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkMP4.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkAVI.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkWebM.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkMOV.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkPNG.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkSheet.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkTimesheet.OnEvent("Click", (*) => ToggleTimesheetMode(g))

    g.btnBrowse.OnEvent("Click", (*) => BrowseOutputDir(g))
    g.btnAudio.OnEvent("Click", (*) => PickAudio(g))

    g.btnGen.OnEvent("Click", (*) => Generate(g))
    g.btnCancel.OnEvent("Click", (*) => CancelGenerate(g))

    g.btnOpenFolder.OnEvent("Click", (*) => OpenOutputFolder(g))

    g.btnPresetSave.OnEvent("Click", (*) => SavePreset(g))
    g.btnPresetLoad.OnEvent("Click", (*) => LoadPreset(g))
    g.btnRecent.OnEvent("Click", (*) => LoadLastProject(g))

    g.OnEvent("DropFiles", (gui, ctrl, files, *) => DropFiles(g, files))
    ; =========================================================
    ; SHOW
    ; =========================================================

    g.Show("Hide w1180 h680 Center")

    HotIfWinActive("ahk_id " g.Hwnd)
    Hotkey("Delete", (*) => HandleCombinerDelete(g))
    Hotkey("*^z", (*) => HandleCombinerUndo(g))
    Hotkey("*^+z", (*) => HandleCombinerRedo(g))
    HotIfWinActive("Timesheet Layer Setup")
    Hotkey("*^z", (*) => HandleCombinerUndo(g))
    Hotkey("*^+z", (*) => HandleCombinerRedo(g))
    Hotkey("~Enter", (*) => CommitTimesheetEditorEnter())
    Hotkey("~NumpadEnter", (*) => CommitTimesheetEditorEnter())
    HotIfWinActive()

    ApplyLayout(g, 1180, 680)
    g.btnTimesheet.Enabled := g.chkTimesheet.Value = 1
    ApplyTimesheetModeUI(g)
    g.Show()

    return g
}

DropFiles(g, files) {
    g.Progress.Value := 0
    if !IsObject(files)
        return
    addedRows := []
    len := files.Length
    PushUndoState(g)
    BeginListUpdate(g)
    try {
        loop len {
            f := files[A_Index]
            if DirExist(f) {
                for mediaPath in CollectMediaFromFolder(f) {
                    idx := AddSingleMedia(g, mediaPath)
                    if idx
                        addedRows.Push(idx)
                }
                continue
            }
            idx := AddSingleMedia(g, f)
            if idx
                addedRows.Push(idx)
        }
    } finally EndListUpdate(g)
    if addedRows.Length > 0 {
        SelectRows(g, addedRows, addedRows[addedRows.Length])
        RefreshTimeline(g)
        UpdatePreview(g)
        g.statText.Value := "Added " addedRows.Length " item(s)"
    }
}

IsValidFile(path) {
    SplitPath(path, , , &ext)
    ext := "." StrLower(ext)
    static valid := ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "webp", "gif", "mp4", "mov"]
    for v in valid {
        if ext = "." v
            return true
    }
    return false
}

IsVideoFile(path) {
    SplitPath(path, , , &ext)
    ext := StrLower(ext)
    return ext = "mp4" || ext = "gif" || ext = "mov"
}

OnAddImages(g) {
    files := FileSelect("M", , "Select Images", "Media (*.png; *.jpg; *.jpeg; *.bmp; *.tif; *.tiff; *.webp; *.gif; *.mp4; *.mov)")
    if files = ""
        return
    g.Progress.Value := 0
    addedRows := []
    PushUndoState(g)
    BeginListUpdate(g)
    try {
        for f in files
            if idx := AddSingleMedia(g, f)
                addedRows.Push(idx)
    } finally EndListUpdate(g)
    if addedRows.Length > 0 {
        SelectRows(g, addedRows, addedRows[addedRows.Length])
        RefreshTimeline(g)
        UpdatePreview(g)
        g.statText.Value := "Added " addedRows.Length " item(s)"
    }
}

OnAddFolder(g) {
    dir := FileSelect("D", , "Select Folder")
    if dir = ""
        return
    files := CollectMediaFromFolder(dir)
    if files.Length = 0
        return
    g.Progress.Value := 0
    addedRows := []
    PushUndoState(g)
    BeginListUpdate(g)
    try {
        for f in files
            if idx := AddSingleMedia(g, f)
                addedRows.Push(idx)
    } finally EndListUpdate(g)
    if addedRows.Length > 0 {
        SelectRows(g, addedRows, addedRows[addedRows.Length])
        RefreshTimeline(g)
        UpdatePreview(g)
        g.statText.Value := "Added " addedRows.Length " item(s) from folder"
    }
}

CollectMediaFromFolder(dir) {
    files := []
    Loop Files, dir "\*.*", "F" {
        if IsValidFile(A_LoopFileFullPath)
            files.Push(A_LoopFileFullPath)
    }
    return SortPathsNaturally(files)
}

SortPathsNaturally(paths) {
    sorted := paths.Clone()
    Loop sorted.Length {
        swapped := false
        Loop sorted.Length - 1 {
            if StrCompare(sorted[A_Index], sorted[A_Index + 1]) > 0 {
                tmp := sorted[A_Index]
                sorted[A_Index] := sorted[A_Index + 1]
                sorted[A_Index + 1] := tmp
                swapped := true
            }
        }
        if !swapped
            break
    }
    return sorted
}

GetTimesheetLayerOptions() {
    global _timesheetLayers
    if _timesheetLayers.Length = 0
        _timesheetLayers := BuildDefaultTimesheetLayers()
    return _timesheetLayers
}

BuildDefaultTimesheetLayers() {
    layers := []
    for base in ["A", "B", "C", "D", "E", "F", "G", "H"] {
        layers.Push(base "_shita")
        layers.Push(base)
        layers.Push(base "_ue")
    }
    return layers
}

SerializeTimesheetLayers() {
    return JoinText(GetTimesheetLayerOptions(), "|")
}

LoadTimesheetLayersFromString(raw) {
    global _timesheetLayers
    layers := []
    for part in StrSplit(raw, "|") {
        name := Trim(part)
        if name != ""
            layers.Push(name)
    }
    if layers.Length = 0
        layers := BuildDefaultTimesheetLayers()
    _timesheetLayers := layers
}

EnsureTimesheetLayerExists(layer) {
    global _timesheetLayers
    if Trim(layer) = ""
        return
    for existing in GetTimesheetLayerOptions() {
        if existing = layer
            return
    }
    _timesheetLayers.Push(layer)
}

IsDefaultVisibleTimesheetLayer(layer) {
    return RegExMatch(layer, "^[A-H]$") > 0
}

ApplyTimesheetModeUI(g) {
    tsMode := IsTimesheetMode(g)
    g.expEdit.Enabled := !tsMode
    g.btnExp1.Enabled := !tsMode
    g.btnExp2.Enabled := !tsMode
    g.btnExp3.Enabled := !tsMode
    g.btnExp4.Enabled := !tsMode
    g.btnExp5.Enabled := !tsMode
    g.btnExp6.Enabled := !tsMode
    g.btnApplyExp.Enabled := !tsMode
    g.btnApplyAll.Enabled := !tsMode

    g.btnUp.Enabled := !tsMode
    g.btnDown.Enabled := !tsMode
    g.btnSort.Enabled := !tsMode
    g.btnRev.Enabled := !tsMode

    g.lblExposure.Value := tsMode ? "Timesheet" : "Frames"
}

EnsureTimesheetFields(item) {
    if !item.HasProp("tsEnabled")
        item.tsEnabled := false
    if !item.HasProp("tsLayer")
        item.tsLayer := "A"
    if !item.HasProp("tsKind")
        item.tsKind := "Key"
    if !item.HasProp("tsCell")
        item.tsCell := ""
    if !item.HasProp("tsStartFrame")
        item.tsStartFrame := 1
    if !item.HasProp("tsEndFrame")
        item.tsEndFrame := Max(1, item.HasProp("exposure") ? item.exposure : 1)
    if !item.HasProp("linkGroup")
        item.linkGroup := ""
    EnsureTimesheetLayerExists(item.tsLayer)
}

BuildLinkedDuplicateItem(src) {
    copy := DeepCloneValue(src)
    EnsureTimesheetFields(copy)
    copy.tsEnabled := false
    copy.tsCell := ""
    copy.tsStartFrame := 1
    copy.tsEndFrame := Max(1, copy.HasProp("exposure") ? copy.exposure : 1)
    return copy
}

GenerateLinkGroupId() {
    return "LG_" A_NowUTC "_" A_TickCount "_" Random(1000, 9999)
}

EnsureLinkedGroup(item) {
    EnsureTimesheetFields(item)
    if Trim(String(item.linkGroup)) = ""
        item.linkGroup := GenerateLinkGroupId()
    return item.linkGroup
}

WriteQueueItemsToIni(path, section) {
    IniWrite(_imageList.Length, path, section, "Count")
    for i, item in _imageList {
        EnsureTimesheetFields(item)
        prefix := "Item" i
        IniWrite(item.path, path, section, prefix "_Path")
        IniWrite(item.exposure, path, section, prefix "_Exposure")
        IniWrite(item.type, path, section, prefix "_Type")
        IniWrite(item.HasProp("frameCount") ? item.frameCount : 0, path, section, prefix "_FrameCount")
        IniWrite(item.HasProp("durationSec") ? item.durationSec : 0, path, section, prefix "_DurationSec")
        IniWrite(item.HasProp("previewFrame") ? item.previewFrame : 1, path, section, prefix "_PreviewFrame")
        IniWrite(item.HasProp("note") ? item.note : "", path, section, prefix "_Note")
        IniWrite(item.tsEnabled ? 1 : 0, path, section, prefix "_TsEnabled")
        IniWrite(item.tsLayer, path, section, prefix "_TsLayer")
        IniWrite(item.tsKind, path, section, prefix "_TsKind")
        IniWrite(item.tsCell, path, section, prefix "_TsCell")
        IniWrite(item.tsStartFrame, path, section, prefix "_TsStartFrame")
        IniWrite(item.tsEndFrame, path, section, prefix "_TsEndFrame")
        IniWrite(item.linkGroup, path, section, prefix "_LinkGroup")
    }
}

ReadQueueItemsFromIni(path, section) {
    items := []
    count := Integer(IniRead(path, section, "Count", "0"))
    Loop count {
        prefix := "Item" A_Index
        itemPath := IniRead(path, section, prefix "_Path", "")
        if itemPath = ""
            continue
        SplitPath(itemPath, &name)
        itemType := IniRead(path, section, prefix "_Type", "image")
        item := {
            path: itemPath,
            name: name,
            exposure: Integer(IniRead(path, section, prefix "_Exposure", "2")),
            type: itemType,
            note: IniRead(path, section, prefix "_Note", "")
        }
        EnsureTimesheetFields(item)
        if itemType = "video" {
            item.frameCount := Integer(IniRead(path, section, prefix "_FrameCount", "0"))
            item.durationSec := Float(IniRead(path, section, prefix "_DurationSec", "0"))
            item.previewFrame := Integer(IniRead(path, section, prefix "_PreviewFrame", "1"))
        }
        item.tsEnabled := Integer(IniRead(path, section, prefix "_TsEnabled", "0")) = 1
        item.tsLayer := IniRead(path, section, prefix "_TsLayer", item.tsLayer)
        item.tsKind := IniRead(path, section, prefix "_TsKind", item.tsKind)
        item.tsCell := IniRead(path, section, prefix "_TsCell", item.tsCell)
        item.tsStartFrame := Integer(IniRead(path, section, prefix "_TsStartFrame", item.tsStartFrame))
        item.tsEndFrame := Integer(IniRead(path, section, prefix "_TsEndFrame", item.tsEndFrame))
        item.linkGroup := IniRead(path, section, prefix "_LinkGroup", "")
        EnsureTimesheetLayerExists(item.tsLayer)
        items.Push(item)
    }
    return items
}

GetTimesheetKindOptions() {
    return ["Key", "Inbetween"]
}

AutoDetectTimesheetFromName(name, &layer := "", &cell := "") {
    layer := ""
    cell := ""
    if RegExMatch(name, "i)(?:^|[_\-\s])(A|B|C|D|E|F|G|H)\s*([0-9]+)_(shita|ue)(?:$|[_\-\s\.])", &m) {
        layer := StrUpper(m[1]) "_" StrLower(m[3])
        cell := m[2]
        return true
    }
    if RegExMatch(name, "i)(?:^|[_\-\s])(A|B|C|D|E|F|G|H)_(shita|ue)\s*([0-9]+)", &m) {
        layer := StrUpper(m[1]) "_" StrLower(m[2])
        cell := m[3]
        return true
    }
    if RegExMatch(name, "i)(?:^|[_\-\s])(A|B|C|D|E|F|G|H)\s*([0-9]+)", &m) {
        layer := StrUpper(m[1])
        cell := m[2]
        return true
    }
    return false
}

AddSingleMedia(g, path) {
    global _selectedRow
    if !IsValidFile(path)
        return 0
    SplitPath(path, &name)
    for item in _imageList {
        if item.path = path
            return 0
    }
    if IsVideoFile(path) {
        item := {path: path, name: name, exposure: 1, type: "video", frameCount: 0, durationSec: 0, previewFrame: 1, note: ""}
        _imageList.Push(item)
        lbl := "1 (video)"
        ProbeVideoLater(g, item, _imageList.Length)
    } else {
        item := {path: path, name: name, exposure: 2, type: "image", note: ""}
        _imageList.Push(item)
        lbl := "2"
        if _imageList.Length = 1 {
            dim := GetImageDimensions(path)
            if dim.w > 0 && dim.h > 0 {
                g.widthEdit.Value := dim.w
                g.heightEdit.Value := dim.h
            }
            if HasAlphaChannel(path) {
                g.bgEdit.Value := "#000000"
                g.bgAlphaEdit.Value := "00"
            }
        }
    }
    EnsureTimesheetFields(item)
    AutoDetectTimesheetFromName(item.name, &tsLayer, &tsCell)
    if tsLayer != ""
        item.tsLayer := tsLayer
    if tsCell != ""
        item.tsCell := tsCell
    idx := _imageList.Length
    g.lv.Add(, idx, name, lbl, item.note)
    _selectedRow := idx
    return idx
}

ProbeVideoLater(g, item, idx) {
    fps := RefreshTimelineRaw(g)
    SetTimer () => (
        info := ProbeVideoInfo(item.path, fps),
        item.frameCount := info.frameCount,
        item.durationSec := info.durationSec,
        item.previewFrame := ClampPreviewFrame(item),
        UpdateListViewRow(g, idx),
        _selectedRow ? UpdatePreview(g) : 0,
        RefreshTimeline(g),
        SetTimer(, 0)
    ), -1
}

ProbeVideoInfo(path, fps) {
    rnd := Random(1, 999999)
    logFile := A_Temp "\NastarxaIC_probe_" rnd ".txt"
    RunFFmpegLogged("-i " Chr(34) path Chr(34), logFile)
    output := ""
    try output := FileRead(logFile)
    try FileDelete(logFile)
    if RegExMatch(output, "Duration: (\d+):(\d+):(\d+\.\d+)", &m) {
        dur := Integer(m[1])*3600 + Integer(m[2])*60 + Float(m[3])
        return {durationSec: dur, frameCount: Max(1, Round(dur * fps))}
    }
    return {durationSec: 0, frameCount: 0}
}

GetImageDimensions(path) {
    try {
        img := ComObject("WIA.ImageFile")
        img.LoadFile(path)
        return {w: img.Width, h: img.Height}
    }
    return {w: 0, h: 0}
}

HasAlphaChannel(path) {
    log := A_Temp "\NastarxaIC_alpha_" A_TickCount ".txt"
    RunFFmpegLogged("-i " Chr(34) path Chr(34) " -hide_banner", log)
    output := ""
    try output := FileRead(log)
    try FileDelete(log)
    return InStr(output, "rgba") || InStr(output, "yuva") || InStr(output, "ga ")
}

GetSelectedRows(g) {
    rows := []
    row := 0
    Loop {
        row := g.lv.GetNext(row)
        if !row
            break
        rows.Push(row)
    }
    return rows
}

SortRowsDescending(rows) {
    Loop rows.Length {
        swapped := false
        Loop rows.Length - 1 {
            if rows[A_Index] < rows[A_Index + 1] {
                tmp := rows[A_Index]
                rows[A_Index] := rows[A_Index + 1]
                rows[A_Index + 1] := tmp
                swapped := true
            }
        }
        if !swapped
            break
    }
    return rows
}

RemoveSelected(g) {
    global _selectedRow
    rows := GetSelectedRows(g)
    if rows.Length = 0
        return
    PushUndoState(g)
    g.Progress.Value := 0
    nextRow := rows[1]
    rows := SortRowsDescending(rows)
    for r in rows
        _imageList.RemoveAt(r)
    _selectedRow := _imageList.Length > 0 ? Min(nextRow, _imageList.Length) : 0
    SyncListViewToModel(g, _selectedRow > 0 ? [_selectedRow] : [], _selectedRow)
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Removed " rows.Length " item(s)"
}

DuplicateSelected(g) {
    global _selectedRow
    rows := GetSelectedRows(g)
    if rows.Length = 0
        return
    PushUndoState(g)
    g.Progress.Value := 0
    rowsCopy := []
    newRows := []
    for r in rows
        rowsCopy.Push(r)
    rowsCopy := SortRowsDescending(rowsCopy)
    for r in rowsCopy {
        src := _imageList[r]
        copy := src.Clone()
        SplitPath(copy.path, &nm)
        copy.name := nm
        copy.linkGroup := ""
        _imageList.InsertAt(r + 1, copy)
        newRows.InsertAt(1, r + 1)
    }
    _selectedRow := newRows[newRows.Length]
    SyncListViewToModel(g, newRows, _selectedRow)
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Duplicated " rows.Length " item(s)"
}

SortByName(g) {
    if IsTimesheetMode(g)
        return
    global _imageList
    global _selectedRow
    PushUndoState(g)
    g.Progress.Value := 0
    sorted := _imageList.Clone()
    Loop sorted.Length {
        swapped := false
        Loop sorted.Length - 1 {
            if StrCompare(sorted[A_Index].name, sorted[A_Index + 1].name) > 0 {
                tmp := sorted[A_Index]
                sorted[A_Index] := sorted[A_Index + 1]
                sorted[A_Index + 1] := tmp
                swapped := true
            }
        }
        if !swapped
            break
    }
    _imageList := sorted
    _selectedRow := 0
    SyncListViewToModel(g)
    ClearListViewSelection(g.lv)
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Sorted by name"
}

ReverseOrder(g) {
    if IsTimesheetMode(g)
        return
    global _imageList
    global _selectedRow
    PushUndoState(g)
    g.Progress.Value := 0
    reversed := []
    for i in _imageList
        reversed.InsertAt(1, i)
    _imageList := reversed
    _selectedRow := 0
    SyncListViewToModel(g)
    ClearListViewSelection(g.lv)
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Reversed order"
}

SetExposurePreset(g, val) {
    if IsTimesheetMode(g)
        return
    g.expEdit.Value := val
    g.Progress.Value := 0
    rows := GetSelectedRows(g)
    if rows.Length > 0 {
        PushUndoState(g)
        for r in rows
            _imageList[r].exposure := val
        UpdateListViewRows(g, rows)
        RefreshTimeline(g)
        g.statText.Value := "Exposure set to " val " for " rows.Length " item(s)"
    } else {
        g.statText.Value := "Preset " val " loaded - click Apply"
    }
}

ClearAll(g) {
    global _imageList, _selectedRow
    if _imageList.Length = 0
        return
    PushUndoState(g)
    g.Progress.Value := 0
    _imageList := []
    _selectedRow := 0
    g.lv.Delete()
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Cleared all"
}

MoveItem(g, dir) {
    if IsTimesheetMode(g)
        return
    global _selectedRow
    if _selectedRow = 0
        return
    row := _selectedRow
    target := row + dir
    if target < 1 || target > _imageList.Length
        return
    PushUndoState(g)
    g.Progress.Value := 0
    tmp := _imageList[row]
    _imageList[row] := _imageList[target]
    _imageList[target] := tmp
    _selectedRow := target
    UpdateListViewRows(g, [row, target])
    SelectRows(g, [target], target)
    RefreshTimeline(g)
    UpdatePreview(g)
}

SyncListViewToModel(g, selectedRows := "", focusRow := 0) {
    currentCount := g.lv.GetCount()
    targetCount := _imageList.Length

    BeginListUpdate(g)
    try {
        while currentCount > targetCount {
            g.lv.Delete(currentCount)
            currentCount -= 1
        }
        while currentCount < targetCount {
            currentCount += 1
            InsertListViewRow(g.lv, currentCount)
        }
        Loop targetCount
            UpdateListViewRow(g, A_Index)
        if IsObject(selectedRows) {
            ClearListViewSelection(g.lv)
            SelectRows(g, selectedRows, focusRow)
        }
    } finally EndListUpdate(g)
}

UpdateListViewRow(g, row) {
    if row < 1 || row > _imageList.Length
        return
    item := _imageList[row]
    EnsureTimesheetFields(item)
    lbl := IsTimesheetMode(g)
        ? ""
        : (item.type = "video" ? (item.frameCount > 0 ? item.frameCount " frames" : "video") : item.exposure)
    tsTotal := GetTimesheetTotalFrames()
    tsLayer := item.tsEnabled ? item.tsLayer : ""
    tsCell := item.tsEnabled ? item.tsCell : ""
    tsStart := item.tsEnabled ? FormatTsFrameDisplay(item.tsStartFrame) : ""
    tsEnd := item.tsEnabled ? FormatTsFrameDisplay(item.tsEndFrame) : ""
    tsDur := item.tsEnabled ? tsTotal : ""
    g.lv.Modify(
        row,
        "",
        row,
        item.name,
        lbl,
        item.HasProp("note") ? item.note : "",
        tsLayer,
        tsCell,
        tsStart,
        tsEnd,
        tsDur
    )
}

UpdateListViewRows(g, rows) {
    if !IsObject(rows) || rows.Length = 0
        return
    SetListViewRedraw(g.lv, false)
    try {
        for row in rows
            UpdateListViewRow(g, row)
    } finally SetListViewRedraw(g.lv, true)
}

InsertListViewRow(lv, row) {
    static LVM_INSERTITEMW := 0x104D
    static LVIF_TEXT := 0x0001
    cbSize := A_PtrSize = 8 ? 88 : 60
    text := Buffer(4, 0)
    NumPut("ushort", 0, text, 0)
    item := Buffer(cbSize, 0)
    NumPut("uint", LVIF_TEXT, item, 0)
    NumPut("int", row - 1, item, 4)
    NumPut("int", 0, item, 8)
    NumPut("ptr", text.Ptr, item, A_PtrSize = 8 ? 24 : 20)
    SendMessage(LVM_INSERTITEMW, 0, item.Ptr, lv.Hwnd)
}

ClearListViewSelection(lv) {
    static LVM_SETITEMSTATE := 0x102B
    static LVIS_FOCUSED := 0x0001
    static LVIS_SELECTED := 0x0002
    cbSize := A_PtrSize = 8 ? 80 : 60
    state := Buffer(cbSize, 0)
    NumPut("uint", 0, state, 12)
    NumPut("uint", LVIS_SELECTED | LVIS_FOCUSED, state, 16)
    SendMessage(LVM_SETITEMSTATE, -1, state.Ptr, lv.Hwnd)
}

SelectRows(g, rows, focusRow := 0) {
    global _selectedRow
    for row in rows {
        if row >= 1 && row <= _imageList.Length
            g.lv.Modify(row, "Select")
    }
    if focusRow >= 1 && focusRow <= _imageList.Length {
        _selectedRow := focusRow
        g.lv.Modify(focusRow, "Focus Vis")
    }
}

SelectRow(g, row) {
    global _selectedRow
    if row = 0 || row > _imageList.Length
        return
    g.Progress.Value := 0
    _selectedRow := row
    item := _imageList[row]
    g.expEdit.Value := item.exposure
    g.noteEdit.Value := item.HasProp("note") ? item.note : ""
    g.lv.Modify(row, "Select Focus Vis")
    UpdatePreview(g)
}

ApplyNote(g) {
    rows := GetSelectedRows(g)
    if rows.Length = 0
        return
    PushUndoState(g)
    g.Progress.Value := 0
    for r in rows
        _imageList[r].note := g.noteEdit.Value
    UpdateListViewRows(g, rows)
    SelectRows(g, rows, _selectedRow)
    g.statText.Value := "Updated note for " rows.Length " item(s)"
}

OnFpsChanged(g) {
    global _imageList
    g.Progress.Value := 0
    rows := []
    fps := RefreshTimelineRaw(g)
    for idx, item in _imageList {
        if item.type != "video"
            continue
        if item.HasProp("durationSec") && item.durationSec > 0 {
            newCount := Max(1, Round(item.durationSec * fps))
            if !item.HasProp("frameCount") || item.frameCount != newCount {
                item.frameCount := newCount
                item.previewFrame := ClampPreviewFrame(item)
                rows.Push(idx)
            }
        }
    }
    if rows.Length > 0
        UpdateListViewRows(g, rows)
    RefreshTimeline(g)
    UpdatePreview(g)
}

OnPreviewFrameChanged(g) {
    global _selectedRow, _imageList
    if _selectedRow < 1 || _selectedRow > _imageList.Length
        return
    item := _imageList[_selectedRow]
    if item.type != "video"
        return
    item.previewFrame := ClampPreviewFrame(item, g.previewFrameSlider.Value)
    UpdatePreview(g)
}

ClampPreviewFrame(item, requested := 0) {
    frameCount := item.HasProp("frameCount") && item.frameCount > 0 ? item.frameCount : 1
    frame := requested > 0 ? requested : (item.HasProp("previewFrame") ? item.previewFrame : 1)
    if frame < 1
        frame := 1
    if frame > frameCount
        frame := frameCount
    return frame
}

GetPreviewCacheDir() {
    global _previewCacheDir
    if !DirExist(_previewCacheDir)
        DirCreate(_previewCacheDir)
    return _previewCacheDir
}

GetVideoPreviewPath(item, frameNo, fps) {
    key := SimpleHash(item.path "|" fps "|" frameNo)
    return GetPreviewCacheDir() "\" key ".png"
}

SimpleHash(text) {
    hash := 0
    Loop Parse, text
        hash := Mod(hash * 131 + Ord(A_LoopField), 2147483647)
    return Format("{:08X}", hash)
}

ExtractVideoPreviewFrame(item, frameNo, fps) {
    global _FFMPEG
    if !FileExist(_FFMPEG)
        return ""
    frameNo := frameNo < 1 ? 1 : frameNo
    fps := fps < 1 ? 1 : fps
    destPath := GetVideoPreviewPath(item, frameNo, fps)
    if FileExist(destPath)
        return destPath

    q := Chr(34)
    seek := (frameNo - 1) / fps
    seekArg := seek > 0 ? "-ss " Format("{:.3f}", seek) " " : ""
    logFile := A_Temp "\NastarxaIC_preview_" A_TickCount ".log"
    args := "-y " seekArg " -i " q item.path q " -frames:v 1 " q destPath q
    result := RunFFmpegLogged(args, logFile)
    try FileDelete(logFile)
    return result = 0 && FileExist(destPath) ? destPath : ""
}

SetPreviewSliderState(g, visible, frameCount := 1, frameNo := 1) {
    frameMax := frameCount > 0 ? frameCount : 1
    g.previewFrameSlider.Opt("Range1-" frameMax)
    g.previewFrameSlider.Value := frameNo < 1 ? 1 : frameNo
    g.previewFrameSlider.Visible := visible
    g.previewFrameSlider.Enabled := visible && frameMax > 1
    g.previewFrameLabel.Visible := visible
    g.previewFrameLabel.Value := visible ? "Frame " g.previewFrameSlider.Value "/" frameMax : ""
}

BuildPreviewPictureValue(path, maxW, maxH) {
    dim := GetImageDimensions(path)
    if dim.w <= 0 || dim.h <= 0 || maxW <= 0 || maxH <= 0
        return "*w" maxW " *h" maxH " " path
    scale := Min(maxW / dim.w, maxH / dim.h)
    if scale <= 0
        scale := 1
    drawW := Max(1, Round(dim.w * scale))
    drawH := Max(1, Round(dim.h * scale))
    return "*w" drawW " *h" drawH " " path
}

UpdatePreview(g) {
    global _selectedRow
    if _selectedRow < 1 || _selectedRow > _imageList.Length {
        g.previewPic.Value := ""
        g.previewText.Value := "No preview"
        SetPreviewSliderState(g, false)
        return
    }
    item := _imageList[_selectedRow]
    pw := g.HasProp("_previewPicW") ? g._previewPicW : 260
    ph := g.HasProp("_previewPicH") ? g._previewPicH : 180
    if item.type = "image" {
        SetPreviewSliderState(g, false)
        g.previewPic.Value := ""
        if !item.HasProp("path") || item.path = "" {
            g.previewText.Value := item.name " (no file)"
            return
        }
        g.previewPic.Value := BuildPreviewPictureValue(item.path, pw, ph)
        dim := GetImageDimensions(item.path)
        warn := GetAspectWarning(g, dim.w, dim.h)
        g.previewText.Value := item.name "`n" dim.w "x" dim.h (warn != "" ? "`n" warn : "")
    } else {
        fps := RefreshTimelineRaw(g)
        frameNo := ClampPreviewFrame(item)
        item.previewFrame := frameNo
        SetPreviewSliderState(g, true, item.frameCount > 0 ? item.frameCount : 1, frameNo)
        g.previewPic.Value := ""
        previewPath := ExtractVideoPreviewFrame(item, frameNo, fps)
        if previewPath != ""
            g.previewPic.Value := BuildPreviewPictureValue(previewPath, pw, ph)
        dim := previewPath != "" ? GetImageDimensions(previewPath) : {w: 0, h: 0}
        g.previewText.Value := item.name
            . "`nFrame " frameNo "/" (item.frameCount > 0 ? item.frameCount : 1)
            . (dim.w > 0 && dim.h > 0 ? "`n" dim.w "x" dim.h : "")
    }
}

GetAspectWarning(g, srcW, srcH) {
    rawW := g.widthEdit.Value
    rawH := g.heightEdit.Value
    w := rawW ~= "^\d+$" ? Integer(rawW) : 0
    h := rawH ~= "^\d+$" ? Integer(rawH) : 0
    if srcW <= 0 || srcH <= 0 || w <= 0 || h <= 0
        return ""
    srcAspect := Round(srcW / srcH, 3)
    outAspect := Round(w / h, 3)
    return Abs(srcAspect - outAspect) > 0.05 ? "Aspect mismatch" : ""
}

ApplyExposure(g, all) {
    if IsTimesheetMode(g)
        return
    if _imageList.Length = 0
        return
    PushUndoState(g)
    g.Progress.Value := 0
    raw := g.expEdit.Value
    val := raw ~= "^\d+$" ? Integer(raw) : 2
    if val < 1
        val := 1
    if all {
        for item in _imageList
            item.exposure := val
        rows := []
        Loop _imageList.Length
            rows.Push(A_Index)
        UpdateListViewRows(g, rows)
        if _selectedRow > 0
            SelectRows(g, [_selectedRow], _selectedRow)
        g.statText.Value := "Applied " val " to all items"
    } else {
        rows := GetSelectedRows(g)
        if rows.Length = 0
            return
        for r in rows
            _imageList[r].exposure := val
        UpdateListViewRows(g, rows)
        SelectRows(g, rows, _selectedRow)
        g.statText.Value := "Applied " val " to " rows.Length " item(s)"
    }
    RefreshTimeline(g)
}

RefreshTimeline(g) {
    if IsTimesheetMode(g) {
        DeduplicateTimesheetCells()
        total := GetTimesheetTotalFrames()
        fps := RefreshTimelineRaw(g)
        dur := total / fps
        g.timeText.Value := "Items: " _imageList.Length "  -  TS frames: " total "  -  Duration: " Format("{:.1f}", dur) "s (" FormatDuration(dur) ")"
        return
    }
    total := 0
    vidCount := 0
    for item in _imageList {
        if item.type = "video" {
            vidCount++
            if item.frameCount > 0
                total += item.frameCount
        } else {
            total += item.exposure
        }
    }
    raw := g.fpsEdit.Value
    fps := raw ~= "^\d+$" ? Integer(raw) : 24
    if fps < 1
        fps := 1
    dur := total / fps
    vidPart := vidCount > 0 ? "  -  Videos: " vidCount : ""
    g.timeText.Value := "Items: " _imageList.Length vidPart "  -  Total frames: " total "  -  Duration: " Format("{:.1f}", dur) "s (" FormatDuration(dur) ")"
}

RefreshTimelineRaw(g) {
    raw := g.fpsEdit.Value
    fps := raw ~= "^\d+$" ? Integer(raw) : 24
    if fps < 1
        fps := 1
    return fps
}

FormatDuration(sec) {
    m := Floor(sec / 60)
    s := Round(Mod(sec, 60))
    return m "m " s "s"
}

PushUndoState(g) {
    global _undoStack, _redoStack, _MAX_UNDO, _isHistoryReplay
    if _isHistoryReplay
        return
    _undoStack.Push(CaptureAppState(g))
    while _undoStack.Length > _MAX_UNDO
        _undoStack.RemoveAt(1)
    _redoStack := []
}

CommitActiveTimesheetPending(force := false) {
    global _activeTimesheetGui
    if !IsObject(_activeTimesheetGui)
        return
    try {
        if !_activeTimesheetGui.HasProp("Hwnd") || !WinExist("ahk_id " _activeTimesheetGui.Hwnd)
            return
    }
    CommitPendingTimesheetFields(_activeTimesheetGui, force)
}

HandleCombinerDelete(g) {
    RemoveSelected(g)
}

HandleCombinerUndo(g) {
    CommitActiveTimesheetPending(true)
    UndoAction(g)
}

HandleCombinerRedo(g) {
    CommitActiveTimesheetPending(true)
    RedoAction(g)
}

CommitTimesheetEditorEnter() {
    global _activeTimesheetGui
    if !IsObject(_activeTimesheetGui)
        return
    try {
        if !_activeTimesheetGui.HasProp("Hwnd") || !WinExist("ahk_id " _activeTimesheetGui.Hwnd)
            return
    }
    if !WinActive("ahk_id " _activeTimesheetGui.Hwnd)
        return
    focused := ControlGetFocus("ahk_id " _activeTimesheetGui.Hwnd)
    if focused = ""
        return
    if focused != _activeTimesheetGui.edCell.ClassNN
        && focused != _activeTimesheetGui.edStart.ClassNN
        && focused != _activeTimesheetGui.edEnd.ClassNN
        && focused != _activeTimesheetGui.btnApplyText.ClassNN
        return
    CommitPendingTimesheetFields(_activeTimesheetGui, true)
}

CaptureAppState(g) {
    global _imageList, _selectedRow, _timesheetLayers
    state := {
        selectedRow: _selectedRow,
        imageList: DeepCloneValue(_imageList),
        timesheetLayers: DeepCloneValue(_timesheetLayers),
        fps: g.fpsEdit.Value,
        width: g.widthEdit.Value,
        height: g.heightEdit.Value,
        outName: g.outEdit.Value,
        fmtGIF: g.chkGIF.Value,
        fmtMP4: g.chkMP4.Value,
        fmtAVI: g.chkAVI.Value,
        fmtWebM: g.chkWebM.Value,
        fmtMOV: g.chkMOV.Value,
        fmtPNG: g.chkPNG.Value,
        fmtSheet: g.chkSheet.Value,
        sheetCount: g.sheetCountEdit.Value,
        timestamp: g.chkTimestamp.Value,
        loop: g.loopEdit.Value,
        crf: g.crfEdit.Value,
        fit: g.fitDDL.Text,
        bg: g.bgEdit.Value,
        bgAlpha: g.bgAlphaEdit.Value,
        outputDir: g.dirEdit.Value,
        audio: g.audioEdit.Value,
        timesheetMode: g.chkTimesheet.Value,
        expEdit: g.expEdit.Value,
        noteEdit: g.noteEdit.Value
    }
    return state
}

DeepCloneValue(value) {
    if !IsObject(value)
        return value
    if value is Array {
        out := []
        for item in value
            out.Push(DeepCloneValue(item))
        return out
    }
    if value is Map {
        out := Map()
        for key, item in value
            out[key] := DeepCloneValue(item)
        return out
    }
    out := {}
    for key, item in value.OwnProps()
        out.%key% := DeepCloneValue(item)
    return out
}

RestoreAppState(g, state) {
    global _imageList, _selectedRow, _isHistoryReplay, _timesheetLayers
    _isHistoryReplay := true
    try {
        _imageList := DeepCloneValue(state.imageList)
        _timesheetLayers := state.HasProp("timesheetLayers") ? DeepCloneValue(state.timesheetLayers) : BuildDefaultTimesheetLayers()
        _selectedRow := state.selectedRow
        g.fpsEdit.Value := state.fps
        g.widthEdit.Value := state.width
        g.heightEdit.Value := state.height
        g.outEdit.Value := state.outName
        g.chkGIF.Value := state.fmtGIF
        g.chkMP4.Value := state.fmtMP4
        g.chkAVI.Value := state.fmtAVI
        g.chkWebM.Value := state.fmtWebM
        g.chkMOV.Value := state.HasProp("fmtMOV") ? state.fmtMOV : 0
        g.chkPNG.Value := state.fmtPNG
        g.chkSheet.Value := state.fmtSheet
        g.sheetCountEdit.Value := state.sheetCount
        g.chkTimestamp.Value := state.timestamp
        g.loopEdit.Value := state.loop
        g.crfEdit.Value := state.crf
        TrySelectDropDownText(g.fitDDL, state.fit)
        g.bgEdit.Value := state.bg
        g.bgAlphaEdit.Value := state.bgAlpha
        g.dirEdit.Value := state.outputDir
        g.audioEdit.Value := state.audio
        g.chkTimesheet.Value := state.timesheetMode
        g.expEdit.Value := state.expEdit
        g.noteEdit.Value := state.noteEdit
        g.btnTimesheet.Enabled := g.chkTimesheet.Value = 1
        ApplyTimesheetModeUI(g)
        if _selectedRow > _imageList.Length
            _selectedRow := _imageList.Length
        selectedRows := _selectedRow > 0 ? [_selectedRow] : []
        SyncListViewToModel(g, selectedRows, _selectedRow)
        RefreshActiveTimesheetGui()
        RefreshTimeline(g)
        UpdatePreview(g)
    } finally _isHistoryReplay := false
}

UndoAction(g) {
    global _undoStack, _redoStack
    if _undoStack.Length = 0
        return
    _redoStack.Push(CaptureAppState(g))
    state := _undoStack.Pop()
    RestoreAppState(g, state)
    g.statText.Value := "Undo"
}

RedoAction(g) {
    global _undoStack, _redoStack
    if _redoStack.Length = 0
        return
    _undoStack.Push(CaptureAppState(g))
    state := _redoStack.Pop()
    RestoreAppState(g, state)
    g.statText.Value := "Redo"
}

GetPrimaryOutputPath(outDir, outName, fmt) {
    switch fmt {
        case "PNGSEQ":
            return outDir "\" outName "_png"
        case "CONTACT":
            return outDir "\" outName ".png"
        default:
            return outDir "\" outName "." FormatExt(fmt)
    }
}

GetContactOutputPath(outDir, outName, partIndex, totalParts) {
    if totalParts <= 1
        return outDir "\" outName ".png"
    return outDir "\" outName "_sheet" Format("{:02d}", partIndex) ".png"
}

GetContactSheetSize(g) {
    raw := g.sheetCountEdit.Value
    count := raw ~= "^\d+$" ? Integer(raw) : 16
    return Max(1, count)
}

BrowseOutputDir(g) {
    dir := FileSelect("D", , "Select output directory")
    if dir != ""
        g.dirEdit.Value := dir
}

PickAudio(g) {
    path := FileSelect(3, , "Select Audio", "Audio (*.mp3; *.wav; *.ogg; *.m4a; *.flac)")
    if path != ""
        g.audioEdit.Value := path
}

CancelGenerate(g) {
    global _cancelGenerate
    _cancelGenerate := true
    g.statText.Value := "Cancel requested..."
}

SavePreset(g) {
    ib := InputBox("Preset name:", "Save Preset")
    if ib.Result != "OK"
        return
    name := ib.Value
    if Trim(name) = ""
        return
    IniWrite(g.fpsEdit.Value, _PRESET_FILE, name, "FPS")
    IniWrite(g.widthEdit.Value, _PRESET_FILE, name, "Width")
    IniWrite(g.heightEdit.Value, _PRESET_FILE, name, "Height")
    IniWrite(g.chkGIF.Value, _PRESET_FILE, name, "FmtGIF")
    IniWrite(g.chkMP4.Value, _PRESET_FILE, name, "FmtMP4")
    IniWrite(g.chkAVI.Value, _PRESET_FILE, name, "FmtAVI")
    IniWrite(g.chkWebM.Value, _PRESET_FILE, name, "FmtWebM")
    IniWrite(g.chkMOV.Value, _PRESET_FILE, name, "FmtMOV")
    IniWrite(g.chkPNG.Value, _PRESET_FILE, name, "FmtPNG")
    IniWrite(g.chkSheet.Value, _PRESET_FILE, name, "FmtSheet")
    IniWrite(g.sheetCountEdit.Value, _PRESET_FILE, name, "SheetCount")
    IniWrite(g.loopEdit.Value, _PRESET_FILE, name, "Loop")
    IniWrite(g.crfEdit.Value, _PRESET_FILE, name, "CRF")
    IniWrite(g.fitDDL.Text, _PRESET_FILE, name, "Fit")
    IniWrite(g.bgEdit.Value, _PRESET_FILE, name, "BG")
    IniWrite(g.bgAlphaEdit.Value, _PRESET_FILE, name, "BGAlpha")
    IniWrite(g.audioEdit.Value, _PRESET_FILE, name, "Audio")
    IniWrite(g.chkTimesheet.Value, _PRESET_FILE, name, "TimesheetMode")
    IniWrite(SerializeTimesheetLayers(), _PRESET_FILE, name, "TsLayers")
    WriteQueueItemsToIni(_PRESET_FILE, name)
    g.statText.Value := "Preset saved: " name
}

LoadPreset(g) {
    global _imageList
    global _selectedRow
    if !FileExist(_PRESET_FILE)
        return
    raw := IniRead(_PRESET_FILE)
    names := []
    for line in StrSplit(raw, "`n", "`r") {
        line := Trim(line)
        if line != ""
            names.Push(line)
    }
    if names.Length = 0
        return
    ib := InputBox("Preset name:`n" JoinText(names, " | "), "Load Preset")
    if ib.Result != "OK"
        return
    sel := ib.Value
    if Trim(sel) = ""
        return
    PushUndoState(g)
    g.fpsEdit.Value := IniRead(_PRESET_FILE, sel, "FPS", "24")
    g.widthEdit.Value := IniRead(_PRESET_FILE, sel, "Width", "1920")
    g.heightEdit.Value := IniRead(_PRESET_FILE, sel, "Height", "1080")
    g.chkGIF.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtGIF", "1"))
    g.chkMP4.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtMP4", "1"))
    g.chkAVI.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtAVI", "0"))
    g.chkWebM.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtWebM", "0"))
    g.chkMOV.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtMOV", "0"))
    g.chkPNG.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtPNG", "0"))
    g.chkSheet.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtSheet", "0"))
    g.sheetCountEdit.Value := IniRead(_PRESET_FILE, sel, "SheetCount", "16")
    g.loopEdit.Value := IniRead(_PRESET_FILE, sel, "Loop", "0")
    g.crfEdit.Value := IniRead(_PRESET_FILE, sel, "CRF", "23")
    TrySelectDropDownText(g.fitDDL, IniRead(_PRESET_FILE, sel, "Fit", "stretch"))
    g.bgEdit.Value := NormalizeHexColor(IniRead(_PRESET_FILE, sel, "BG", "#FFFFFF"))
    g.bgAlphaEdit.Value := IniRead(_PRESET_FILE, sel, "BGAlpha", "FF")
    g.audioEdit.Value := IniRead(_PRESET_FILE, sel, "Audio", "")
    g.chkTimesheet.Value := Integer(IniRead(_PRESET_FILE, sel, "TimesheetMode", "0"))
    LoadTimesheetLayersFromString(IniRead(_PRESET_FILE, sel, "TsLayers", SerializeTimesheetLayers()))
    presetItems := ReadQueueItemsFromIni(_PRESET_FILE, sel)
    if presetItems.Length > 0 {
        _imageList := presetItems
        SyncLinkedDuplicateCells()
        NormalizeTimesheetLayerTimings()
        _selectedRow := 0
        SyncListViewToModel(g)
        RefreshTimeline(g)
    }
    g.btnTimesheet.Enabled := g.chkTimesheet.Value = 1
    ApplyTimesheetModeUI(g)
    OnFpsChanged(g)
    UpdatePreview(g)
    g.statText.Value := "Preset loaded: " sel
}

JoinText(arr, sep := ", ") {
    out := ""
    for i, val in arr {
        if i > 1
            out .= sep
        out .= val
    }
    return out
}

TrySelectDropDownText(ctrl, text) {
    static CB_GETCOUNT := 0x146
    static CB_GETLBTEXTLEN := 0x149
    static CB_GETLBTEXT := 0x148

    count := SendMessage(CB_GETCOUNT, 0, 0, ctrl.Hwnd)
    if count = "" || count < 1 {
        ctrl.Choose(1)
        return
    }

    Loop count {
        idx := A_Index - 1
        len := SendMessage(CB_GETLBTEXTLEN, idx, 0, ctrl.Hwnd)
        if len < 0
            continue
        buf := Buffer((len + 1) * 2, 0)
        SendMessage(CB_GETLBTEXT, idx, buf.Ptr, ctrl.Hwnd)
        itemText := StrGet(buf, "UTF-16")
        if itemText = text {
            ctrl.Choose(A_Index)
            return
        }
    }
    ctrl.Choose(1)
}

FormatTsFrameDisplay(val) {
    if val = ""
        return ""
    n := Integer(val)
    return Format("{:02d}", n)
}

RefreshActiveTimesheetGui() {
    global _activeTimesheetGui
    if !IsObject(_activeTimesheetGui)
        return
    try {
        if !_activeTimesheetGui.HasProp("Hwnd") || !WinExist("ahk_id " _activeTimesheetGui.Hwnd)
            return
    }
    ReloadTimesheetList(_activeTimesheetGui)
    LoadTimesheetEditorFromRows(_activeTimesheetGui)
}

LoadLastProject(g) {
    if !FileExist(_LAST_PROJECT_FILE)
        return
    path := Trim(FileRead(_LAST_PROJECT_FILE))
    if path != "" && FileExist(path)
        LoadProjectFromPath(g, path)
}

CleanupTemp() {
    global _tempDir, _previewCacheDir
    if _tempDir != "" && DirExist(_tempDir)
        DirDelete(_tempDir, true)
    if DirExist(_previewCacheDir)
        DirDelete(_previewCacheDir, true)
}

NormalizeHexColor(raw) {
    color := Trim(raw)
    color := RegExReplace(color, "^#")
    if RegExMatch(color, "i)^[0-9a-f]{8}$")
        return "#" StrUpper(color)
    return RegExMatch(color, "i)^[0-9a-f]{6}$") ? "#" StrUpper(color) : "#FFFFFF"
}

GetBGColor(g) {
    base := NormalizeHexColor(g.bgEdit.Value)
    alpha := Trim(g.bgAlphaEdit.Value)
    alpha := RegExReplace(alpha, "^#")
    if RegExMatch(alpha, "i)^[0-9a-f]{2}$")
        return SubStr(base, 1, 7) StrUpper(alpha)
    return base
}

GetCheckedFormats(g) {
    fmts := []
    if g.chkGIF.Value
        fmts.Push("GIF")
    if g.chkMP4.Value
        fmts.Push("MP4")
    if g.chkAVI.Value
        fmts.Push("AVI")
    if g.chkWebM.Value
        fmts.Push("WebM")
    if g.chkMOV.Value
        fmts.Push("MOV")
    if g.chkPNG.Value
        fmts.Push("PNGSEQ")
    if g.chkSheet.Value
        fmts.Push("CONTACT")
    return fmts
}

FormatSupportsTrueAlpha(fmt) {
    return fmt = "MOV" || fmt = "PNGSEQ" || fmt = "CONTACT"
}

IsTimesheetMode(g) {
    return g.HasProp("chkTimesheet") && g.chkTimesheet.Value = 1
}

ToggleTimesheetMode(g) {
    PushUndoState(g)
    g.Progress.Value := 0
    g.btnTimesheet.Enabled := g.chkTimesheet.Value = 1
    ApplyTimesheetModeUI(g)
    SyncListViewToModel(g)
    RefreshTimeline(g)
}

GetTimesheetTotalFrames() {
    total := 0
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled && item.type = "image" && item.tsEndFrame > total
            total := item.tsEndFrame
    }
    return total
}

GetTimesheetLayerRank(layer) {
    for idx, name in GetTimesheetLayerOptions() {
        if name = layer
            return idx
    }
    return 999
}

GetTimesheetItemsForFrame(frameNo) {
    active := []
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.type != "image" || !item.tsEnabled
            continue
        if frameNo >= item.tsStartFrame && frameNo <= item.tsEndFrame
            active.Push(item)
    }
    Loop active.Length {
        swapped := false
        Loop active.Length - 1 {
            left := GetTimesheetLayerRank(active[A_Index].tsLayer)
            right := GetTimesheetLayerRank(active[A_Index + 1].tsLayer)
            if left > right {
                tmp := active[A_Index]
                active[A_Index] := active[A_Index + 1]
                active[A_Index + 1] := tmp
                swapped := true
            }
        }
        if !swapped
            break
    }
    return active
}

GetFFmpegColorValue(bgColor) {
    hex := SubStr(NormalizeHexColor(bgColor), 2)
    if StrLen(bgColor) = 9 {
        alphaHex := SubStr(bgColor, 8, 2)
        alphaVal := Integer("0x" alphaHex) / 255
        return "0x" SubStr(hex, 1, 6) "@" Format("{:.3f}", alphaVal)
    }
    return "0x" SubStr(hex, 1, 6)
}

BuildTimesheetCompositeCmd(activeItems, w, h, fitMode, bgColor, outPath) {
    q := Chr(34)
    args := "-y -f lavfi -i color=c=" GetFFmpegColorValue(bgColor) ":s=" w "x" h ":d=1"
    for item in activeItems
        args .= " -i " q item.path q

    filter := "[0:v]format=rgba[b0];"
    scaleFilter := BuildTimesheetScaleFilter(w, h, fitMode)
    overlayBase := "b0"
    for idx, item in activeItems {
        inIdx := idx
        layerLabel := "l" idx
        outLabel := "b" idx
        if scaleFilter != ""
            filter .= "[" inIdx ":v]" scaleFilter ",format=rgba[" layerLabel "];"
        else
            filter .= "[" inIdx ":v]format=rgba[" layerLabel "];"
        filter .= "[" overlayBase "][" layerLabel "]overlay=0:0:format=auto[" outLabel "];"
        overlayBase := outLabel
    }

    return args " -filter_complex " q filter q " -map " q "[" overlayBase "]" q " -frames:v 1 " q outPath q
}

CreateBlankFrame(destPath, w, h, bgColor) {
    if w <= 0 || h <= 0
        return false
    colorVal := GetFFmpegColorValue(bgColor)
    args := "-y -f lavfi -i color=c=" colorVal ":s=" w "x" h ":d=1 -frames:v 1 " Chr(34) destPath Chr(34)
    return RunFFmpegLogged(args, A_Temp "\NastarxaIC_blank_" A_TickCount ".log") = 0 && FileExist(destPath)
}

BuildTimesheetScaleFilter(w, h, fitMode) {
    if w <= 0 || h <= 0
        return ""
    transparent := "0x00000000"
    switch fitMode {
        case "contain", "pad":
            return "scale=" w ":" h ":force_original_aspect_ratio=decrease,pad=" w ":" h ":(ow-iw)/2:(oh-ih)/2:" transparent
        case "cover":
            return "scale=" w ":" h ":force_original_aspect_ratio=increase,crop=" w ":" h
        default:
            return "scale=" w ":" h
    }
}

PrepareTimesheetFrames(g, tempDir, w, h, fitMode, bgColor) {
    totalFrames := GetTimesheetTotalFrames()
    if totalFrames < 1
        return 0
    if w <= 0 || h <= 0 {
        MsgBox "Timesheet mode needs a valid canvas width and height.", "Invalid Canvas", "IconX"
        return -1
    }
    frameNum := 0
    Loop totalFrames {
        sheetFrame := A_Index
        if _cancelGenerate
            break
        outFrame := tempDir "\" Format("{:06d}.png", frameNum)
        active := GetTimesheetItemsForFrame(sheetFrame)
        ok := active.Length > 0
            ? (RunFFmpegLogged(BuildTimesheetCompositeCmd(active, w, h, fitMode, bgColor, outFrame), tempDir "\timesheet_compose.log", tempDir) = 0 && FileExist(outFrame))
            : CreateBlankFrame(outFrame, w, h, bgColor)
        if !ok
            return -1
        frameNum += 1
        g.Progress.Value := Round(100 * sheetFrame / totalFrames)
        g.statText.Value := "Preparing timesheet frames... " sheetFrame "/" totalFrames
    }
    return frameNum
}

Generate(g) {
    global _tempDir, _cancelGenerate
    if _imageList.Length = 0 {
        g.statText.Value := "No images to process"
        MsgBox "Add images to the list first.", "No Images", "Icon!"
        return
    }
    if !FileExist(_FFMPEG) {
        g.statText.Value := "ffmpeg not found at " _FFMPEG
        MsgBox "ffmpeg not found at:`n" _FFMPEG, "Error", "IconX"
        return
    }

    fmts := GetCheckedFormats(g)
    if fmts.Length = 0 {
        MsgBox "Select at least one output format.", "No Format", "Icon!"
        return
    }
    if g.chkMOV.Value && !FFmpegHasEncoder(GetFFmpegPathForFormat("MOV"), "qtrle") {
        MsgBox "QuickTime MOV export needs an ffmpeg build with the qtrle encoder.", "MOV Export Unavailable", "IconX"
        return
    }
    if IsTimesheetMode(g) {
        tsTotal := GetTimesheetTotalFrames()
        if tsTotal < 1 {
            g.statText.Value := "Timesheet has no enabled frames"
            MsgBox "Timesheet mode needs at least one enabled image with a valid Start/End frame.", "Timesheet Empty", "Icon!"
            return
        }
        for item in _imageList {
            EnsureTimesheetFields(item)
            if item.type = "video" && item.tsEnabled {
                MsgBox "Timesheet mode currently supports still-image layers only. Disable TS for video rows or remove them from the setup.", "Timesheet Mode", "Icon!"
                return
            }
        }
    }

    outDir := g.dirEdit.Value
    if outDir = ""
        outDir := _OUTPUT_DIR
    try DirCreate(outDir)
    if !DirExist(outDir) {
        g.statText.Value := "Output folder is not available"
        MsgBox "Output folder could not be created:`n" outDir, "Invalid Output Folder", "IconX"
        return
    }
    outName := g.outEdit.Value
    if outName = ""
        outName := "animation"
    if g.chkTimestamp.Value {
        ts := FormatTime(, "yyyyMMdd_HHmmss")
        outName .= "_" ts
    }

    q := Chr(34)
    raw := g.fpsEdit.Value
    fps := raw ~= "^\d+$" ? Integer(raw) : 24
    if fps < 1
        fps := 1

    rawW := g.widthEdit.Value
    rawH := g.heightEdit.Value
    w := rawW ~= "^\d+$" ? Integer(rawW) : 0
    h := rawH ~= "^\d+$" ? Integer(rawH) : 0
    fitMode := g.fitDDL.Text
    bgColor := GetBGColor(g)
    audioPath := g.audioEdit.Value
    _cancelGenerate := false

    if StrLen(bgColor) = 9 && SubStr(bgColor, 8, 2) != "FF" {
        alphaUnsupported := []
        for fmt in fmts {
            if !FormatSupportsTrueAlpha(fmt)
                alphaUnsupported.Push(fmt)
        }
        if alphaUnsupported.Length > 0 {
            MsgBox "BG alpha will be preserved only for MOV, PNG, and Contact Sheet.`n`nThese selected formats do not keep true alpha:`n" JoinText(alphaUnsupported, ", "), "Alpha Format Warning", "Icon!"
        }
    }

    tempDir := A_Temp "\NastarxaIC_" A_TickCount
    DirCreate(tempDir)
    _tempDir := tempDir

    g.btnGen.Enabled := false
    g.btnCancel.Enabled := true
    g.statText.Value := "Preparing frames..."
    g.Progress.Value := 0
    g.Progress.Visible := true

    SetTimer () => (
        RunGenerate(g, outDir, outName, fmts, fps, w, h, fitMode, bgColor, audioPath, tempDir),
        SetTimer(, 0)
    ), -1
}

RunGenerate(g, outDir, outName, fmts, fps, w, h, fitMode, bgColor, audioPath, tempDir) {
    global _tempDir, _cancelGenerate, _lastPrepareError
    processed := 0
    frameNum := 0
    q := Chr(34)
    stillDir := tempDir "\still"
    DirCreate(stillDir)

    if IsTimesheetMode(g) {
        frameNum := PrepareTimesheetFrames(g, tempDir, w, h, fitMode, bgColor)
        if frameNum < 0 {
            try DirDelete(tempDir, true)
            if _tempDir = tempDir
                _tempDir := ""
            g.statText.Value := "Failed to build timesheet frames"
            g.Progress.Visible := false
            g.btnGen.Enabled := true
            g.btnCancel.Enabled := false
            MsgBox "Failed to compose one or more timesheet frames. Check that assigned files still exist and can be read by ffmpeg.", "Timesheet Error", "IconX"
            return
        }
    } else {

        for item in _imageList {
            if _cancelGenerate
                break
            if item.type = "video" {
                vidDir := tempDir "\v" A_Index
                DirCreate(vidDir)
                vidPattern := Chr(34) vidDir "\%06d.png" Chr(34)
                RunFFmpegLogged("-i " Chr(34) item.path Chr(34) " -vf " Chr(34) "fps=" fps Chr(34) " " vidPattern, tempDir "\video_extract.log", tempDir)
                Loop Files, vidDir "\*.png", "F" {
                    dest := tempDir "\" Format("{:06d}.png", frameNum)
                    try FileMove(A_LoopFileFullPath, dest, 1)
                    frameNum++
                }
            } else {
                srcFrame := stillDir "\" Format("{:06d}.png", processed)
                if !PrepareStillFrame(item.path, srcFrame) {
                    g.statText.Value := "Failed to read image: " item.name
                    MsgBox "Failed to prepare image:`n" item.path "`n`n" (_lastPrepareError != "" ? _lastPrepareError : "Unknown ffmpeg/image conversion error."), "Image Read Error", "IconX"
                    continue
                }
                Loop item.exposure {
                    dest := tempDir "\" Format("{:06d}.png", frameNum)
                    try FileCopy(srcFrame, dest, 1)
                    frameNum++
                }
            }
            processed++
            pct := Round(100 * processed / _imageList.Length)
            g.Progress.Value := pct
            g.statText.Value := "Preparing frames... " processed "/" _imageList.Length
        }
    }

    if _cancelGenerate {
        try DirDelete(tempDir, true)
        if _tempDir = tempDir
            _tempDir := ""
        g.statText.Value := "Cancelled"
        g.Progress.Visible := false
        g.btnGen.Enabled := true
        g.btnCancel.Enabled := false
        return
    }

    if frameNum = 0 {
        try DirDelete(tempDir, true)
        if _tempDir = tempDir
            _tempDir := ""
        g.statText.Value := "No frames were prepared"
        g.Progress.Visible := false
        g.btnGen.Enabled := true
        g.btnCancel.Enabled := false
        extra := _lastPrepareError != "" ? "`n`nLast error:`n" _lastPrepareError : ""
        MsgBox "No frames were prepared. Check that the selected files still exist and ffmpeg can read the video inputs." extra, "Nothing Generated", "Icon!"
        return
    }

    successCount := 0
    generatedCount := 0
    failCount := 0

    loopVal := 0
    rawLoop := g.loopEdit.Value
    if rawLoop ~= "^\d+$"
        loopVal := Integer(rawLoop)
    sheetSize := GetContactSheetSize(g)
    crf := 23
    rawCrf := g.crfEdit.Value
    if rawCrf ~= "^\d+$"
        crf := Integer(rawCrf)

    for fmt in fmts {
        outPath := GetPrimaryOutputPath(outDir, outName, fmt)
        g.statText.Value := "Encoding " fmt "..."

        if fmt = "PNGSEQ" {
            seqDir := outPath
            DirCreate(seqDir)
            cmd := BuildPngSequenceCmd(w, h, fitMode, bgColor, tempDir, seqDir)
            errLog := tempDir "\ffmpeg_err.log"
            ffmpegPath := GetFFmpegPathForFormat(fmt)
            result := RunFFmpegLogged(cmd, errLog, tempDir, ffmpegPath)
            if result = 0 {
                successCount++
                generatedCount++
            } else {
                failCount++
                errText := ""
                try errText := FileRead(errLog)
                errMsg := errText != "" ? errText : "exit code " result
                MsgBox "Failed to encode " fmt ".`n" errMsg, "ffmpeg Error", "IconX"
            }
            continue
        }
        if fmt = "CONTACT" {
            totalParts := Ceil(frameNum / sheetSize)
            partSuccess := true
            Loop totalParts {
                partIndex := A_Index
                startNum := (partIndex - 1) * sheetSize
                partFrames := Min(sheetSize, frameNum - startNum)
                contactOut := GetContactOutputPath(outDir, outName, partIndex, totalParts)
                cmd := BuildContactSheetCmd(fps, w, h, fitMode, bgColor, tempDir, contactOut, partFrames, startNum)
                errLog := tempDir "\ffmpeg_err.log"
                result := RunFFmpegLogged(cmd, errLog, tempDir, GetFFmpegPathForFormat(fmt))
                if result != 0 {
                    partSuccess := false
                    failCount++
                    errText := ""
                    try errText := FileRead(errLog)
                    errMsg := errText != "" ? errText : "exit code " result
                    MsgBox "Failed to encode " fmt ".`n" errMsg, "ffmpeg Error", "IconX"
                    break
                }
                generatedCount++
            }
            if partSuccess
                successCount++
            continue
        } else {
            cmd := BuildFFmpegCmd(fmt, fps, w, h, fitMode, bgColor, loopVal, crf, audioPath, tempDir, outPath)
        }
        errLog := tempDir "\ffmpeg_err.log"
        ffmpegPath := GetFFmpegPathForFormat(fmt)
        result := RunFFmpegLogged(cmd, errLog, tempDir, ffmpegPath)

        if result = 0 {
            successCount++
            generatedCount++
        } else {
            failCount++
            errText := ""
            try errText := FileRead(errLog)
            errMsg := errText != "" ? errText : "exit code " result
            MsgBox "Failed to encode " fmt ".`n" errMsg, "ffmpeg Error", "IconX"
        }
    }

    try DirDelete(tempDir, true)
    if _tempDir = tempDir
        _tempDir := ""

    if successCount > 0 {
        g.statText.Value := "Done: " generatedCount " file(s) generated"
        g.Progress.Value := 100
    }
    if failCount > 0 {
        g.statText.Value .= " (" failCount " failed)"
        g.Progress.Value := 0
    }
    if successCount > 0 && failCount = 0 {
        firstFmt := fmts[1]
        lastOut := firstFmt = "CONTACT" && Ceil(frameNum / GetContactSheetSize(g)) > 1
            ? outDir
            : GetPrimaryOutputPath(outDir, outName, firstFmt)
        try Run(q lastOut q)
    }

    g.btnGen.Enabled := true
    g.btnCancel.Enabled := false
}

PrepareStillFrame(path, destPath) {
    global _lastPrepareError
    _lastPrepareError := ""
    if !FileExist(path) {
        _lastPrepareError := "Input file does not exist."
        return false
    }
    SplitPath(path, , , &ext)
    ext := StrLower(ext)
    if ext = "png" {
        try {
            FileCopy(path, destPath, 1)
            return true
        } catch as err {
            _lastPrepareError := err.Message
        }
    }
    logFile := A_Temp "\NastarxaIC_prepare_" A_TickCount ".log"
    try FileDelete(logFile)
    try {
        args := "-y -i " Chr(34) path Chr(34) " -frames:v 1 -update 1 -f image2 " Chr(34) destPath Chr(34)
        result := RunFFmpegLogged(args, logFile)
        if result = 0 && FileExist(destPath) {
            try FileDelete(logFile)
            return true
        }
        if FileExist(logFile)
            _lastPrepareError := Trim(FileRead(logFile))
        if _lastPrepareError = ""
            _lastPrepareError := "ffmpeg exited with code " result
    } catch as err {
        _lastPrepareError := err.Message
    }
    try FileDelete(logFile)
    return false
}

RunFFmpegLogged(args, logFile, workDir := "", ffmpegPath := "") {
    runner := A_Temp "\NastarxaIC_runffmpeg_" A_TickCount ".bat"
    try FileDelete(logFile)
    argsSafe := StrReplace(args, "%", "%%")
    toolPath := ffmpegPath != "" ? ffmpegPath : _FFMPEG
    bat := "@echo off`r`n"
        . Chr(34) toolPath Chr(34) " " argsSafe " 1>" Chr(34) logFile Chr(34) " 2>&1`r`n"
        . "exit /b %errorlevel%`r`n"
    FileAppend(bat, runner)
    result := workDir != "" ? RunWait(Chr(34) runner Chr(34), workDir, "Hide") : RunWait(Chr(34) runner Chr(34), , "Hide")
    try FileDelete(runner)
    return result
}

BuildScaleFilter(w, h, fitMode, bgColor) {
    if w <= 0 || h <= 0
        return ""
    bg := "0x" SubStr(bgColor, 2)
    switch fitMode {
        case "contain":
            return "scale=" w ":" h ":force_original_aspect_ratio=decrease,pad=" w ":" h ":(ow-iw)/2:(oh-ih)/2:" bg
        case "cover":
            return "scale=" w ":" h ":force_original_aspect_ratio=increase,crop=" w ":" h
        case "pad":
            return "scale=" w ":" h ":force_original_aspect_ratio=decrease,pad=" w ":" h ":(ow-iw)/2:(oh-ih)/2:" bg
        default:
            return "scale=" w ":" h
    }
}

BuildAlphaScaleFilter(w, h, fitMode) {
    if w <= 0 || h <= 0
        return ""
    transparent := "0x00000000"
    switch fitMode {
        case "contain", "pad":
            return "scale=" w ":" h ":force_original_aspect_ratio=decrease,pad=" w ":" h ":(ow-iw)/2:(oh-ih)/2:" transparent
        case "cover":
            return "scale=" w ":" h ":force_original_aspect_ratio=increase,crop=" w ":" h
        default:
            return "scale=" w ":" h
    }
}

BuildPngSequenceCmd(w, h, fitMode, bgColor, inputDir, outputDir) {
    q := Chr(34)
    inPattern := q inputDir "\%06d.png" q
    outPattern := q outputDir "\%06d.png" q
    scaleFilter := BuildScaleFilter(w, h, fitMode, bgColor)
    args := "-y -i " inPattern
    if scaleFilter != ""
        args .= " -vf " q scaleFilter ",format=rgba" q
    else
        args .= " -vf " q "format=rgba" q
    args .= " -pix_fmt rgba " outPattern
    return args
}

BuildVideoEncodeFilter(scaleFilter := "") {
    evenFilter := "pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0"
    if scaleFilter = ""
        return evenFilter
    return scaleFilter "," evenFilter
}

BuildFFmpegCmd(fmt, fps, w, h, fitMode, bgColor, loopVal, crf, audioPath, inputDir, outputPath) {
    q := Chr(34)
    inPattern := q inputDir "\%06d.png" q
    out := q outputPath q
    scaleFilter := BuildScaleFilter(w, h, fitMode, bgColor)
    alphaScaleFilter := BuildAlphaScaleFilter(w, h, fitMode)
    videoFilter := BuildVideoEncodeFilter(scaleFilter)
    audioArgs := ""
    if (fmt = "MP4" || fmt = "WebM" || fmt = "MOV") && audioPath != "" && FileExist(audioPath)
        audioArgs := " -i " q audioPath q " -shortest"
    switch fmt {
        case "GIF":
            gifLoop := loopVal > 0 ? loopVal : 0
            filter := q "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" q
            if scaleFilter != ""
                filter := q scaleFilter ",split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" q
            cmd1 := "-y -framerate " fps " -i " inPattern " -vf " filter " -loop " gifLoop " " out
        case "MP4":
            cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -vf " q videoFilter q " -c:v libx264 -pix_fmt yuv420p -crf " crf " -movflags +faststart " out
        case "AVI":
            cmd1 := "-y -framerate " fps " -i " inPattern " -vf " q videoFilter q " -c:v libx264 -pix_fmt yuv420p -crf " crf " " out
        case "WebM":
            cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -vf " q videoFilter q " -c:v libvpx -pix_fmt yuv420p -auto-alt-ref 0 -b:v 1M -crf " crf " " out
        case "MOV":
            movAudio := audioArgs != "" ? " -c:a pcm_s16le" : ""
            cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -c:v qtrle -pix_fmt argb" movAudio " " out
            if alphaScaleFilter != ""
                cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -vf " q alphaScaleFilter q " -c:v qtrle -pix_fmt argb" movAudio " " out
        default:
            cmd1 := "-y -framerate " fps " -i " inPattern " " out
            if scaleFilter != ""
                cmd1 := "-y -framerate " fps " -i " inPattern " -vf " q scaleFilter q " " out
    }
    return cmd1
}

BuildContactSheetCmd(fps, w, h, fitMode, bgColor, inputDir, outputPath, frameCount := 16, startNum := 0) {
    q := Chr(34)
    inPattern := q inputDir "\%06d.png" q
    out := q outputPath q
    cols := Ceil(Sqrt(Max(frameCount, 1)))
    rows := Ceil(frameCount / cols)
    tileW := w > 0 ? Max(1, w // cols) : 320
    tileH := h > 0 ? Max(1, h // rows) : 180
    scaleFilter := BuildScaleFilter(tileW, tileH, "contain", bgColor)
    vf := scaleFilter != "" ? scaleFilter ",format=rgba,tile=" cols "x" rows : "format=rgba,tile=" cols "x" rows
    return "-y -framerate " fps " -start_number " startNum " -i " inPattern " -vf " q vf q " -frames:v 1 -pix_fmt rgba " out
}


ApplyLayout(g, aW, aH) {
    leftX := 14
    gap := 20
    rightW := 392
    rightX := aW - rightW - 14
    leftW := rightX - leftX - gap
    if leftW < 620 {
        leftW := 620
        rightX := leftX + leftW + gap
    }

    btnY := 36
    lvY := 68
    bottomY := aH - 176
    noteY := aH - 136
    stY    := aH - 102    
    prY    := aH - 76 

    lvH := bottomY - lvY - 14
    if lvH < 180
        lvH := 180

    g.lblList.Move(leftX, 12)
    g.btnAdd.Move(leftX, btnY, 78)
    g.btnAddFolder.Move(leftX + 84, btnY, 70)
    g.btnRemove.Move(leftX + 160, btnY, 64)
    g.btnDup.Move(leftX + 230, btnY, 52)
    g.btnClear.Move(leftX + 288, btnY, 48)
    g.btnUp.Move(leftX + 344, btnY, 28)
    g.btnDown.Move(leftX + 376, btnY, 28)
    g.btnSort.Move(leftX + 412, btnY, 42)
    g.btnRev.Move(leftX + 460, btnY, 46)
    g.btnSave.Move(leftX + 514, btnY, 48)
    g.btnLoad.Move(leftX + 568, btnY, 48)
    g.btnGuide.Move(leftX + 622, btnY, 56)

    g.lv.Move(leftX, lvY, leftW, lvH)
    fixedColsW := 35 + 50 + 72 + 48 + 52 + 52 + 58
    nameW := leftW - fixedColsW - 100
    if nameW < 210
        nameW := 210
    noteColW := leftW - fixedColsW - nameW
    if noteColW < 100
        noteColW := 100
    UpdateListViewColumns(g, nameW, noteColW)

    g.lblExposure.Move(leftX, bottomY + 4)
    g.expEdit.Move(leftX + 72, bottomY, 54)
    g.btnExp1.Move(leftX + 136, bottomY, 28)
    g.btnExp2.Move(leftX + 168, bottomY, 28)
    g.btnExp3.Move(leftX + 200, bottomY, 28)
    g.btnExp4.Move(leftX + 232, bottomY, 28)
    g.btnExp5.Move(leftX + 264, bottomY, 28)
    g.btnExp6.Move(leftX + 296, bottomY, 28)
    g.btnApplyExp.Move(leftX + 332, bottomY, 52)
    g.btnApplyAll.Move(leftX + 390, bottomY, 44)

    ; Preset buttons (on Exposure row)
    g.btnPresetSave.Move(leftX + 442, bottomY, 90, 22)
    g.btnPresetLoad.Move(leftX + 540, bottomY, 90, 22)
    g.btnRecent.Move(leftX + 638, bottomY, 94, 22)

    g.lblNote.Move(leftX, noteY + 4)
    noteW := leftW - 150
    if noteW < 180
        noteW := 180
    g.noteEdit.Move(leftX + 72, noteY, noteW)
    g.btnApplyNote.Move(leftX + 82 + noteW, noteY, 54)

    g.statText.Move(leftX, stY, leftW - 8, 22)
    g.Progress.Move(leftX, prY, leftW, 10)

    labelW := 46
    row1Y := 32
    row2Y := 68
    row3Y := 124
    row4Y := 156
    row5Y := 188
    row7Y := 226

    g.lblOutput.Move(rightX, 12)

    g.lblFps.Move(rightX, row1Y + 4)
    g.fpsEdit.Move(rightX + labelW, row1Y, 48)
    g.lblLoop.Move(rightX + 104, row1Y + 4)
    g.loopEdit.Move(rightX + 146, row1Y, 46)
    g.lblQuality.Move(rightX + 206, row1Y + 4)
    g.crfEdit.Move(rightX + 262, row1Y, 44)
    g.lblQualityHint.Move(rightX + 314, row1Y + 4, 76)

    g.lblFormats.Move(rightX, row2Y + 2)
    g.chkGIF.Move(rightX + labelW, row2Y, 54)
    g.chkMP4.Move(rightX + 108, row2Y, 56)
    g.chkAVI.Move(rightX + 168, row2Y, 50)
    g.chkWebM.Move(rightX + 224, row2Y, 66)
    g.chkMOV.Move(rightX + 294, row2Y, 58)
    g.chkPNG.Move(rightX + labelW, row2Y + 26, 54)
    g.chkSheet.Move(rightX + 108, row2Y + 26, 62)
    g.sheetCountEdit.Move(rightX + 176, row2Y + 26, 48)
    g.lblSheetCount.Move(rightX + 232, row2Y + 30, 100)

    g.lblSize.Move(rightX, row3Y + 4)
    g.widthEdit.Move(rightX + labelW, row3Y, 74)
    g.lblSizeX.Move(rightX + 128, row3Y + 4)
    g.heightEdit.Move(rightX + 146, row3Y, 74)
    g.lblFit.Move(rightX + 234, row3Y + 4)
    g.fitDDL.Move(rightX + 260, row3Y, 96)

    g.lblFilename.Move(rightX, row4Y + 4)
    g.outEdit.Move(rightX + labelW, row4Y, 136)
    g.chkTimestamp.Move(rightX + 191, row4Y + 2, 55)
    g.chkTimesheet.Move(rightX + 250, row4Y + 2, 38)
    g.btnTimesheet.Move(rightX + 288, row4Y, 72, 24)

    g.lblBg.Move(rightX, row5Y + 4)
    g.bgEdit.Move(rightX + labelW, row5Y, 60)
    g.lblBgAlpha.Move(rightX + labelW + 69, row5Y + 4)
    g.bgAlphaEdit.Move(rightX + labelW + 84, row5Y, 36)
    g.lblAudio.Move(rightX + 178, row5Y + 4)
    g.audioEdit.Move(rightX + 214, row5Y, 144)
    g.btnAudio.Move(rightX + 364, row5Y, 28)

    g.lblPreview.Move(rightX, row7Y + 4)
    previewY := row7Y + 24
    previewW := rightW
    previewH := aH - previewY - 176
    if previewH < 150
        previewH := 150
    sliderH := 24
    picH := previewH - sliderH - 8
    if picH < 118
        picH := 118
    infoW := 126
    picW := previewW - infoW - 12
    if picW < 210 {
        picW := previewW
        infoW := 0
    }
    sliderY := previewY + picH + 8
    g.previewPic.Move(rightX, previewY, picW, picH)
    g._previewPicW := picW
    g._previewPicH := picH
    g.previewFrameSlider.Move(rightX, sliderY, picW, sliderH)
    if infoW > 0 {
        g.previewText.Move(rightX + picW + 12, previewY + 6, infoW, picH - 28)
        g.previewFrameLabel.Move(rightX + picW + 12, sliderY + 2, infoW, 18)
    } else {
        g.previewText.Move(rightX, sliderY + sliderH + 6, previewW, 34)
        g.previewFrameLabel.Move(rightX, previewY + 6, previewW, 18)
    }

    tlY := sliderY + sliderH + 14
    if tlY > aH - 112
        tlY := aH - 112

    g.lblTimeline.Move(rightX, tlY)
    g.timeText.Move(rightX, tlY + 22, rightW, 22)

    ; Save To (between timeline and generate)
    saveToY := tlY + 56
    g.lblOutputTo.Move(rightX, saveToY)
    g.dirEdit.Move(rightX + 52, saveToY - 4, rightW - 92)
    g.btnBrowse.Move(rightX + rightW - 34, saveToY - 4, 28)

    genY := aH - 100                     ; align with left panel progress bar
    if genY < saveToY + 28              ; ensure below save to row
        genY := saveToY + 28
    g.btnGen.Move(rightX, genY, 130, 34)
    g.btnCancel.Move(rightX + 138, genY, 114, 34)
    g.btnOpenFolder.Move(rightX + 260, genY, 132, 34)
}

UpdateListViewColumns(g, nameW, noteColW) {
    changed := false
    if !g.HasProp("_lvCol1") || g._lvCol1 != 35 {
        g.lv.ModifyCol(1, 35)
        g._lvCol1 := 35
        changed := true
    }
    if !g.HasProp("_lvCol2") || g._lvCol2 != nameW {
        g.lv.ModifyCol(2, nameW)
        g._lvCol2 := nameW
        changed := true
    }
    if !g.HasProp("_lvCol3") || g._lvCol3 != 50 {
        g.lv.ModifyCol(3, 50)
        g._lvCol3 := 50
        changed := true
    }
    if !g.HasProp("_lvCol4") || g._lvCol4 != noteColW {
        g.lv.ModifyCol(4, noteColW)
        g._lvCol4 := noteColW
        changed := true
    }
    if !g.HasProp("_lvCol5") || g._lvCol5 != 72 {
        g.lv.ModifyCol(5, 72)
        g._lvCol5 := 72
        changed := true
    }
    if !g.HasProp("_lvCol6") || g._lvCol6 != 48 {
        g.lv.ModifyCol(6, 48)
        g._lvCol6 := 48
        changed := true
    }
    if !g.HasProp("_lvCol7") || g._lvCol7 != 52 {
        g.lv.ModifyCol(7, 52)
        g._lvCol7 := 52
        changed := true
    }
    if !g.HasProp("_lvCol8") || g._lvCol8 != 52 {
        g.lv.ModifyCol(8, 52)
        g._lvCol8 := 52
        changed := true
    }
    if !g.HasProp("_lvCol9") || g._lvCol9 != 58 {
        g.lv.ModifyCol(9, 58)
        g._lvCol9 := 58
        changed := true
    }
    return changed
}

SetListViewRedraw(lv, enabled) {
    static WM_SETREDRAW := 0x000B
    SendMessage(WM_SETREDRAW, enabled ? 1 : 0, 0, lv.Hwnd)
    if enabled
        DllCall("RedrawWindow", "ptr", lv.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x0101)
}

EnableListViewDoubleBuffer(lv) {
    static LVM_GETEXTENDEDLISTVIEWSTYLE := 0x1037
    static LVM_SETEXTENDEDLISTVIEWSTYLE := 0x1036
    static LVS_EX_DOUBLEBUFFER := 0x00010000
    styles := SendMessage(LVM_GETEXTENDEDLISTVIEWSTYLE, 0, 0, lv.Hwnd)
    SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 0, styles | LVS_EX_DOUBLEBUFFER, lv.Hwnd)
}

FormatExt(fmt) {
    switch fmt {
        case "GIF": return "gif"
        case "MP4": return "mp4"
        case "AVI": return "avi"
        case "WebM": return "webm"
        case "MOV": return "mov"
        case "CONTACT": return "png"
    }
    return "mp4"
}

OpenOutputFolder(g) {
    dir := g.dirEdit.Value
    if DirExist(dir)
        Run(Chr(34) dir Chr(34))
}

ShowGuide() {
    guide :=
    (
    "Quick Guide`n`n"
    "1. Add files`n"
    "Use Add Image, Folder, or drag and drop images/videos into the window.`n`n"
    "2. Arrange order`n"
    "Use Copy, Remove, Clear, Up/Down, A-Z, or Flip to manage the queue.`n`n"
    "3. Set timing`n"
    "Frames controls how long each image stays. Use 1/2/3 presets, then Apply for selected rows or All for the whole list.`n`n"
    "4. Add note`n"
    "Select one or more rows, type in Note, then press Set.`n`n"
    "5. Configure export`n"
    "Choose FPS, Loop, format, Canvas size, Fit mode, output Name, Save To folder, optional BG color + Alpha (00-FF hex), and optional Audio.`n`n"
    "6. Preview and generate`n"
    "Select a row to preview it. When ready, press Generate.`n`n"
    "Extra`n"
    "Save/Open stores or loads a project. Save Preset/Load Preset stores export settings. Last Project reopens the most recent project."
    )
    MsgBox(guide, "How to Use Nastarxa Image Combiner", "Iconi")
}

ShowTimesheetSetup(mainGui) {
    global _activeTimesheetGui
    for item in _imageList
        EnsureTimesheetFields(item)

    ts := Gui("+Owner" mainGui.Hwnd, "Timesheet Layer Setup")
    ts.BackColor := "F2F2F2"
    ts.SetFont("s9", "Segoe UI")
    ts.MarginX := 12
    ts.MarginY := 10
    ts.mainGui := mainGui
    _activeTimesheetGui := ts

    ts.tabs := ts.AddTab3("x12 y10 w980 h472 c202020", ["Assignments", "Help"])
    ts.tabs.SetFont("c202020", "Segoe UI")

    ts.tabs.UseTab(1)
    ts.lv := ts.AddListView(
        "x24 y48 w956 h252 Multi BackgroundFFFFFF c000000 Grid",
        ["#", "Active", "File", "Layer", "Type", "Cell", "Start", "End", "TS Dur"]
    )
    ts.lv.ModifyCol(1, 35)
    ts.lv.ModifyCol(2, 46)
    ts.lv.ModifyCol(3, 340)
    ts.lv.ModifyCol(4, 108)
    ts.lv.ModifyCol(5, 88)
    ts.lv.ModifyCol(6, 64)
    ts.lv.ModifyCol(7, 64)
    ts.lv.ModifyCol(8, 64)
    ts.lv.ModifyCol(9, 72)

    ts.lblUse := ts.AddText("x24 y316 c202020", "Active")
    ts.chkUse := ts.AddCheckbox("x60 y314 w22 h22 cFFFFFF")
    ts.lblLayer := ts.AddText("x102 y316 c202020", "Layer")
    ts.ddlLayer := ts.AddDropDownList("x144 y312 w138 Choose2", GetTimesheetLayerOptions())
    ts.btnLayerUp := ts.AddButton("x286 y312 w56 h22", "Top+")
    ts.btnLayerDown := ts.AddButton("x346 y312 w56 h22", "Bot+")
    ts.btnLayerDel := ts.AddButton("x406 y312 w56 h22", "Del")
    ts.lblKind := ts.AddText("x470 y316 c202020", "Type")
    ts.ddlKind := ts.AddDropDownList("x508 y312 w96 Choose1", GetTimesheetKindOptions())
    ts.lblCell := ts.AddText("x618 y316 c202020", "Cell")
    ts.edCell := ts.AddEdit("x652 y312 w58 h22 BackgroundFFFFFF c000000")
    ts.lblStart := ts.AddText("x724 y316 c202020", "Start")
    ts.edStart := ts.AddEdit("x764 y312 w52 h22 Number BackgroundFFFFFF c000000", "1")
    ts.lblEnd := ts.AddText("x826 y316 c202020", "End")
    ts.edEnd := ts.AddEdit("x856 y312 w52 h22 Number BackgroundFFFFFF c000000", "1")
    ts.btnApplyText := ts.AddButton("x916 y312 w64 h22", "Apply")

    ts.btnAutoSel := ts.AddButton("x24 y352 w144 h26", "Auto Detect Selected")
    ts.btnAutoAll := ts.AddButton("x176 y352 w144 h26", "Auto Detect All")
    ts.btnFillAll := ts.AddButton("x328 y352 w170 h26", "Fill Missing End = Start")
    ts.btnLinkDup := ts.AddButton("x506 y352 w112 h26", "Link Dup")
    ts.btnPreview := ts.AddButton("x626 y352 w108 h26", "Preview...")
    ts.lblTotal := ts.AddText("x742 y356 w238 h18 c202020", "")
    ts.info := ts.AddText("x24 y392 w956 h38 c404040"
        , "Assign a queue item to a layer column, cell number, and frame range. "
        . "Frames are absolute output frames, so if an item starts at frame 74 it will appear from frame 74 onward. "
        . "TS Duration is the maximum End frame from all enabled rows, used as the final video duration.")

    ts.tabs.UseTab(2)
    ts.help := ts.AddEdit("x24 y48 w956 h380 ReadOnly -Wrap BackgroundFFFFFF c000000"
        , "Timesheet layering mode" "`r`n`r`n"
        . "Layer order:" "`r`n"
        . "Each base layer has three positions:" "`r`n"
        . "A_shita -> A -> A_ue -> B_shita -> B -> B_ue -> ... -> H_shita -> H -> H_ue" "`r`n`r`n"
        . "Use this when your cut is built from stacked cel layers instead of a simple frame queue." "`r`n`r`n"
        . "Fields:" "`r`n"
        . "- Layer: which timesheet column the image belongs to." "`r`n"
        . "- Cell: the cel number shown in that column." "`r`n"
        . "- Start / End: absolute output frames where this image is active." "`r`n`r`n"
        . "Notes:" "`r`n"
        . "- Link Dup makes another timesheet row that points to the same source file, so one image can have multiple TS setups." "`r`n"
        . "- Every layer A-H can use _shita and _ue." "`r`n"
        . "- Auto Detect tries to read names like A1, B12, A1_shita, B3_ue." "`r`n"
        . "- When Timesheet mode is enabled, output is composited per frame by layer order.")

    ts.tabs.UseTab()
    ts.btnEditGrid := ts.AddButton("x720 y490 w130 h28", "Edit By Time Sheet")
    ts.btnClose := ts.AddButton("x860 y490 w120 h28", "Close")

    ts.lv.OnEvent("Click", (lv, row) => LoadTimesheetEditorFromRows(ts))
    ts.lv.OnEvent("ItemFocus", (lv, row) => row ? LoadTimesheetEditorFromRows(ts) : 0)
    ts.chkUse.OnEvent("Click", (*) => ApplyTimesheetUseState(ts))
    ts.ddlLayer.OnEvent("Change", (*) => ApplyTimesheetDropdownFields(ts))
    ts.btnLayerUp.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), AddManualTimesheetLayer(ts, true)))
    ts.btnLayerDown.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), AddManualTimesheetLayer(ts, false)))
    ts.btnLayerDel.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), DeleteManualTimesheetLayer(ts)))
    ts.ddlKind.OnEvent("Change", (*) => ApplyTimesheetDropdownFields(ts))
    ts.edCell.OnEvent("Change", (*) => ScheduleTimesheetFieldApply(ts))
    ts.edStart.OnEvent("Change", (*) => ScheduleTimesheetFieldApply(ts))
    ts.edEnd.OnEvent("Change", (*) => ScheduleTimesheetFieldApply(ts))
    ts.btnApplyText.OnEvent("Click", (*) => CommitPendingTimesheetFields(ts, true))
    ts.btnAutoSel.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), AutoDetectTimesheetRows(ts, true)))
    ts.btnAutoAll.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), AutoDetectTimesheetRows(ts, false)))
    ts.btnFillAll.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), FillMissingTimesheetEnds(ts)))
    ts.btnLinkDup.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), LinkedDuplicateTimesheetRows(ts)))
    ts.btnPreview.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), ShowTimesheetPreview(ts)))
    ts.btnEditGrid.OnEvent("Click", (*) => (CommitPendingTimesheetFields(ts), ShowTimesheetEditGrid(ts)))
    ts.OnEvent("Close", (*) => CloseTimesheetSetup(ts))
    ts.btnClose.OnEvent("Click", (*) => CloseTimesheetSetup(ts))

    ReloadTimesheetList(ts)
    LoadTimesheetEditorFromRows(ts)
    ts.Show("w1004 h536")
}

ReloadTimesheetList(ts) {
    BeginListUpdate(ts)
    try {
        ts.lv.Delete()
        tsTotal := GetTimesheetTotalFrames()
        for idx, item in _imageList {
            EnsureTimesheetFields(item)
            ts.lv.Add(
                ,
                idx,
                item.tsEnabled ? "Y" : "",
                item.name,
                item.tsLayer,
                item.tsKind,
                item.tsCell,
                FormatTsFrameDisplay(item.tsStartFrame),
                FormatTsFrameDisplay(item.tsEndFrame),
                item.tsEnabled ? tsTotal : ""
            )
        }
    } finally EndListUpdate(ts)
    UpdateTimesheetSummary(ts)
}

UpdateTimesheetSummary(ts) {
    total := GetTimesheetTotalFrames()
    fps := RefreshTimelineRaw(ts.mainGui)
    dur := fps > 0 ? total / fps : 0
    ts.lblTotal.Value := "TS Duration / Video Max: " total " frame(s)  |  " Format("{:.2f}", dur) "s @ " fps " fps"
}

BeginListUpdate(guiOrTs) {
    if !guiOrTs.HasProp("_lvUpdateDepth")
        guiOrTs._lvUpdateDepth := 0
    guiOrTs._lvUpdateDepth += 1
    if guiOrTs._lvUpdateDepth = 1
        SetListViewRedraw(guiOrTs.lv, false)
}

EndListUpdate(guiOrTs) {
    if !guiOrTs.HasProp("_lvUpdateDepth") || guiOrTs._lvUpdateDepth < 1
        return
    guiOrTs._lvUpdateDepth -= 1
    if guiOrTs._lvUpdateDepth = 0
        SetListViewRedraw(guiOrTs.lv, true)
}

GetSelectedListRows(lv) {
    rows := []
    row := 0
    Loop {
        row := lv.GetNext(row)
        if !row
            break
        rows.Push(row)
    }
    return rows
}

LoadTimesheetEditorFromRows(ts) {
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0 && _imageList.Length > 0 {
        ts.lv.Modify(1, "Select Focus Vis")
        rows := [1]
    }
    if rows.Length = 0
        return
    ts._loadingEditor := true
    item := _imageList[rows[1]]
    EnsureTimesheetFields(item)
    allUse := true
    for row in rows {
        rowItem := _imageList[row]
        EnsureTimesheetFields(rowItem)
        if !rowItem.tsEnabled {
            allUse := false
            break
        }
    }
    ts.chkUse.Value := allUse ? 1 : 0
    TrySelectDropDownText(ts.ddlLayer, item.tsLayer)
    TrySelectDropDownText(ts.ddlKind, item.tsKind)
    ts.edCell.Value := item.tsCell
    ts.edStart.Value := item.tsStartFrame
    ts.edEnd.Value := item.tsEndFrame
    ts._loadingEditor := false
}

ApplyTimesheetUseState(ts) {
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0
        return
    if ts.chkUse.Value = 1 {
        appendStart := GetTimesheetTotalFrames() + 1
        if appendStart < 1
            appendStart := 1
        ts.edStart.Value := appendStart
        endVal := ts.edEnd.Value ~= "^\d+$" ? Integer(ts.edEnd.Value) : 0
        if endVal < appendStart
            ts.edEnd.Value := appendStart
    }
    ApplyTimesheetEditorToSelected(ts, true)
}

ApplyTimesheetDropdownFields(ts) {
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0
        return
    ApplyTimesheetEditorToSelected(ts, false, true, false)
}

ScheduleTimesheetFieldApply(ts) {
    if ts.HasProp("_loadingEditor") && ts._loadingEditor
        return
    ts._pendingFieldApply := true
}

CommitPendingTimesheetFields(ts, force := false) {
    if !IsSet(ts) || !IsObject(ts)
        return
    try {
        if !ts.HasProp("Hwnd") || !WinExist("ahk_id " ts.Hwnd)
            return
    }
    if ts.HasProp("_loadingEditor") && ts._loadingEditor
        return
    if !force && (!ts.HasProp("_pendingFieldApply") || !ts._pendingFieldApply)
        return
    ts._pendingFieldApply := false
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0
        return
    ApplyTimesheetEditorToSelected(ts, false, false, true)
}

CloseTimesheetSetup(ts) {
    global _activeTimesheetGui
    CommitPendingTimesheetFields(ts)
    SyncListViewToModel(ts.mainGui)
    RefreshTimeline(ts.mainGui)
    UpdatePreview(ts.mainGui)
    _activeTimesheetGui := ""
    ts.Destroy()
}

AddManualTimesheetLayer(ts, insertBefore := true) {
    anchor := ts.ddlLayer.Text
    if Trim(anchor) = ""
        anchor := GetTimesheetLayerOptions()[1]
    ib := InputBox("New layer name:", insertBefore ? "Add Layer Above" : "Add Layer Below")
    if ib.Result != "OK"
        return
    newLayer := Trim(ib.Value)
    if newLayer = "" {
        MsgBox "Layer name cannot be empty.", "Timesheet Layer", "Icon!"
        return
    }
    for layer in GetTimesheetLayerOptions() {
        if layer = newLayer {
            MsgBox "That layer name already exists.", "Timesheet Layer", "Icon!"
            return
        }
    }
    layers := GetTimesheetLayerOptions()
    anchorIdx := 0
    Loop layers.Length {
        if layers[A_Index] = anchor {
            anchorIdx := A_Index
            break
        }
    }
    if anchorIdx = 0
        anchorIdx := layers.Length
    insertIdx := insertBefore ? anchorIdx : anchorIdx + 1
    global _timesheetLayers
    _timesheetLayers.InsertAt(insertIdx, newLayer)
    ts.Destroy()
    ShowTimesheetSetup(ts.mainGui)
}

LinkedDuplicateTimesheetRows(ts) {
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0
        return
    PushUndoState(ts.mainGui)
    insertedRows := []
    rowsDesc := SortRowsDescending(rows.Clone())
    for _, row in rowsDesc {
        EnsureLinkedGroup(_imageList[row])
        copy := BuildLinkedDuplicateItem(_imageList[row])
        insertAt := row + 1
        _imageList.InsertAt(insertAt, copy)
        insertedRows.InsertAt(1, insertAt)
    }
    ReloadTimesheetList(ts)
    ClearListViewSelection(ts.lv)
    for row in insertedRows
        ts.lv.Modify(row, "Select")
    ts.lv.Modify(insertedRows[1], "Focus Vis")
    LoadTimesheetEditorFromRows(ts)
    SyncListViewToModel(ts.mainGui, insertedRows, insertedRows[1])
    RefreshTimeline(ts.mainGui)
    UpdatePreview(ts.mainGui)
    ts.mainGui.statText.Value := "Linked duplicated " rows.Length " item(s)"
}

DeleteManualTimesheetLayer(ts) {
    layer := Trim(ts.ddlLayer.Text)
    if layer = ""
        return
    if RegExMatch(layer, "^[A-H]$") {
        MsgBox "Base layers A to H cannot be deleted.", "Timesheet Layer", "Icon!"
        return
    }
    rowsToMove := []
    fallback := GetFallbackTimesheetLayer(layer)
    for idx, item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsLayer = layer
            rowsToMove.Push(idx)
    }
    if rowsToMove.Length > 0 {
        PushUndoState(ts.mainGui)
        for row in rowsToMove
            _imageList[row].tsLayer := fallback
        SyncLinkedDuplicateCells(rowsToMove)
    }
    global _timesheetLayers
    Loop _timesheetLayers.Length {
        if _timesheetLayers[A_Index] = layer {
            _timesheetLayers.RemoveAt(A_Index)
            break
        }
    }
    if rowsToMove.Length > 0
        NormalizeTimesheetLayerTimings(CollectAffectedTimesheetLayers(rowsToMove))
    ts.Destroy()
    ShowTimesheetSetup(ts.mainGui)
}

GetFallbackTimesheetLayer(layer) {
    layers := GetTimesheetLayerOptions()
    foundIdx := 0
    Loop layers.Length {
        if layers[A_Index] = layer {
            foundIdx := A_Index
            break
        }
    }
    if foundIdx > 1
        return layers[foundIdx - 1]
    return layers.Length > 1 ? layers[2] : "A"
}

SnapshotTimesheetRows(rows) {
    snapshot := Map()
    for row in rows {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        snapshot[row] := {
            tsEnabled: item.tsEnabled,
            tsLayer: item.tsLayer,
            tsKind: item.tsKind,
            tsCell: item.tsCell,
            tsStartFrame: item.tsStartFrame,
            tsEndFrame: item.tsEndFrame
        }
    }
    return snapshot
}

RestoreTimesheetRows(snapshot) {
    for row, saved in snapshot {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        item.tsEnabled := saved.tsEnabled
        item.tsLayer := saved.tsLayer
        item.tsKind := saved.tsKind
        item.tsCell := saved.tsCell
        item.tsStartFrame := saved.tsStartFrame
        item.tsEndFrame := saved.tsEndFrame
    }
}

TimesheetRowsNeedChange(rows, useState, useOnly, layer, kind, cell, startFrame, endFrame, applyDropdowns := true, applyText := true) {
    for row in rows {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        if item.tsEnabled != useState
            return true
        if useOnly
            continue
        if applyDropdowns && item.tsLayer != layer
            return true
        if applyDropdowns && item.tsKind != kind
            return true
        if applyText && String(item.tsCell) != String(cell)
            return true
        if applyText && item.tsStartFrame != startFrame
            return true
        if applyText && item.tsEndFrame != endFrame
            return true
    }
    return false
}

SyncLinkedDuplicateCells(rows := "") {
    combos := Map()
    if IsObject(rows) && rows.Length > 0 {
        for row in rows {
            item := _imageList[row]
            EnsureTimesheetFields(item)
            group := Trim(String(item.linkGroup))
            if item.type != "image" || group = ""
                continue
            key := group "|" item.tsLayer
            cell := Trim(String(item.tsCell))
            if !combos.Has(key) || (combos[key].cell = "" && cell != "")
                combos[key] := {group: group, layer: item.tsLayer, cell: cell}
        }
    } else {
        for _, item in _imageList {
            EnsureTimesheetFields(item)
            group := Trim(String(item.linkGroup))
            if item.type != "image" || group = ""
                continue
            key := group "|" item.tsLayer
            cell := Trim(String(item.tsCell))
            if !combos.Has(key) || (combos[key].cell = "" && cell != "")
                combos[key] := {group: group, layer: item.tsLayer, cell: cell}
        }
    }
    for _, combo in combos {
        desiredCell := combo.cell
        if desiredCell = "" {
            for _, item in _imageList {
                EnsureTimesheetFields(item)
                if item.type = "image" && item.linkGroup = combo.group && item.tsLayer = combo.layer {
                    cell := Trim(String(item.tsCell))
                    if cell != "" {
                        desiredCell := cell
                        break
                    }
                }
            }
        }
        if desiredCell = ""
            continue
        for _, item in _imageList {
            EnsureTimesheetFields(item)
            if item.type = "image" && item.linkGroup = combo.group && item.tsLayer = combo.layer
                item.tsCell := desiredCell
        }
    }
}

CollectAffectedTimesheetLayers(rows) {
    layers := []
    seen := Map()
    for row in rows {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        if !seen.Has(item.tsLayer) {
            seen[item.tsLayer] := true
            layers.Push(item.tsLayer)
        }
    }
    return layers
}

NormalizeTimesheetLayerTimings(layers := "") {
    targetLayers := IsObject(layers) ? layers : GetTimesheetLayerOptions()
    for layer in targetLayers {
        entries := []
        for idx, item in _imageList {
            EnsureTimesheetFields(item)
            if !item.tsEnabled || item.type != "image" || item.tsLayer != layer
                continue
            entries.Push({row: idx, item: item})
        }
        Loop entries.Length {
            swapped := false
            Loop entries.Length - 1 {
                left := entries[A_Index].item.tsStartFrame
                right := entries[A_Index + 1].item.tsStartFrame
                if left > right {
                    tmp := entries[A_Index]
                    entries[A_Index] := entries[A_Index + 1]
                    entries[A_Index + 1] := tmp
                    swapped := true
                }
            }
            if !swapped
                break
        }
        prevEnd := 0
        for entry in entries {
            item := entry.item
            if item.tsStartFrame <= prevEnd
                item.tsStartFrame := prevEnd + 1
            if item.tsEndFrame < item.tsStartFrame
                item.tsEndFrame := item.tsStartFrame
            prevEnd := item.tsEndFrame
        }
    }
}

FindDuplicateTimesheetCell() {
    seen := Map()
    for idx, item in _imageList {
        EnsureTimesheetFields(item)
        cell := Trim(String(item.tsCell))
        if !item.tsEnabled || item.type != "image" || cell = ""
            continue
        key := item.tsLayer "|" cell
        if seen.Has(key) {
            prior := seen[key]
            sameLinkedGroup := Trim(String(item.linkGroup)) != ""
                && item.linkGroup = prior.group
            if !sameLinkedGroup
                return {row1: prior.row, row2: idx, layer: item.tsLayer, cell: cell}
        } else {
            seen[key] := {row: idx, group: Trim(String(item.linkGroup))}
        }
    }
    return ""
}

ApplyTimesheetEditorToSelected(ts, useOnly := false, applyDropdowns := true, applyText := true) {
    rows := GetSelectedListRows(ts.lv)
    if rows.Length = 0
        return
    layer := ts.ddlLayer.Text
    kind := ts.ddlKind.Text
    cell := Trim(ts.edCell.Value)
    startFrame := ts.edStart.Value ~= "^\d+$" ? Integer(ts.edStart.Value) : 1
    endFrame := ts.edEnd.Value ~= "^\d+$" ? Integer(ts.edEnd.Value) : startFrame
    if startFrame < 1
        startFrame := 1
    if endFrame < startFrame
        endFrame := startFrame
    useState := ts.chkUse.Value = 1
    if !TimesheetRowsNeedChange(rows, useState, useOnly, layer, kind, cell, startFrame, endFrame, applyDropdowns, applyText)
        return
    PushUndoState(ts.mainGui)
    snapshot := SnapshotTimesheetRows(rows)

    for row in rows {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        wasEnabled := item.tsEnabled
        item.tsEnabled := useState
        if useOnly {
            if useState && !wasEnabled {
                item.tsStartFrame := startFrame
                if item.tsEndFrame < item.tsStartFrame
                    item.tsEndFrame := item.tsStartFrame
                if item.tsCell = ""
                    item.tsCell := GetNextCellForLayer(item.tsLayer)
            }
        } else {
            if applyDropdowns {
                item.tsLayer := layer
                item.tsKind := kind
            }
            if applyText {
                item.tsCell := cell
                item.tsStartFrame := startFrame
                item.tsEndFrame := endFrame
            }
        }
    }
    SyncLinkedDuplicateCells(rows)
    NormalizeTimesheetLayerTimings(CollectAffectedTimesheetLayers(rows))
    dup := FindDuplicateTimesheetCell()
    if IsObject(dup) {
        RestoreTimesheetRows(snapshot)
        ReloadTimesheetList(ts)
        for row in rows
            ts.lv.Modify(row, "Select")
        ts.lv.Modify(rows[1], "Focus Vis")
        LoadTimesheetEditorFromRows(ts)
        MsgBox "Duplicate cell " dup.cell " is not allowed in layer " dup.layer ".", "Timesheet Duplicate Cell", "Icon!"
        return
    }
    ReloadTimesheetList(ts)
    for row in rows
        ts.lv.Modify(row, "Select")
    ts.lv.Modify(rows[1], "Focus Vis")
    LoadTimesheetEditorFromRows(ts)
    UpdateListViewRows(ts.mainGui, rows)
    RefreshTimeline(ts.mainGui)
}

AutoDetectTimesheetRows(ts, selectedOnly := false) {
    rows := selectedOnly ? GetSelectedListRows(ts.lv) : []
    if !selectedOnly {
        Loop _imageList.Length
            rows.Push(A_Index)
    }
    if rows.Length = 0
        return
    PushUndoState(ts.mainGui)
    snapshot := SnapshotTimesheetRows(rows)
    for row in rows {
        item := _imageList[row]
        EnsureTimesheetFields(item)
        if AutoDetectTimesheetFromName(item.name, &layer, &cell) {
            item.tsEnabled := true
            item.tsLayer := layer
            item.tsKind := "Key"
            item.tsCell := cell
            if item.tsEndFrame < item.tsStartFrame
                item.tsEndFrame := item.tsStartFrame
        }
    }
    SyncLinkedDuplicateCells(rows)
    NormalizeTimesheetLayerTimings(CollectAffectedTimesheetLayers(rows))
    dup := FindDuplicateTimesheetCell()
    if IsObject(dup) {
        RestoreTimesheetRows(snapshot)
        ReloadTimesheetList(ts)
        for row in rows
            ts.lv.Modify(row, "Select")
        ts.lv.Modify(rows[1], "Focus Vis")
        LoadTimesheetEditorFromRows(ts)
        MsgBox "Duplicate cell " dup.cell " is not allowed in layer " dup.layer ".", "Timesheet Duplicate Cell", "Icon!"
        return
    }
    ReloadTimesheetList(ts)
    for row in rows
        ts.lv.Modify(row, "Select")
    ts.lv.Modify(rows[1], "Focus Vis")
    LoadTimesheetEditorFromRows(ts)
    UpdateListViewRows(ts.mainGui, rows)
    RefreshTimeline(ts.mainGui)
}

FillMissingTimesheetEnds(ts) {
    PushUndoState(ts.mainGui)
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEndFrame < item.tsStartFrame
            item.tsEndFrame := item.tsStartFrame
    }
    ReloadTimesheetList(ts)
    LoadTimesheetEditorFromRows(ts)
    SyncListViewToModel(ts.mainGui)
    RefreshTimeline(ts.mainGui)
}

GetActiveTimesheetItemForLayerFrame(layer, frameNo) {
    for item in _imageList {
        EnsureTimesheetFields(item)
        if !item.tsEnabled || item.type != "image"
            continue
        if item.tsLayer = layer && frameNo >= item.tsStartFrame && frameNo <= item.tsEndFrame
            return item
    }
    return ""
}

GetTimesheetPreviewLayers() {
    hasAny := false
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled && item.type = "image" {
            hasAny := true
            break
        }
    }
    if !hasAny
        return []

    layers := []
    for layer in GetTimesheetLayerOptions() {
        if IsDefaultVisibleTimesheetLayer(layer) || HasTimesheetLayerUsage(layer)
            layers.Push(layer)
    }
    return layers
}

HasTimesheetLayerUsage(layer) {
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled && item.type = "image" && item.tsLayer = layer
            return true
    }
    return false
}

GetTimesheetLayerLabel(layer) {
    if RegExMatch(layer, "^(.)_shita$", &m)
        return m[1] "-"
    if RegExMatch(layer, "^(.)_ue$", &m)
        return m[1] "+"
    return layer
}

GetKeyframeToken(cell) {
    cell := Trim(String(cell))
    if cell = ""
        cell := "?"
    return Chr(8226) cell
}

ShowTimesheetPreview(ts) {
    preview := Gui("+Owner" ts.Hwnd, "Timesheet Preview")
    preview.BackColor := "F8F3E7"
    preview.SetFont("s10", "Consolas")
    preview.MarginX := 12
    preview.MarginY := 10
    preview.previewText := BuildTimesheetPreviewTextV2()
    preview.txtEdit := preview.AddEdit("x12 y12 w760 h600 ReadOnly -Wrap BackgroundFFFFFF c000000", preview.previewText)
    preview.btnSaveTxt := preview.AddButton("x12 y622 w100 h28", "Save TXT")
    preview.btnSavePng := preview.AddButton("x120 y622 w100 h28", "Save PNG")
    preview.btnClose := preview.AddButton("x652 y622 w120 h28", "Close")
    preview.btnSaveTxt.OnEvent("Click", (*) => ExportTimesheetPreviewText(preview))
    preview.btnSavePng.OnEvent("Click", (*) => ExportTimesheetPreviewImage(preview))
    preview.btnClose.OnEvent("Click", (*) => preview.Destroy())
    preview.Show("w784 h664")
    preview.btnClose.Focus()
}

PadPreviewToken(text, width) {
    text := String(text)
    if StrLen(text) >= width
        return text
    return SubStr("                    ", 1, width - StrLen(text)) text
}

BuildTimesheetPreviewTextV2() {
    layers := GetTimesheetPreviewLayers()
    if layers.Length = 0
        return "No enabled timesheet rows yet."

    total := GetTimesheetTotalFrames()
    colW := 6
    frameW := 3
    header1 := PadPreviewToken("Fr", frameW) " |"
    header2 := SubStr("------", 1, frameW) "-+"
    for layer in layers {
        label := PadPreviewToken(GetTimesheetLayerLabel(layer), colW)
        header1 .= label
        header2 .= SubStr("---------------", 1, colW)
    }
    out := header1 "`r`n" header2 "`r`n"

    Loop total {
        frameNo := A_Index
        line := PadPreviewToken(frameNo, frameW) " |"
        for layer in layers {
            item := GetActiveTimesheetItemForLayerFrame(layer, frameNo)
            prev := frameNo > 1 ? GetActiveTimesheetItemForLayerFrame(layer, frameNo - 1) : ""
            if IsObject(item) {
                startOfBlock := !IsObject(prev) || prev != item
                if startOfBlock {
                    cell := item.tsCell != "" ? item.tsCell : "?"
                    token := item.tsKind = "Inbetween" ? cell : GetKeyframeToken(cell)
                } else {
                    token := "│"
                }
            } else {
                token := (frameNo = 1 || IsObject(prev)) ? "X" : "~"
            }
            line .= PadPreviewToken(token, colW)
        }
        out .= line "`r`n"
    }

    out .= "`r`nLegend:`r`n"
        . "number with " Chr(8226) " = keyframe`r`n"
        . "plain number = inbetween`r`n"
        . "X = empty frame start`r`n"
        . "│ = held frame continuation`r`n"
        . "~ = empty continuation"
    return out
}

ExportTimesheetPreviewText(preview) {
    path := FileSelect("S16", _OUTPUT_DIR "\timesheet_preview.txt", "Save Timesheet Preview", "Text (*.txt)")
    if path = ""
        return
    text := preview.HasProp("previewText") ? preview.previewText : preview.txtEdit.Value
    FileDeleteSafe(path)
    FileAppend(text, path, "UTF-8")
}

ExportTimesheetPreviewImage(preview) {
    path := FileSelect("S16", _OUTPUT_DIR "\timesheet_preview.png", "Save Timesheet Preview Image", "PNG (*.png)")
    if path = ""
        return
    text := preview.HasProp("previewText") ? preview.previewText : preview.txtEdit.Value
    if RenderTextPreviewToPng(text, path)
        return
    MsgBox "Failed to export preview image.", "Timesheet Preview", "IconX"
}

RenderTextPreviewToPng(text, destPath) {
    txtPath := A_Temp "\NastarxaIC_preview_" A_TickCount ".txt"
    scriptPath := A_Temp "\NastarxaIC_preview_" A_TickCount ".ps1"
    q := Chr(34)
    try {
        FileDeleteSafe(txtPath)
        FileDeleteSafe(scriptPath)
        FileAppend(text, txtPath, "UTF-8")
        psLines := [
            "param([string]$txtPath,[string]$pngPath)",
            "Add-Type -AssemblyName System.Drawing",
            "$text = [System.IO.File]::ReadAllText($txtPath, [System.Text.Encoding]::UTF8)",
            "$lines = $text -split '\r?\n'",
            "if ($lines.Length -eq 0) { $lines = @('') }",
            "$font = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)",
            "$bmp0 = New-Object System.Drawing.Bitmap(4,4)",
            "$g0 = [System.Drawing.Graphics]::FromImage($bmp0)",
            "$g0.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit",
            "$maxWidth = 0.0",
            "foreach ($line in $lines) {",
            "    $size = $g0.MeasureString($line, $font)",
            "    if ($size.Width -gt $maxWidth) { $maxWidth = $size.Width }",
            "}",
            "$lineHeight = [Math]::Ceiling($font.GetHeight($g0) + 4)",
            "$g0.Dispose()",
            "$bmp0.Dispose()",
            "$margin = 16",
            "$width = [Math]::Max(320, [int][Math]::Ceiling($maxWidth) + ($margin * 2))",
            "$height = [Math]::Max(180, ($lines.Length * $lineHeight) + ($margin * 2))",
            "$bmp = New-Object System.Drawing.Bitmap($width, $height)",
            "$g = [System.Drawing.Graphics]::FromImage($bmp)",
            "$g.Clear([System.Drawing.Color]::White)",
            "$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit",
            "$brush = [System.Drawing.Brushes]::Black",
            "for ($i = 0; $i -lt $lines.Length; $i++) {",
            "    $g.DrawString($lines[$i], $font, $brush, $margin, $margin + ($i * $lineHeight))",
            "}",
            "$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)",
            "$g.Dispose()",
            "$bmp.Dispose()",
            "$font.Dispose()"
        ]
        ps := JoinText(psLines, "`r`n")
        FileAppend(ps, scriptPath, "UTF-8")
        cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " q scriptPath q " " q txtPath q " " q destPath q
        result := RunWait(cmd, , "Hide")
        return result = 0 && FileExist(destPath)
    } finally {
        FileDeleteSafe(txtPath)
        FileDeleteSafe(scriptPath)
    }
}

FileDeleteSafe(path) {
    try FileDelete(path)
}

SaveProject(g) {
    path := FileSelect("S16", _OUTPUT_DIR "\project.nfcp", "Save Project", "Project (*.nfcp)")
    if path = ""
        return
    IniWrite(g.dirEdit.Value, path, "Settings", "OutputDir")
    iniFps := g.fpsEdit.Value
    IniWrite(iniFps, path, "Settings", "FPS")
    iniW := g.widthEdit.Value
    IniWrite(iniW, path, "Settings", "Width")
    iniH := g.heightEdit.Value
    IniWrite(iniH, path, "Settings", "Height")
    iniOut := g.outEdit.Value
    IniWrite(iniOut, path, "Settings", "OutName")
    IniWrite(g.chkGIF.Value, path, "Settings", "FmtGIF")
    IniWrite(g.chkMP4.Value, path, "Settings", "FmtMP4")
    IniWrite(g.chkAVI.Value, path, "Settings", "FmtAVI")
    IniWrite(g.chkWebM.Value, path, "Settings", "FmtWebM")
    IniWrite(g.chkMOV.Value, path, "Settings", "FmtMOV")
    IniWrite(g.chkPNG.Value, path, "Settings", "FmtPNG")
    IniWrite(g.chkSheet.Value, path, "Settings", "FmtSheet")
    IniWrite(g.sheetCountEdit.Value, path, "Settings", "SheetCount")
    IniWrite(g.chkTimestamp.Value, path, "Settings", "Timestamp")
    IniWrite(g.loopEdit.Value, path, "Settings", "Loop")
    IniWrite(g.crfEdit.Value, path, "Settings", "CRF")
    IniWrite(g.fitDDL.Text, path, "Settings", "Fit")
    IniWrite(g.bgEdit.Value, path, "Settings", "BG")
    IniWrite(g.bgAlphaEdit.Value, path, "Settings", "BGAlpha")
    IniWrite(g.audioEdit.Value, path, "Settings", "Audio")
    IniWrite(g.chkTimesheet.Value, path, "Settings", "TimesheetMode")
    IniWrite(SerializeTimesheetLayers(), path, "Settings", "TsLayers")
    try FileDelete(_LAST_PROJECT_FILE)
    FileAppend(path, _LAST_PROJECT_FILE)
    WriteQueueItemsToIni(path, "Files")
    g.statText.Value := "Project saved"
}

LoadProject(g) {
    global _imageList
    path := FileSelect("3", _OUTPUT_DIR "\project.nfcp", "Load Project", "Project (*.nfcp)")
    if path = ""
        return
    LoadProjectFromPath(g, path)
}

LoadProjectFromPath(g, path) {
    global _imageList
    global _selectedRow
    try {
        PushUndoState(g)
        g.fpsEdit.Value := IniRead(path, "Settings", "FPS", "24")
        g.widthEdit.Value := IniRead(path, "Settings", "Width", "1920")
        g.heightEdit.Value := IniRead(path, "Settings", "Height", "1080")
        g.outEdit.Value := IniRead(path, "Settings", "OutName", "animation")
        g.dirEdit.Value := IniRead(path, "Settings", "OutputDir", _OUTPUT_DIR)
        g.chkGIF.Value := Integer(IniRead(path, "Settings", "FmtGIF", "1"))
        g.chkMP4.Value := Integer(IniRead(path, "Settings", "FmtMP4", "1"))
        g.chkAVI.Value := Integer(IniRead(path, "Settings", "FmtAVI", "0"))
        g.chkWebM.Value := Integer(IniRead(path, "Settings", "FmtWebM", "0"))
        g.chkMOV.Value := Integer(IniRead(path, "Settings", "FmtMOV", "0"))
        g.chkPNG.Value := Integer(IniRead(path, "Settings", "FmtPNG", "0"))
        g.chkSheet.Value := Integer(IniRead(path, "Settings", "FmtSheet", "0"))
        g.sheetCountEdit.Value := IniRead(path, "Settings", "SheetCount", "16")
        g.chkTimestamp.Value := Integer(IniRead(path, "Settings", "Timestamp", "0"))
        g.loopEdit.Value := IniRead(path, "Settings", "Loop", "0")
        g.crfEdit.Value := IniRead(path, "Settings", "CRF", "23")
        TrySelectDropDownText(g.fitDDL, IniRead(path, "Settings", "Fit", "stretch"))
        g.bgEdit.Value := NormalizeHexColor(IniRead(path, "Settings", "BG", "#FFFFFF"))
        g.bgAlphaEdit.Value := IniRead(path, "Settings", "BGAlpha", "FF")
        g.audioEdit.Value := IniRead(path, "Settings", "Audio", "")
        g.chkTimesheet.Value := Integer(IniRead(path, "Settings", "TimesheetMode", "0"))
        LoadTimesheetLayersFromString(IniRead(path, "Settings", "TsLayers", SerializeTimesheetLayers()))

        _imageList := ReadQueueItemsFromIni(path, "Files")
        if _imageList.Length = 0 {
            count := Integer(IniRead(path, "Files", "Count", "0"))
            Loop count {
                prefix := "Item" A_Index
            ; Backward-compatible loader for older project files.
                raw := IniRead(path, "Files", prefix, "")
                parts := StrSplit(raw, "|||")
                if parts.Length >= 2 {
                    SplitPath(parts[1], &name)
                    item := {path: parts[1], name: name, exposure: Integer(parts[2]), type: "image", note: parts.Length >= 5 ? parts[5] : ""}
                    EnsureTimesheetFields(item)
                    if parts.Length >= 3 && parts[3] = "video" {
                        item.type := "video"
                        item.frameCount := parts.Length >= 4 ? Integer(parts[4]) : 0
                        item.durationSec := 0
                        item.previewFrame := 1
                    } else if parts.Length >= 3 {
                        item.type := parts[3]
                        if parts[3] = "video" {
                            item.frameCount := parts.Length >= 4 ? Integer(parts[4]) : 0
                            item.durationSec := 0
                            item.previewFrame := 1
                        }
                    }
                    _imageList.Push(item)
                }
            }
        }
        SyncLinkedDuplicateCells()
        NormalizeTimesheetLayerTimings()
        _selectedRow := 0
        SyncListViewToModel(g)
        RefreshTimeline(g)
        UpdatePreview(g)
        g.btnTimesheet.Enabled := g.chkTimesheet.Value = 1
        ApplyTimesheetModeUI(g)
        g.statText.Value := "Loaded " _imageList.Length " item(s)"
        try FileDelete(_LAST_PROJECT_FILE)
        FileAppend(path, _LAST_PROJECT_FILE)
    } catch {
        MsgBox "Failed to load project file.", "Error", "IconX"
    }
}

; ============================================================
; TIMESHEET — Edit Grid (Table)
; ============================================================

GetNextCellForLayer(layer) {
    used := []
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled && item.tsLayer = layer && item.tsCell ~= "^\d+$"
            used.Push(Integer(item.tsCell))
    }
    cell := 1
    loop {
        found := false
        for n in used {
            if n = cell {
                found := true
                break
            }
        }
        if !found
            return cell
        cell += 1
    }
}

AutoAssignTimesheetCells() {
    layers := Map()
    for item in _imageList {
        EnsureTimesheetFields(item)
        if !item.tsEnabled
            continue
        l := item.tsLayer
        if !layers.Has(l)
            layers[l] := []
        layers[l].Push(item)
    }
    for l, items in layers {
        Loop items.Length {
            swapped := false
            Loop items.Length - 1 {
                a := items[A_Index]
                b := items[A_Index + 1]
                if a.tsStartFrame > b.tsStartFrame {
                    tmp := items[A_Index]
                    items[A_Index] := items[A_Index + 1]
                    items[A_Index + 1] := tmp
                    swapped := true
                }
            }
            if !swapped
                break
        }
        cell := 1
        for item in items
            item.tsCell := cell++
    }
}

DeduplicateTimesheetCells() {
    layers := Map()
    for idx, item in _imageList {
        EnsureTimesheetFields(item)
        if !item.tsEnabled || item.type != "image"
            continue
        l := item.tsLayer
        if !layers.Has(l)
            layers[l] := []
        layers[l].Push({idx: idx, item: item})
    }
    for l, items in layers {
        cellGroups := Map()
        for entry in items {
            cell := Trim(String(entry.item.tsCell))
            if cell = "" || !(cell ~= "^\d+$")
                continue
            if !cellGroups.Has(cell)
                cellGroups[cell] := []
            cellGroups[cell].Push(entry)
        }
        for cell, entries in cellGroups {
            if entries.Length <= 1
                continue
            groups := Map()
            for entry in entries {
                g := Trim(String(entry.item.linkGroup))
                if !groups.Has(g)
                    groups[g] := 0
                groups[g] += 1
            }
            bestGroup := ""
            bestCount := 0
            for g, cnt in groups {
                if cnt > bestCount {
                    bestCount := cnt
                    bestGroup := g
                }
            }
            for entry in entries {
                g := Trim(String(entry.item.linkGroup))
                if g != bestGroup {
                    entry.item.tsCell := GetNextCellForLayer(l)
                }
            }
            if bestGroup = "" && entries.Length > 1 {
                for i, entry in entries {
                    if i = 1
                        continue
                    entry.item.tsCell := GetNextCellForLayer(l)
                }
            }
        }
    }
}

GetActiveTimesheetLayers() {
    seen := Map()
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled {
            l := item.tsLayer
            if !seen.Has(l)
                seen[l] := true
        }
    }
    layers := []
    for l, _ in seen
        layers.Push(l)
    Loop layers.Length {
        swapped := false
        Loop layers.Length - 1 {
            ra := GetTimesheetLayerRank(layers[A_Index])
            rb := GetTimesheetLayerRank(layers[A_Index + 1])
            if ra > rb {
                tmp := layers[A_Index]
                layers[A_Index] := layers[A_Index + 1]
                layers[A_Index + 1] := tmp
                swapped := true
            }
        }
        if !swapped
            break
    }
    return layers
}

GetCellText(frame, layer) {
    for item in _imageList {
        EnsureTimesheetFields(item)
        if item.tsEnabled && item.tsLayer = layer && item.tsStartFrame <= frame && frame <= item.tsEndFrame {
            if frame = item.tsStartFrame {
                if item.tsCell ~= "^\d+$"
                    return "•" item.tsCell
                return "X"
            }
            return "│"
        }
    }
    return "~"
}

ShowTimesheetEditGrid(ts) {
    global _imageList
    eg := Gui("+Owner" ts.Hwnd, "Timesheet Edit Grid")
    eg.SetFont("s9", "Segoe UI")
    eg.MarginX := 10
    eg.MarginY := 10
    eg.ts := ts

    layers := GetActiveTimesheetLayers()
    eg.layers := layers

    totalW := Max(420, 60 + layers.Length * 64)
    if totalW > 1200
        totalW := 1200

    eg.AddText("x10 y10 c808080", "Edit cell values directly.  •N=numbered, X=keyframe, │=hold, ~=empty")

    eg.edit := eg.AddEdit("x10 y28 w" (totalW - 20) " h260 +HScroll +VScroll +WantTab", "")

    eg.edit.Value := BuildTimesheetTableText(layers)

    btnRow1 := 298
    eg.btnMinus := eg.AddButton("x10 y" btnRow1 " w28 h24", "-")
    eg.btnPlus := eg.AddButton("x42 y" btnRow1 " w28 h24", "+")

    btnRow2 := btnRow1 + 32
    eg.btnAuto := eg.AddButton("x10 y" btnRow2 " w130 h26", "Auto-Adjust")
    eg.btnSave := eg.AddButton("x150 y" btnRow2 " w110 h26", "Save && Sync")
    eg.btnHelp := eg.AddButton("x260 y" btnRow2 " w28 h24", "?")
    eg.btnClose := eg.AddButton("x" (totalW - 126) " y" btnRow2 " w96 h26", "Close")

    eg.btnMinus.OnEvent("Click", (*) => RemoveEditGridFrame(eg))
    eg.btnPlus.OnEvent("Click", (*) => AddEditGridFrame(eg))
    eg.btnAuto.OnEvent("Click", (*) => SmartAutoAdjustEditGrid(eg))
    eg.btnSave.OnEvent("Click", (*) => SaveEditGrid(eg))
    eg.btnHelp.OnEvent("Click", (*) => ShowEditGridHelp())
    eg.btnClose.OnEvent("Click", (*) => eg.Destroy())

    eg.Show("w" totalW " h" (btnRow2 + 50))
}

BuildTimesheetTableText(layers) {
    if layers.Length = 0
        return " Fr"
    total := GetTimesheetTotalFrames()
    fw := Max(2, StrLen(total))
    hdr := SubStr("     ", 1, fw - 2) "Fr"
    sep := ""
    Loop fw
        sep .= "-"
    for l in layers {
        hdr .= " | " PadCenter(l, 5)
        sep .= "-+------"
    }
    text := hdr "`n" sep "`n"
    Loop total {
        f := A_Index
        line := Format("{:" fw "d}", f)
        for l in layers
            line .= " | " PadCenter(GetCellText(f, l), 5)
        text .= line "`n"
    }
    return RTrim(text, "`n")
}

PadCenter(str, width) {
    len := StrLen(str)
    if len >= width
        return str
    pad := width - len
    left := pad // 2
    right := pad - left
    result := str
    Loop right
        result .= " "
    Loop left
        result := " " . result
    return result
}

AddEditGridFrame(eg) {
    text := eg.edit.Value
    lines := StrSplit(text, "`n")
    total := lines.Length - 2

    lastParts := ""
    if total >= 1 {
        lastLine := lines[lines.Length]
        lastParts := StrSplit(lastLine, "|")
    }

    line := Format("{:3d}", total + 1)
    for li, l in eg.layers {
        if IsObject(lastParts) && li < lastParts.Length {
            lastVal := Trim(lastParts[li + 1])
            if lastVal = "X" || lastVal = "~"
                val := "~"
            else
                val := "│"
        } else {
            val := "~"
        }
        line .= " | " PadCenter(val, 5)
    }
    text .= "`n" . line
    eg.edit.Value := text
    RenumberGridFrames(eg)
}

RemoveEditGridFrame(eg) {
    text := eg.edit.Value
    lines := StrSplit(text, "`n")
    if lines.Length <= 3
        return
    lines.RemoveAt(lines.Length)
    newText := lines[1]
    Loop lines.Length - 1
        newText .= "`n" . lines[A_Index + 1]
    eg.edit.Value := newText
    RenumberGridFrames(eg)
}

RenumberGridFrames(eg) {
    text := eg.edit.Value
    lines := StrSplit(text, "`n", "`r")
    if lines.Length < 3
        return

    dataParts := []
    for i, line in lines {
        if i <= 2
            continue
        l := Trim(line)
        if l = ""
            continue
        parts := StrSplit(l, "|")
        if parts.Length < 2
            continue
        dataParts.Push(parts)
    }
    if dataParts.Length = 0
        return

    fw := Max(2, StrLen(dataParts.Length))
    layers := eg.layers
    hdr := SubStr("     ", 1, fw - 2) "Fr"
    sep := ""
    Loop fw
        sep .= "-"
    for l in layers {
        hdr .= " | " PadCenter(l, 5)
        sep .= "-+------"
    }
    newText := hdr "`n" sep
    seq := 1
    for parts in dataParts {
        parts[1] := Format("{:" fw "d} ", seq)
        newLine := ""
        for j, p in parts {
            if j > 1
                newLine .= "|"
            newLine .= p
        }
        newText .= "`n" . newLine
        seq++
    }
    eg.edit.Value := newText
    SendMessage(0x00B1, StrLen(newText), StrLen(newText), eg.edit.Hwnd)
}

ParseTimesheetGrid(text, layers) {
    lines := StrSplit(text, "`n", "`r")
    grid := []
    for i, line in lines {
        if i <= 2
            continue
        line := Trim(line)
        if line = ""
            continue
        parts := StrSplit(line, "|")
        if parts.Length < 2
            continue
        try
            frame := Integer(Trim(parts[1]))
        if !frame
            continue
        cells := []
        for j, part in parts {
            if j = 1
                continue
            cellVal := Trim(part)
            if cellVal = "|"
                cellVal := "│"
            cells.Push(cellVal)
        }
        grid.Push({frame: frame, cells: cells})
    }
    return grid
}

SmartAutoAdjustEditGrid(eg) {
    text := eg.edit.Value
    layers := eg.layers
    if text = ""
        return

    lines := StrSplit(text, "`n", "`r")
    data := []
    for i, line in lines {
        if i <= 2
            continue
        line := Trim(line)
        if line = ""
            continue
        parts := StrSplit(line, "|")
        if parts.Length < 2
            continue
        try
            frame := Integer(Trim(parts[1]))
        if !frame
            continue
        row := []
        for j, part in parts {
            if j = 1
                continue
            row.Push(Trim(part))
        }
        data.Push({frame: frame, cells: row})
    }

    if data.Length = 0
        return

    fw := Max(2, StrLen(data.Length))
    hdr := SubStr("     ", 1, fw - 2) "Fr"
    sep := ""
    Loop fw
        sep .= "-"
    for l in layers {
        hdr .= " | " PadCenter(l, 5)
        sep .= "-+------"
    }
    newText := hdr "`n" sep

    seq := 1
    for ei, entry in data {
        line := Format("{:" fw "d}", seq)
        for li, l in layers {
            val := entry.cells.Length >= li ? entry.cells[li] : "~"
            if val = "|"
                val := "│"
            if val = "" || val = "~" || val = "│" {
                if ei > 1 {
                    above := data[ei-1].cells.Length >= li ? data[ei-1].cells[li] : "~"
                    if above = "|"
                        above := "│"
                    if above = "X" || above = "~" || above = ""
                        val := "~"
                    else
                        val := "│"
                } else {
                    val := "~"
                }
            }
            line .= " | " PadCenter(val, 5)
        }
        newText .= "`n" . line
        seq++
    }

    eg.edit.Value := newText
}

RestoreItemsFromGrid(grid, layers) {
    global _imageList

    regular := []
    srcLookup := Map()
    for item in _imageList {
        if item.type = "image" && item.tsEnabled {
            key := item.tsLayer "|" Trim(String(item.tsCell))
            if !srcLookup.Has(key)
                srcLookup[key] := item.path
            continue
        }
        regular.Push(item)
    }

    newItems := []
    for li, layer in layers {
        startFrame := 0
        cellNum := ""
        for gi, entry in grid {
            val := entry.cells.Length >= li ? entry.cells[li] : "~"
            if val = "|"
                val := "│"
            if startFrame = 0 {
                if val = "~"
                    continue
                startFrame := entry.frame
                if SubStr(val, 1, 1) = "•"
                    cellNum := SubStr(val, 2)
                else
                    cellNum := ""
                continue
            }
            if val = "~" || (val = "X" && entry.frame > startFrame) || (SubStr(val, 1, 1) = "•") {
                endFrame := entry.frame - 1
                srcPath := srcLookup.Has(layer "|" cellNum) ? srcLookup[layer "|" cellNum] : ""
                item := {name: "TS-frame" startFrame, type: "image", exposure: 1, note: "", path: srcPath
                    , tsEnabled: true, tsLayer: layer, tsCell: cellNum, tsStartFrame: startFrame, tsEndFrame: endFrame, linkGroup: ""}
                EnsureTimesheetFields(item)
                newItems.Push(item)
                if val = "~" {
                    startFrame := 0
                    cellNum := ""
                } else {
                    startFrame := entry.frame
                    if SubStr(val, 1, 1) = "•"
                        cellNum := SubStr(val, 2)
                    else
                        cellNum := ""
                }
                continue
            }
        }
        if startFrame > 0 && grid.Length > 0 {
            srcPath := srcLookup.Has(layer "|" cellNum) ? srcLookup[layer "|" cellNum] : ""
            item := {name: "TS-frame" startFrame, type: "image", exposure: 1, note: "", path: srcPath
                , tsEnabled: true, tsLayer: layer, tsCell: cellNum, tsStartFrame: startFrame, tsEndFrame: grid[grid.Length].frame, linkGroup: ""}
            EnsureTimesheetFields(item)
            newItems.Push(item)
        }
    }

    _imageList := []
    for item in regular
        _imageList.Push(item)
    for item in newItems
        _imageList.Push(item)
}

SaveEditGrid(eg) {
    global _imageList
    layers := eg.layers
    text := eg.edit.Value
    if Trim(text) = ""
        return

    grid := ParseTimesheetGrid(text, layers)
    if grid.Length = 0 {
        MsgBox "Could not parse the grid text.", "Parse Error", "Icon!"
        return
    }

    if grid[1].cells.Length < layers.Length {
        MsgBox "Number of columns in text (" grid[1].cells.Length ") doesn't match layers (" layers.Length ").", "Parse Error", "Icon!"
        return
    }

    backup := _imageList.Clone()
    PushUndoState(eg.ts.mainGui)
    RestoreItemsFromGrid(grid, layers)

    dup := FindDuplicateTimesheetCell()
    if IsObject(dup) {
        _imageList := backup
        eg.edit.Value := BuildTimesheetTableText(layers)
        MsgBox "Duplicate cell " dup.cell " in layer " dup.layer ". Changes reverted.", "Timesheet Error", "Icon!"
        return
    }

    SyncListViewToModel(eg.ts.mainGui)
    ReloadTimesheetList(eg.ts)
    RefreshTimeline(eg.ts.mainGui)
    UpdatePreview(eg.ts.mainGui)

    eg.edit.Value := BuildTimesheetTableText(layers)
}

ShowEditGridHelp() {
    MsgBox(
        "TIMESHEET EDIT GRID HELP`n`n"
        . "Edit the table text directly:`n"
        . "  •1, •2 ...  Cell number keyframe`n"
        . "  X           Keyframe (no number)`n"
        . "  │ or |      Hold / continuation (type | auto-converts to │)`n"
        . "  ~           Empty (no item)`n`n"
        . "Buttons:`n"
        . "  [+] Add a frame at the end (value from last frame: •N/│ → │, X/~ → ~)`n"
        . "  [-] Remove the last frame`n`n"
        . "Auto-Adjust: re-aligns text, fills empty cells from above, renumbers frames`n"
        . "  •N, N, │ above → │ below     X, ~, empty above → ~ below`n`n"
        . "Save && Sync: reconstructs items from the table text`n"
        . "Frame numbers are always kept sequential (1, 2, 3, ...)`n"
        . "Changes are tracked with Undo (Ctrl+Z in main window)",
        "Edit Grid Help", "Iconi"
    )
}
