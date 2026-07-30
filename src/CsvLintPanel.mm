// CsvLintPanel.mm — docked CSV Lint window + per-file definitions + column
// coloring. UI mirrors Forms/CsvLintWindow.cs: toolbar (Detect columns,
// auto-matic, Apply, Colors, Sort, Add column, Reformat, Validate data, gear),
// editable metadata box (ini lines), output box (double-click jumps to the
// error line/value in the editor).

#import "CsvLintPanel.h"
#include "Scintilla.h"
#include "engine/CsvDefinition.h"
#include "engine/CsvAnalyze.h"
#include "engine/CsvValidate.h"
#include "engine/CsvSchemaIni.h"
#include "engine/CsvEdit.h"
#include "engine/CsvConvert.h"
#import "CsvLintDialogs.h"
#include <map>
#include <string>
#include <chrono>
#import <os/log.h>

// ── state ───────────────────────────────────────────────────────────────────

static NppData *gNpp = nullptr;

static NSView       *sView       = nil;
static NSTextView   *sMetaText   = nil;
static NSTextView   *sOutText    = nil;
static NSButton     *sApplyBtn   = nil;
static NSButton     *sAutoChk    = nil;
static NSButton     *sColorsBtn  = nil;
static id            sTextObserver = nil;
static dispatch_block_t sRecolorPending = nil;

static std::map<std::string, CsvDefinition> sFileCsvDef;   // Main.FileCsvDef
static std::map<std::string, bool>          sFileColorsOff; // "Aa" toggle per file

// Interim persistence for the auto-matic checkbox (full settings phase later).
static NSString *const kAutoDetectKey = @"CSVLintAutoDetectColumns";

// 12-color presets from upstream extra/CSVLint_12_colors.xml (RRGGBB).
static const int kLightColors[12] = {
    0xC0EFFF, 0xFFFFC0, 0xFFE0FF, 0xA0FFA0, 0xFFC0E0, 0xA0FFFF,
    0xFFE0C0, 0xD0D0FF, 0xCFFFA0, 0xFFACFF, 0x80FFBF, 0xFFC0C0,
};
static const int kDarkColors[12] = {   // dark-neon fgColors as box tints
    0x80BFFF, 0xFFFF80, 0xFFB0FF, 0x80FF80, 0xFF80BF, 0x80FFFF,
    0xFFBF80, 0xC0C0FF, 0xBFFF80, 0xFF80FF, 0x80FFBF, 0xFF8080,
};
static const int kIndicatorBase = 20;   // indicators 20..31

// ── host helpers ────────────────────────────────────────────────────────────

static intptr_t npp(uint32_t msg, uintptr_t w = 0, intptr_t l = 0) {
    return gNpp->_sendMessage(gNpp->_nppHandle, msg, w, l);
}
static NppHandle curSci() {
    int which = -1;
    npp(NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return which == 0 ? gNpp->_scintillaMainHandle : gNpp->_scintillaSecondHandle;
}
static intptr_t sci(uint32_t msg, uintptr_t w = 0, intptr_t l = 0) {
    return gNpp->_sendMessage(curSci(), msg, w, l);
}

static std::string currentFilePath() {
    char buf[4096] = {0};
    npp(NPPM_GETFULLCURRENTPATH, sizeof(buf) - 1, (intptr_t)buf);
    return buf;
}

static std::string currentExtLower() {
    // Note: this host's NPPM_GETEXTPART returns the extension WITHOUT the
    // leading dot (Windows includes it) — normalize to dot-less lowercase.
    char buf[256] = {0};
    npp(NPPM_GETEXTPART, sizeof(buf) - 1, (intptr_t)buf);
    std::string e = buf;
    if (!e.empty() && e[0] == '.') e.erase(0, 1);
    for (auto &c : e) c = (char)tolower((unsigned char)c);
    return e;
}

static std::string documentText() {
    intptr_t len = sci(SCI_GETLENGTH);
    if (len <= 0) return "";
    std::string text((size_t)len, '\0');
    Sci_TextRangeFull tr = {{0, (Sci_Position)len}, &text[0]};
    sci(SCI_GETTEXTRANGEFULL, 0, (intptr_t)&tr);
    return text;
}

static std::string editorEOL() {
    switch (sci(SCI_GETEOLMODE)) {
        case SC_EOL_CR: return "\r";
        case SC_EOL_LF: return "\n";
        default:        return "\r\n";
    }
}

static void setDocumentText(const std::string &text) {
    sci(SCI_SETTEXT, 0, (intptr_t)text.c_str());
}

static std::string elapsedSince(std::chrono::steady_clock::time_point t0) {
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                  std::chrono::steady_clock::now() - t0).count();
    char buf[32];
    snprintf(buf, sizeof buf, "%02lld:%02lld:%02lld.%03lld",
             ms / 3600000, (ms / 60000) % 60, (ms / 1000) % 60, ms % 1000);
    return buf;
}

static void setOutput(const std::string &s) {
    sOutText.string = [NSString stringWithUTF8String:s.c_str()] ?: @"";
}

// ── column coloring (indicators — replaces the Windows external lexer) ──────

static int rgbToSci(int rrggbb) {   // Scintilla colours are 0xBBGGRR
    return ((rrggbb & 0xFF) << 16) | (rrggbb & 0xFF00) | ((rrggbb >> 16) & 0xFF);
}

static void setupIndicators() {
    bool dark = npp(NPPM_ISDARKMODEENABLED) != 0;
    const int *palette = dark ? kDarkColors : kLightColors;
    for (int i = 0; i < 12; i++) {
        int ind = kIndicatorBase + i;
        sci(SCI_INDICSETSTYLE, ind, INDIC_FULLBOX);
        sci(SCI_INDICSETFORE, ind, rgbToSci(palette[i]));
        sci(SCI_INDICSETALPHA, ind, dark ? 70 : 130);
        sci(SCI_INDICSETOUTLINEALPHA, ind, 0);
        sci(SCI_INDICSETUNDER, ind, 1);
    }
}

static void clearColors() {
    intptr_t len = sci(SCI_GETLENGTH);
    for (int i = 0; i < 12; i++) {
        sci(SCI_SETINDICATORCURRENT, kIndicatorBase + i);
        sci(SCI_INDICATORCLEARRANGE, 0, len);
    }
}

/// Offset-aware value scanner for coloring: same quote/separator rules as the
/// parser, but tracking byte ranges instead of extracting values.
static void applyColumnColors() {
    std::string path = currentFilePath();
    auto it = sFileCsvDef.find(path);
    if (it == sFileCsvDef.end()) return;
    CsvDefinition &def = it->second;

    intptr_t len = sci(SCI_GETLENGTH);
    clearColors();

    if (sFileColorsOff[path]) return;
    if (def.Fields.empty()) return;
    if (def.Fields.size() == 1 && def.Fields[0].MaxWidth >= 9999) return;   // not tabular
    if (len > csvSettings().AutoSyntaxLimit) return;

    std::string text = documentText();
    const char quoteChar = csvSettings().DefaultQuoteChar;
    size_t p = 0;
    int skip = def.SkipLines;

    auto fill = [&](size_t start, size_t end, int col) {
        if (end <= start) return;
        sci(SCI_SETINDICATORCURRENT, kIndicatorBase + (col % 12));
        sci(SCI_INDICATORFILLRANGE, start, end - start);
    };

    while (p < text.size()) {
        // skip-lines and comment lines stay uncolored
        bool lineSkipped = false;
        if (skip > 0) {
            skip--;
            lineSkipped = true;
        } else if (def.CommentChar != '\0' && text[p] == def.CommentChar) {
            lineSkipped = true;
        }
        if (lineSkipped) {
            while (p < text.size() && text[p] != '\n') p++;
            if (p < text.size()) p++;
            continue;
        }

        if (def.Separator == '\0') {
            // fixed width: cumulative widths
            size_t lineStart = p;
            size_t lineEnd = p;
            while (lineEnd < text.size() && text[lineEnd] != '\n' && text[lineEnd] != '\r')
                lineEnd++;
            size_t colStart = lineStart;
            for (size_t c = 0; c < def.FieldWidths.size() && colStart < lineEnd; c++) {
                size_t colEnd = colStart + (size_t)def.FieldWidths[c];
                if (colEnd > lineEnd) colEnd = lineEnd;
                fill(colStart, colEnd, (int)c);
                colStart = colEnd;
            }
            // overflow tail = one extra column
            if (colStart < lineEnd) fill(colStart, lineEnd, (int)def.FieldWidths.size());
            p = lineEnd;
            if (p < text.size() && text[p] == '\r') p++;
            if (p < text.size() && text[p] == '\n') p++;
        } else {
            // delimited: walk one line (quoted values may span lines)
            int col = 0;
            size_t valStart = p;
            bool inQuote = false;
            bool atValueStart = true;
            while (p < text.size()) {
                char ch = text[p];
                if (inQuote) {
                    if (ch == quoteChar) {
                        if (p + 1 < text.size() && text[p + 1] == quoteChar) p++;   // escaped ""
                        else inQuote = false;
                    }
                } else if (ch == quoteChar && atValueStart) {
                    inQuote = true;
                    atValueStart = false;
                } else if (ch == def.Separator) {
                    fill(valStart, p, col);
                    col++;
                    valStart = p + 1;
                    atValueStart = true;
                } else if (ch == '\n' || ch == '\r') {
                    break;
                } else if (ch != ' ') {
                    atValueStart = false;
                }
                p++;
            }
            fill(valStart, p, col);
            if (p < text.size() && text[p] == '\r') p++;
            if (p < text.size() && text[p] == '\n') p++;
        }
    }
}

static void scheduleRecolor() {
    if (sRecolorPending) dispatch_block_cancel(sRecolorPending);
    sRecolorPending = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        sRecolorPending = nil;
        setupIndicators();
        applyColumnColors();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), sRecolorPending);
}

// ── panel content updates ───────────────────────────────────────────────────

/// SetCsvDefinition: show the definition (with the "unable to detect" banner)
/// in the metadata box; enable/disable Apply.
static void setCsvDefinitionText(CsvDefinition &csvdef, bool applybtn) {
    std::string msg;
    if (csvdef.ScanState == CsvScanState::TooBig) {
        msg += "; *********************************\r\n";
        msg += "; File is too large for CsvLint to analyze\r\n";
        msg += "; *********************************\r\n";
    } else if (csvdef.Fields.size() == 1 &&
               csvdef.Fields[0].DataType == ColumnType::String &&
               csvdef.Fields[0].MaxWidth >= 9999) {
        msg += "; *********************************\r\n";
        msg += "; Unable to detect column separator\r\n";
        msg += "; *********************************\r\n";
    }
    std::string text = msg + csvdef.GetIniLines();
    sMetaText.string = [NSString stringWithUTF8String:text.c_str()] ?: @"";
    sApplyBtn.enabled = applybtn;
}

/// Main.UpdateCSVChanges: store per-file definition, recolor, optionally save
/// the schema.ini section.
static void updateCSVChanges(CsvDefinition &csvdef, bool saveini) {
    std::string path = currentFilePath();
    sFileCsvDef[path] = csvdef;

    setupIndicators();
    applyColumnColors();

    os_log(OS_LOG_DEFAULT, "[CSVLint] updateCSVChanges %{public}s saveini=%d", path.c_str(), (int)saveini);
    if (saveini) {
        std::string errmsg;
        CsvDefinition stored = csvdef;   // GetIniLines is non-const (NumberDigits recompute)
        if (!CsvSchemaIni::WriteIniSection(path, stored.GetIniLines(), errmsg)) {
            NSAlert *a = [NSAlert new];
            a.messageText = @"Error saving schema.ini";
            a.informativeText = [NSString stringWithUTF8String:errmsg.c_str()] ?: @"";
            [a runModal];
        }
    }
}

/// Main.CheckValidCsvDef
static bool checkValidCsvDef(const CsvDefinition &csvdef, const char *action) {
    if (csvdef.Fields.empty() ||
        (csvdef.Fields[0].DataType == ColumnType::String && csvdef.Fields[0].MaxWidth >= 9999)) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Missing csv metadata";
        a.informativeText = [NSString stringWithFormat:
            @"Cannot %s without valid csv metadata.\nOpen the CSV Lint window, "
            @"press [Detect columns] and try again.", action];
        [a runModal];
        return false;
    }
    return true;
}

static CsvDefinition definitionFromMetaText(std::string *outError) {
    std::string text = sMetaText.string.UTF8String ?: "";
    return CsvDefinition::FromIniLines(text, outError);
}

// ── actions (target object) ─────────────────────────────────────────────────

@interface CsvLintPanelActions : NSObject
- (void)detectColumns:(id)sender;
- (void)applyMeta:(id)sender;
- (void)toggleColors:(id)sender;
- (void)validateData:(id)sender;
- (void)autoDetectToggled:(id)sender;
- (void)notYet:(id)sender;
- (void)openSettings:(id)sender;
@end

static CsvLintPanelActions *sActions = nil;

static void detectColumnsNow(bool userRequested) {
    bool autodetect = [sAutoChk state] == NSControlStateValueOn;
    char sep = '\0';
    std::string widths;
    bool header = false;
    int skip = 0;
    char comm = csvSettings().CommentCharacter;

    // manual override auto-detect (DetectColumnsForm)
    if (!autodetect) {
        if (!csvDlgDetectColumns(sep, widths, header, skip, comm)) return;
    }

    setOutput("");
    auto t0 = std::chrono::steady_clock::now();

    std::string text = documentText();
    CsvDefinition csvdef = CsvAnalyze::InferFromData(
        text, autodetect, sep, widths, header, skip, comm,
        userRequested, /*isCsv*/true);

    updateCSVChanges(csvdef, false);
    setCsvDefinitionText(csvdef, true);
    setOutput("Detecting columns from data is ready, time elapsed " + elapsedSince(t0));
    NSLog(@"[CSVLint] detect: sep=%d cols=%zu header=%d", (int)csvdef.Separator,
          csvdef.Fields.size(), (int)csvdef.ColNameHeader);
}

@implementation CsvLintPanelActions

- (void)detectColumns:(id)sender { detectColumnsNow(true); }

- (void)applyMeta:(id)sender {
    std::string err;
    CsvDefinition csvdef = definitionFromMetaText(&err);
    if (!err.empty()) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Error in schema.ini";
        a.informativeText = [NSString stringWithUTF8String:err.c_str()] ?: @"";
        [a runModal];
        return;
    }
    if (!csvdef.Fields.empty()) {
        updateCSVChanges(csvdef, true);
        setCsvDefinitionText(csvdef, false);
    }
}

- (void)toggleColors:(id)sender {
    std::string path = currentFilePath();
    sFileColorsOff[path] = !sFileColorsOff[path];
    setupIndicators();
    applyColumnColors();
}

- (void)validateData:(id)sender {
    setOutput("");
    std::string err;
    CsvDefinition csvdef = definitionFromMetaText(&err);
    if (!err.empty() || !checkValidCsvDef(csvdef, "validate data")) return;

    auto t0 = std::chrono::steady_clock::now();
    std::string text = documentText();
    TextReader rd(text);
    CsvValidate csvval;
    csvval.ValidateData(rd, csvdef, elapsedSince(t0));
    setOutput(csvval.Report());
    NSLog(@"[CSVLint] validate: %zu log lines", csvval.log().size());
}

- (void)autoDetectToggled:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:([sAutoChk state] == NSControlStateValueOn)
                                            forKey:kAutoDetectKey];
}

- (void)sortClicked:(id)sender {
    std::string err;
    CsvDefinition csvdef = definitionFromMetaText(&err);
    if (!err.empty() || !checkValidCsvDef(csvdef, "sort data")) return;

    int idx = 0; bool asc = true, val = true;
    if (!csvDlgSort(csvdef, idx, asc, val)) return;

    setOutput("");
    auto t0 = std::chrono::steady_clock::now();
    std::string text = documentText();
    std::string sortErr;
    std::string outText = CsvEdit::SortData(text, csvdef, idx, asc, val, editorEOL(), &sortErr);
    if (!sortErr.empty()) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Sort on column error";
        a.informativeText = [NSString stringWithUTF8String:sortErr.c_str()] ?: @"";
        [a runModal];
        return;
    }
    setDocumentText(outText);
    std::string colname = csvdef.Fields[idx].Name;
    setOutput("Sort data " + std::string(asc ? "a" : "de") + "scending on column '" +
              colname + "' is ready, time elapsed " + elapsedSince(t0) + "\r\n");
    setupIndicators();
    applyColumnColors();
}

- (void)addColumnClicked:(id)sender {
    std::string err;
    CsvDefinition csvdef = definitionFromMetaText(&err);
    if (!err.empty() || !checkValidCsvDef(csvdef, "add new column")) return;

    int cod = 0, idx = 0; std::string par1, par2; bool rem = false;
    if (!csvDlgColumnSplit(csvdef, cod, idx, par1, par2, rem)) return;

    setOutput("");
    auto t0 = std::chrono::steady_clock::now();
    std::string text = documentText();
    CsvDefinition csvnew;
    std::string outText = CsvEdit::ColumnSplit(text, csvdef, idx, cod, par1, par2, rem,
                                               editorEOL(), csvnew);
    setDocumentText(outText);

    std::string msg;
    if (cod == 1) msg = "was padded with \"" + par1 + "\"";
    if (cod == 2) msg = "search \"" + par1 + "\" replace with \"" + par2 + "\"";
    if (cod == 3) msg = "was split on valid and invalid values";
    if (cod == 4) msg = "was split on character " + par1;
    if (cod == 5) msg = "was split on position " + par1;
    if (rem)      msg = msg + (msg.empty() ? "" : "and original column ") + "was removed";
    msg = "Column \"" + csvdef.Fields[idx].Name + "\" " + msg + "\r\n";
    msg += "Add new column is ready, time elapsed " + elapsedSince(t0) + "\r\n";
    setOutput(msg);

    // refresh definition from the changed data (Windows re-runs detect)
    detectColumnsNow(true);
    setOutput(msg);
}

- (void)reformatClicked:(id)sender {
    setOutput("");
    std::string err;
    CsvDefinition csvdef = definitionFromMetaText(&err);
    if (!err.empty() || !checkValidCsvDef(csvdef, "reformat data")) return;

    std::string newSep, newDt, newDec, replCrLf;
    bool updSep = false, alignVert = false;
    if (!csvDlgReformat(csvdef, newSep, updSep, newDt, newDec, replCrLf, alignVert)) return;

    auto t0 = std::chrono::steady_clock::now();
    std::string text = documentText();
    std::string outText = CsvEdit::ReformatDataFile(text, csvdef, newSep, updSep, newDt,
                                                    newDec, replCrLf, alignVert, editorEOL());
    setDocumentText(outText);

    const CsvSettings &st = csvSettings();
    std::string msg;
    if (updSep) {
        std::string oldsep = csvdef.Separator == '\0' ? "{Fixed width}"
                             : (csvdef.Separator == '\t' ? "{Tab}"
                                                          : std::string(1, csvdef.Separator));
        std::string newsepTxt = (newSep.empty() || newSep[0] == '\0') ? "{Fixed width}"
                                : (newSep == "\t" ? "{Tab}" : newSep);
        if (!newSep.empty() && newSep[0] == '\0') csvdef.ColNameHeader = false;
        msg += "Reformat column separator from " + oldsep + " to " + newsepTxt + "\r\n";
        csvdef.Separator = newSep.empty() ? '\0' : newSep[0];
    }
    if (!newDt.empty()) {
        msg += "Reformat datetime format from \"" + csvdef.DateTimeFormat + "\" to \"" +
               newDt + "\"\r\n";
        csvdef.DateTimeFormat = newDt;
        for (auto &col : csvdef.Fields)
            if (col.DataType == ColumnType::DateTime) col.UpdateDateTimeMask(newDt);
    }
    if (!newDec.empty()) {
        msg += "Reformat decimal separator from " + std::string(1, csvdef.DecimalSymbol) +
               " to " + newDec + "\r\n";
        csvdef.DecimalSymbol = newDec[0];
    }
    if (st.TrimValues || st.ReformatQuotes > 0) {
        msg += "General settings: ";
        if (st.TrimValues) msg += "Trim all values";
        if (st.ReformatQuotes > 0) {
            std::string quotetxt = "None / Minimal";
            if (st.ReformatQuotes == 1) quotetxt = "Values with spaces";
            if (st.ReformatQuotes == 2) quotetxt = "All string values";
            if (st.ReformatQuotes == 3) quotetxt = "All non-numeric values";
            if (st.ReformatQuotes == 4) quotetxt = "All values";
            if (st.TrimValues) msg += ", ";
            msg += "apply quotes: " + quotetxt;
        }
        msg += "\r\n";
    }
    msg += "Reformat data is ready, time elapsed " + elapsedSince(t0) + "\r\n";
    setOutput(msg);

    updateCSVChanges(csvdef, false);
    setCsvDefinitionText(csvdef, true);
}

- (void)notYet:(id)sender {
    NSString *what = [sender isKindOfClass:[NSButton class]] ? [(NSButton *)sender title] : @"This";
    NSAlert *a = [NSAlert new];
    a.messageText = @"CSV Lint";
    a.informativeText = [NSString stringWithFormat:
        @"\"%@\" arrives with the edit-operations milestone.", what];
    [a runModal];
}

- (void)openSettings:(id)sender {
    NSAlert *a = [NSAlert new];
    a.messageText = @"CSV Lint";
    a.informativeText = @"Settings window arrives with the settings milestone.";
    [a runModal];
}

@end

// ── output box: double-click jumps to the error line/value ──────────────────

static void outputDoubleClicked(NSTextView *tv) {
    NSString *all = tv.string;
    NSRange selr = tv.selectedRange;
    // find the clicked line's bounds
    NSRange lineRange = [all lineRangeForRange:NSMakeRange(selr.location, 0)];
    NSString *lineText = [all substringWithRange:lineRange];

    // log line format: "** error line 123: Column 4 value "x" ..."
    NSRange startR = [lineText rangeOfString:@"** error line"];
    NSRange colonR = [lineText rangeOfString:@":"];
    if (startR.location == NSNotFound || colonR.location == NSNotFound ||
        startR.location >= colonR.location) return;

    NSString *numStr = [lineText substringWithRange:
        NSMakeRange(startR.location + 13, colonR.location - startR.location - 13)];
    int linenumber = numStr.intValue;
    if (linenumber <= 0) return;

    std::string errval;
    NSRange valR = [lineText rangeOfString:@" value \""];
    if (valR.location != NSNotFound) {
        NSUInteger vpos = valR.location + valR.length;
        NSRange endR = [lineText rangeOfString:@"\""
                                       options:0
                                         range:NSMakeRange(vpos, lineText.length - vpos)];
        if (endR.location != NSNotFound)
            errval = [lineText substringWithRange:NSMakeRange(vpos, endR.location - vpos)]
                         .UTF8String ?: "";
    }

    sci(SCI_GOTOLINE, linenumber - 1);
    if (!errval.empty()) {
        intptr_t cur = sci(SCI_GETCURRENTPOS);
        intptr_t anc = sci(SCI_GETANCHOR);
        sci(SCI_SETTARGETSTART, (uintptr_t)(cur > anc ? cur : anc));
        sci(SCI_SETTARGETEND, (uintptr_t)sci(SCI_GETLINEENDPOSITION, linenumber - 1));
        sci(SCI_SETSEARCHFLAGS, 0);
        intptr_t selpos = sci(SCI_SEARCHINTARGET, errval.size(), (intptr_t)errval.c_str());
        if (selpos != -1) sci(SCI_SETSELECTION, selpos, selpos + (intptr_t)errval.size());
    }
    // give focus back to the editor so the selection is visible
    [[sView window] makeFirstResponder:nil];
}

@interface CsvOutputTextView : NSTextView
@end
@implementation CsvOutputTextView
- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    if (event.clickCount == 2) outputDoubleClicked(self);
}
@end

// ── view construction ───────────────────────────────────────────────────────

static NSButton *makeButton(NSString *title, SEL action, NSView *parent) {
    NSButton *b = [NSButton buttonWithTitle:title target:sActions action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.bezelStyle = NSBezelStyleRounded;
    b.controlSize = NSControlSizeSmall;
    [parent addSubview:b];
    return b;
}

static NSTextView *makeTextArea(NSView *parent, bool editable, NSScrollView **outScroll,
                                Class cls) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *tv = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    tv.editable = editable;
    tv.richText = NO;
    tv.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    tv.autoresizingMask = NSViewWidthSizable;
    tv.allowsUndo = editable;
    scroll.documentView = tv;
    [parent addSubview:scroll];
    *outScroll = scroll;
    return tv;
}

void csvPanelInit(NppData *data) {
    gNpp = data;
}

NSView *csvPanelView(void) {
    if (sView) return sView;
    sActions = [CsvLintPanelActions new];

    sView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 260)];

    // toolbar
    NSButton *detect = makeButton(@"Detect columns", @selector(detectColumns:), sView);

    sAutoChk = [NSButton checkboxWithTitle:@"auto-matic" target:sActions
                                    action:@selector(autoDetectToggled:)];
    sAutoChk.translatesAutoresizingMaskIntoConstraints = NO;
    sAutoChk.controlSize = NSControlSizeSmall;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    sAutoChk.state = ([ud objectForKey:kAutoDetectKey] == nil ||
                      [ud boolForKey:kAutoDetectKey])
                         ? NSControlStateValueOn : NSControlStateValueOff;
    [sView addSubview:sAutoChk];

    sApplyBtn = makeButton(@"Apply", @selector(applyMeta:), sView);
    sApplyBtn.enabled = NO;

    sColorsBtn = makeButton(@"Colors", @selector(toggleColors:), sView);
    NSButton *sort     = makeButton(@"Sort", @selector(sortClicked:), sView);
    NSButton *addcol   = makeButton(@"Add column", @selector(addColumnClicked:), sView);
    NSButton *reformat = makeButton(@"Reformat", @selector(reformatClicked:), sView);
    NSButton *validate = makeButton(@"Validate data", @selector(validateData:), sView);

    NSButton *gear = makeButton(@"", @selector(openSettings:), sView);
    if (@available(macOS 12.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:@"gearshape"
                                 accessibilityDescription:@"Settings"];
        if (img) gear.image = img;
    }
    if (!gear.image) gear.title = @"Settings";

    // text areas in a horizontal split
    NSScrollView *metaScroll, *outScroll;
    sMetaText = makeTextArea(sView, true, &metaScroll, [NSTextView class]);
    sOutText  = makeTextArea(sView, false, &outScroll, [CsvOutputTextView class]);

    // Apply enabled once the metadata text is edited (txtSchemaIni_KeyDown)
    sTextObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSTextDidChangeNotification
                    object:sMetaText
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { sApplyBtn.enabled = YES; }];

    NSDictionary *views = NSDictionaryOfVariableBindings(detect, sort, addcol, reformat,
                                                         validate, gear, metaScroll, outScroll);
    NSMutableDictionary *all = [views mutableCopy];
    all[@"autoChk"] = sAutoChk;
    all[@"applyBtn"] = sApplyBtn;
    all[@"colorsBtn"] = sColorsBtn;

    [NSLayoutConstraint activateConstraints:
        [NSLayoutConstraint constraintsWithVisualFormat:
            @"H:|-8-[detect]-8-[autoChk]-8-[applyBtn]-16-[colorsBtn]-8-[sort]-8-[addcol]-8-"
            @"[reformat]-16-[validate]-(>=8)-[gear]-8-|"
            options:NSLayoutFormatAlignAllCenterY metrics:nil views:all]];
    [NSLayoutConstraint activateConstraints:
        [NSLayoutConstraint constraintsWithVisualFormat:
            @"H:|-4-[metaScroll]-4-[outScroll(>=200)]-4-|"
            options:0 metrics:nil views:all]];
    [NSLayoutConstraint activateConstraints:@[
        [detect.topAnchor constraintEqualToAnchor:sView.topAnchor constant:6],
        [metaScroll.topAnchor constraintEqualToAnchor:detect.bottomAnchor constant:6],
        [metaScroll.bottomAnchor constraintEqualToAnchor:sView.bottomAnchor constant:-4],
        [outScroll.topAnchor constraintEqualToAnchor:metaScroll.topAnchor],
        [outScroll.bottomAnchor constraintEqualToAnchor:metaScroll.bottomAnchor],
        [metaScroll.widthAnchor constraintEqualToAnchor:outScroll.widthAnchor],
    ]];

    return sView;
}

// ── notifications ───────────────────────────────────────────────────────────

void csvPanelOnBufferActivated(void) {
    if (!gNpp) return;
    std::string filename = currentFilePath();
    if (filename.empty()) return;

    bool is_csv = currentExtLower() == "csv";

    auto it = sFileCsvDef.find(filename);
    if (it == sFileCsvDef.end()) {
        CsvDefinition csvdef;
        std::string inilines = CsvSchemaIni::ReadIniSectionLines(filename);
        if (!inilines.empty()) {
            // metadata from previously saved schema.ini
            std::string err;
            csvdef = CsvDefinition::FromIniLines(inilines, &err);
            csvdef.ScanState = CsvScanState::LoadIni;
        } else {
            std::string text = documentText();
            csvdef = CsvAnalyze::InferFromData(text, true, '\0', "", false, 0,
                                               csvSettings().CommentCharacter,
                                               /*userRequested*/false, is_csv);
        }
        it = sFileCsvDef.emplace(filename, csvdef).first;
        os_log(OS_LOG_DEFAULT, "[CSVLint] bufferActivated %{public}s ext=%{public}s: sep=%d cols=%zu scan=%d",
              filename.c_str(), currentExtLower().c_str(),
              (int)csvdef.Separator, csvdef.Fields.size(), (int)csvdef.ScanState);
    }

    setupIndicators();
    applyColumnColors();

    if (sView && sView.window) {
        setCsvDefinitionText(it->second, false);
        setOutput("");
    }
}

void csvPanelOnFileClosed(uintptr_t bufferID) {
    char buf[4096] = {0};
    if (npp(NPPM_GETFULLPATHFROMBUFFERID, bufferID, (intptr_t)buf) > 0 && buf[0]) {
        sFileCsvDef.erase(buf);
        sFileColorsOff.erase(buf);
    }
}

void csvPanelOnModified(void) {
    std::string path = currentFilePath();
    auto it = sFileCsvDef.find(path);
    if (it == sFileCsvDef.end() || it->second.Fields.empty()) return;
    if (sFileColorsOff[path]) return;
    scheduleRecolor();
}

/// The host dispatches NPPM_MENUCOMMAND asynchronously — request the new
/// file, then run `block` only once the current buffer actually changed.
static void newFileThen(void (^block)(void)) {
    intptr_t oldBuf = npp(NPPM_GETCURRENTBUFFERID);
    npp(NPPM_MENUCOMMAND, 0, 41001);   // IDM_FILE_NEW
    __block int attempts = 0;
    __block __weak dispatch_block_t weakTry = nil;
    dispatch_block_t tryRun = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        if (npp(NPPM_GETCURRENTBUFFERID) != oldBuf || ++attempts > 20) {
            block();
        } else {
            dispatch_block_t strongTry = weakTry;
            if (strongTry)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                               dispatch_get_main_queue(), strongTry);
        }
    });
    weakTry = tryRun;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), tryRun);
}

void csvPanelAnalyseReport(void) {
    std::string path = currentFilePath();
    auto it = sFileCsvDef.find(path);
    if (it == sFileCsvDef.end()) return;
    CsvDefinition csvdef = it->second;
    if (!checkValidCsvDef(csvdef, "analyse data")) return;

    std::string text = documentText();

    // ScriptInfo comment lines
    std::vector<std::string> comment;
    size_t slash = path.rfind('/');
    comment.push_back("Nextpad++ CSV Lint plug-in");
    comment.push_back("File: " + (slash == std::string::npos ? path : path.substr(slash + 1)));

    std::string report = CsvAnalyze::StatisticalReport(text, csvdef, comment);

    __block std::string reportCopy = report;
    newFileThen(^{
        setDocumentText(reportCopy);
    });
}

void csvPanelSelectColumns(void) {
    std::string path = currentFilePath();
    auto it = sFileCsvDef.find(path);
    if (it == sFileCsvDef.end()) return;
    CsvDefinition csvdef = it->second;
    if (!checkValidCsvDef(csvdef, "select columns")) return;

    std::vector<int> selIdx;
    if (!csvDlgSelectColumns(csvdef, selIdx)) return;

    std::string text = documentText();
    CsvDefinition csvnew;
    std::string outText = CsvEdit::SelectColumns(text, csvdef, selIdx, editorEOL(), csvnew);

    __block std::string outCopy = outText;
    __block CsvDefinition defCopy = csvnew;
    newFileThen(^{
        setDocumentText(outCopy);
        updateCSVChanges(defCopy, false);   // keyed to the NEW buffer's path now
        if (sView && sView.window) setCsvDefinitionText(defCopy, false);
    });
}

void csvPanelConvertData(void) {
    std::string path = currentFilePath();
    auto it = sFileCsvDef.find(path);
    if (it == sFileCsvDef.end()) return;
    CsvDefinition csvdef = it->second;
    if (!checkValidCsvDef(csvdef, "convert data")) return;

    CsvSettings &st = csvSettings();
    int type = st.DataConvertType;
    std::string tableName = st.DataConvertName;
    int dialect = st.DataConvertSQL;
    int batch = st.DataConvertBatch;
    if (!csvDlgDataConvert(type, tableName, dialect, batch)) return;
    st.DataConvertType = type;
    st.DataConvertName = tableName;
    st.DataConvertSQL = dialect;
    st.DataConvertBatch = batch;

    CsvConvertOptions opt;
    opt.sqlDialect = dialect;
    opt.batchSize = batch;
    opt.tableName = tableName;
    size_t slash = path.rfind('/');
    std::string base = slash == std::string::npos ? path : path.substr(slash + 1);
    size_t dot = base.rfind('.');
    opt.fileNameNoExt = dot == std::string::npos ? base : base.substr(0, dot);
    opt.commentLines = {"Nextpad++ CSV Lint plug-in", "File: " + base};

    std::string text = documentText();
    std::string out;
    int lang = 0;
    switch (type) {
        case 1:  out = CsvConvert::ToXML(text, csvdef, opt);  lang = 9;  break;  // L_XML
        case 2:  out = CsvConvert::ToJSON(text, csvdef, opt); lang = 57; break;  // L_JSON
        default: out = CsvConvert::ToSQL(text, csvdef, opt);  lang = 17; break;  // L_SQL
    }

    __block std::string outCopy = out;
    __block int langCopy = lang;
    __block bool applyLang = (long)out.size() < csvSettings().AutoSyntaxLimit;
    newFileThen(^{
        setDocumentText(outCopy);
        if (applyLang) npp(NPPM_SETCURRENTLANGTYPE, 0, langCopy);
    });
}

void csvPanelShutdown(void) {
    if (sTextObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:sTextObserver];
        sTextObserver = nil;
    }
    if (sRecolorPending) {
        dispatch_block_cancel(sRecolorPending);
        sRecolorPending = nil;
    }
    sView = nil;
    sMetaText = nil;
    sOutText = nil;
    sApplyBtn = nil;
    sAutoChk = nil;
    sColorsBtn = nil;
    sActions = nil;
}
