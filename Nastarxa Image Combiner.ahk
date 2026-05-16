#Requires AutoHotkey v2.0
#SingleInstance Force
TraySetIcon "Combiner.ico"

_FFMPEG := ResolveFFmpegPath()
_OUTPUT_DIR := A_ScriptDir
_imageList := []
_selectedRow := 0
_tempDir := ""
_PRESET_FILE := A_ScriptDir "\presets.ini"
_LAST_PROJECT_FILE := A_ScriptDir "\last_project.txt"
_cancelGenerate := false
_lastPrepareError := ""
_ffmpegEncoderCache := Map()
_previewCacheDir := A_Temp "\NastarxaIC_preview"
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
        ["#", "File", "Exp", "Note"]
    )
    EnableListViewDoubleBuffer(g.lv)

    g.lv.ModifyCol(1, 35)
    g.lv.ModifyCol(2, 460)
    g.lv.ModifyCol(3, 65)
    g.lv.ModifyCol(4, 160)

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
        "x" rx+166 " y146 w90 cFFFFFF",
        "+time"
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
    g.chkPNG.OnEvent("Click", (*) => g.Progress.Value := 0)
    g.chkSheet.OnEvent("Click", (*) => g.Progress.Value := 0)

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

    g.Show("Hide w1180 h650 Center")

    HotIfWinActive("ahk_id " g.Hwnd)
    Hotkey("Delete", (*) => RemoveSelected(g))
    HotIfWinActive()

    ApplyLayout(g, 1180, 680)
    g.Show()

    return g
}

DropFiles(g, files) {
    g.Progress.Value := 0
    if !IsObject(files)
        return
    addedRows := []
    len := files.Length
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
    static valid := ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "webp", "gif", "mp4"]
    for v in valid {
        if ext = "." v
            return true
    }
    return false
}

IsVideoFile(path) {
    SplitPath(path, , , &ext)
    ext := StrLower(ext)
    return ext = "mp4" || ext = "gif"
}

OnAddImages(g) {
    files := FileSelect("M", , "Select Images", "Media (*.png; *.jpg; *.jpeg; *.bmp; *.tif; *.tiff; *.webp; *.gif; *.mp4)")
    if files = ""
        return
    g.Progress.Value := 0
    addedRows := []
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
    global _imageList
    global _selectedRow
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
    RefreshTimeline(g)
    g.statText.Value := "Sorted by name"
}

ReverseOrder(g) {
    global _imageList
    global _selectedRow
    g.Progress.Value := 0
    reversed := []
    for i in _imageList
        reversed.InsertAt(1, i)
    _imageList := reversed
    _selectedRow := 0
    SyncListViewToModel(g)
    RefreshTimeline(g)
    g.statText.Value := "Reversed order"
}

SetExposurePreset(g, val) {
    g.expEdit.Value := val
    g.Progress.Value := 0
    rows := GetSelectedRows(g)
    if rows.Length > 0 {
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
    g.Progress.Value := 0
    _imageList := []
    _selectedRow := 0
    g.lv.Delete()
    RefreshTimeline(g)
    UpdatePreview(g)
    g.statText.Value := "Cleared all"
}

MoveItem(g, dir) {
    global _selectedRow
    if _selectedRow = 0
        return
    row := _selectedRow
    target := row + dir
    if target < 1 || target > _imageList.Length
        return
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
    lbl := item.type = "video" ? (item.frameCount > 0 ? item.frameCount " frames" : "video") : item.exposure
    g.lv.Modify(row, "", row, item.name, lbl, item.HasProp("note") ? item.note : "")
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
    if _imageList.Length = 0
        return
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
    IniWrite(g.chkPNG.Value, _PRESET_FILE, name, "FmtPNG")
    IniWrite(g.chkSheet.Value, _PRESET_FILE, name, "FmtSheet")
    IniWrite(g.sheetCountEdit.Value, _PRESET_FILE, name, "SheetCount")
    IniWrite(g.loopEdit.Value, _PRESET_FILE, name, "Loop")
    IniWrite(g.crfEdit.Value, _PRESET_FILE, name, "CRF")
    IniWrite(g.fitDDL.Text, _PRESET_FILE, name, "Fit")
    IniWrite(g.bgEdit.Value, _PRESET_FILE, name, "BG")
    IniWrite(g.bgAlphaEdit.Value, _PRESET_FILE, name, "BGAlpha")
    IniWrite(g.audioEdit.Value, _PRESET_FILE, name, "Audio")
    g.statText.Value := "Preset saved: " name
}

LoadPreset(g) {
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
    g.fpsEdit.Value := IniRead(_PRESET_FILE, sel, "FPS", "24")
    g.widthEdit.Value := IniRead(_PRESET_FILE, sel, "Width", "1920")
    g.heightEdit.Value := IniRead(_PRESET_FILE, sel, "Height", "1080")
    g.chkGIF.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtGIF", "1"))
    g.chkMP4.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtMP4", "1"))
    g.chkAVI.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtAVI", "0"))
    g.chkWebM.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtWebM", "0"))
    g.chkPNG.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtPNG", "0"))
    g.chkSheet.Value := Integer(IniRead(_PRESET_FILE, sel, "FmtSheet", "0"))
    g.sheetCountEdit.Value := IniRead(_PRESET_FILE, sel, "SheetCount", "16")
    g.loopEdit.Value := IniRead(_PRESET_FILE, sel, "Loop", "0")
    g.crfEdit.Value := IniRead(_PRESET_FILE, sel, "CRF", "23")
    TrySelectDropDownText(g.fitDDL, IniRead(_PRESET_FILE, sel, "Fit", "stretch"))
    g.bgEdit.Value := NormalizeHexColor(IniRead(_PRESET_FILE, sel, "BG", "#FFFFFF"))
    g.bgAlphaEdit.Value := IniRead(_PRESET_FILE, sel, "BGAlpha", "FF")
    g.audioEdit.Value := IniRead(_PRESET_FILE, sel, "Audio", "")
    RefreshTimeline(g)
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
    Loop ctrl.GetCount() {
        if ctrl.Text = text {
            ctrl.Choose(A_Index)
            return
        }
        ctrl.Choose(A_Index)
        if ctrl.Text = text
            return
    }
    ctrl.Choose(1)
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
    if g.chkPNG.Value
        fmts.Push("PNGSEQ")
    if g.chkSheet.Value
        fmts.Push("CONTACT")
    return fmts
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
            Loop Files, tempDir "\*.png", "F"
                try FileCopy(A_LoopFileFullPath, seqDir "\" A_LoopFileName, 1)
            successCount++
            generatedCount++
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

BuildFFmpegCmd(fmt, fps, w, h, fitMode, bgColor, loopVal, crf, audioPath, inputDir, outputPath) {
    q := Chr(34)
    inPattern := q inputDir "\%06d.png" q
    out := q outputPath q
    scaleFilter := BuildScaleFilter(w, h, fitMode, bgColor)
    audioArgs := ""
    if (fmt = "MP4" || fmt = "WebM") && audioPath != "" && FileExist(audioPath)
        audioArgs := " -i " q audioPath q " -shortest"
    switch fmt {
        case "GIF":
            gifLoop := loopVal > 0 ? loopVal : 0
            filter := q "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" q
            if scaleFilter != ""
                filter := q scaleFilter ",split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" q
            cmd1 := "-y -framerate " fps " -i " inPattern " -vf " filter " -loop " gifLoop " " out
        case "MP4":
            cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -c:v libx264 -pix_fmt yuv420p -crf " crf " -movflags +faststart " out
            if scaleFilter != ""
                cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -vf " q scaleFilter q " -c:v libx264 -pix_fmt yuv420p -crf " crf " -movflags +faststart " out
        case "AVI":
            cmd1 := "-y -framerate " fps " -i " inPattern " -c:v libx264 -pix_fmt yuv420p -crf " crf " " out
            if scaleFilter != ""
                cmd1 := "-y -framerate " fps " -i " inPattern " -vf " q scaleFilter q " -c:v libx264 -pix_fmt yuv420p -crf " crf " " out
        case "WebM":
            cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -c:v libvpx -pix_fmt yuv420p -auto-alt-ref 0 -b:v 1M -crf " crf " " out
            if scaleFilter != ""
                cmd1 := "-y -framerate " fps " -i " inPattern audioArgs " -vf " q scaleFilter q " -c:v libvpx -pix_fmt yuv420p -auto-alt-ref 0 -b:v 1M -crf " crf " " out
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
    scaleFilter := BuildScaleFilter(tileW, tileH, fitMode, bgColor)
    vf := scaleFilter != "" ? scaleFilter ",tile=" cols "x" rows : "tile=" cols "x" rows
    return "-y -framerate " fps " -start_number " startNum " -i " inPattern " -vf " q vf q " -frames:v 1 " out
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
    nameW := leftW - 280
    if nameW < 220
        nameW := 220
    noteColW := leftW - nameW - 120
    if noteColW < 120
        noteColW := 120
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
    g.chkPNG.Move(rightX + labelW, row2Y + 26, 54)
    g.chkSheet.Move(rightX + 108, row2Y + 26, 62)
    g.sheetCountEdit.Move(rightX + 176, row2Y + 26, 48)
    g.lblSheetCount.Move(rightX + 230, row2Y + 30, 100)

    g.lblSize.Move(rightX, row3Y + 4)
    g.widthEdit.Move(rightX + labelW, row3Y, 74)
    g.lblSizeX.Move(rightX + 128, row3Y + 4)
    g.heightEdit.Move(rightX + 146, row3Y, 74)
    g.lblFit.Move(rightX + 232, row3Y + 4)
    g.fitDDL.Move(rightX + 264, row3Y, 96)

    g.lblFilename.Move(rightX, row4Y + 4)
    g.outEdit.Move(rightX + labelW, row4Y, 176)
    g.chkTimestamp.Move(rightX + 236, row4Y + 2, 64)

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
    if !g.HasProp("_lvCol3") || g._lvCol3 != 65 {
        g.lv.ModifyCol(3, 65)
        g._lvCol3 := 65
        changed := true
    }
    if !g.HasProp("_lvCol4") || g._lvCol4 != noteColW {
        g.lv.ModifyCol(4, noteColW)
        g._lvCol4 := noteColW
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

BeginListUpdate(g) {
    if !g.HasProp("_lvUpdateDepth")
        g._lvUpdateDepth := 0
    g._lvUpdateDepth += 1
    if g._lvUpdateDepth = 1
        SetListViewRedraw(g.lv, false)
}

EndListUpdate(g) {
    if !g.HasProp("_lvUpdateDepth") || g._lvUpdateDepth < 1
        return
    g._lvUpdateDepth -= 1
    if g._lvUpdateDepth = 0
        SetListViewRedraw(g.lv, true)
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
    try FileDelete(_LAST_PROJECT_FILE)
    FileAppend(path, _LAST_PROJECT_FILE)
    IniWrite(_imageList.Length, path, "Files", "Count")
    for i, item in _imageList {
        prefix := "Item" i
        IniWrite(item.path, path, "Files", prefix "_Path")
        IniWrite(item.exposure, path, "Files", prefix "_Exposure")
        IniWrite(item.type, path, "Files", prefix "_Type")
        IniWrite(item.HasProp("frameCount") ? item.frameCount : 0, path, "Files", prefix "_FrameCount")
        IniWrite(item.HasProp("durationSec") ? item.durationSec : 0, path, "Files", prefix "_DurationSec")
        IniWrite(item.HasProp("previewFrame") ? item.previewFrame : 1, path, "Files", prefix "_PreviewFrame")
        IniWrite(item.HasProp("note") ? item.note : "", path, "Files", prefix "_Note")
    }
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
        g.fpsEdit.Value := IniRead(path, "Settings", "FPS", "24")
        g.widthEdit.Value := IniRead(path, "Settings", "Width", "1920")
        g.heightEdit.Value := IniRead(path, "Settings", "Height", "1080")
        g.outEdit.Value := IniRead(path, "Settings", "OutName", "animation")
        g.dirEdit.Value := IniRead(path, "Settings", "OutputDir", _OUTPUT_DIR)
        g.chkGIF.Value := Integer(IniRead(path, "Settings", "FmtGIF", "1"))
        g.chkMP4.Value := Integer(IniRead(path, "Settings", "FmtMP4", "1"))
        g.chkAVI.Value := Integer(IniRead(path, "Settings", "FmtAVI", "0"))
        g.chkWebM.Value := Integer(IniRead(path, "Settings", "FmtWebM", "0"))
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

        count := Integer(IniRead(path, "Files", "Count", "0"))
        _imageList := []
        Loop count {
            prefix := "Item" A_Index
            itemPath := IniRead(path, "Files", prefix "_Path", "")
            if itemPath != "" {
                SplitPath(itemPath, &name)
                itemType := IniRead(path, "Files", prefix "_Type", "image")
                item := {
                    path: itemPath,
                    name: name,
                    exposure: Integer(IniRead(path, "Files", prefix "_Exposure", "2")),
                    type: itemType,
                    note: IniRead(path, "Files", prefix "_Note", "")
                }
                if itemType = "video" {
                    item.frameCount := Integer(IniRead(path, "Files", prefix "_FrameCount", "0"))
                    item.durationSec := Float(IniRead(path, "Files", prefix "_DurationSec", "0"))
                    item.previewFrame := Integer(IniRead(path, "Files", prefix "_PreviewFrame", "1"))
                }
                _imageList.Push(item)
                continue
            }

            ; Backward-compatible loader for older project files.
            raw := IniRead(path, "Files", prefix, "")
            parts := StrSplit(raw, "|||")
            if parts.Length >= 2 {
                SplitPath(parts[1], &name)
                item := {path: parts[1], name: name, exposure: Integer(parts[2]), type: "image", note: parts.Length >= 5 ? parts[5] : ""}
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
        _selectedRow := 0
        SyncListViewToModel(g)
        RefreshTimeline(g)
        UpdatePreview(g)
        g.statText.Value := "Loaded " _imageList.Length " item(s)"
        try FileDelete(_LAST_PROJECT_FILE)
        FileAppend(path, _LAST_PROJECT_FILE)
    } catch {
        MsgBox "Failed to load project file.", "Error", "IconX"
    }
}
