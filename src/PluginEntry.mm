// CSVLint.macos — macOS port of the CSV Lint plug-in for Notepad++
// (original Windows plugin by Bas de Reuver, https://github.com/BdR76/CSVLint —
// C#/WinForms; this port is a rewrite against the Nextpad++ macOS plugin API).
//
// PluginEntry.mm — plugin contract: menu items (mirroring the Windows menu
// 1:1), docked-panel registration, notification routing, settings lifecycle.
//
// Column coloring note: the Windows plugin ships a managed ILexer and
// registers "CSVLint" as an external language. The macOS host has no
// external-lexer machinery, so this port colors columns with Scintilla
// INDICATORS instead (the ComparePlus pattern) — self-contained, no host
// changes, coexists with whatever lexer owns the buffer.

#import <Cocoa/Cocoa.h>
#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"
#import "CsvLintPanel.h"
#import "CsvSettingsIO.h"
#include <string>
#include <cstring>

#define PLUGIN_NAME    "CSV Lint"
#define PLUGIN_VERSION "1.0.1"
static const int NB_FUNC = 11;

static NppData  nppData;
static FuncItem funcItem[NB_FUNC];

static uint64_t g_panelHandle  = 0;
static NSView  *sPanelView     = nil;
static bool     sPanelVisible  = false;

// ═══════════════════════════════════════════════════════════════════════════
//  Host helpers
// ═══════════════════════════════════════════════════════════════════════════

static intptr_t npp(uint32_t msg, uintptr_t w = 0, intptr_t l = 0) {
    return nppData._sendMessage(nppData._nppHandle, msg, w, l);
}

static NppHandle getCurScintilla() {
    int which = -1;
    npp(NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return (which == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
}

static intptr_t sci(uint32_t msg, uintptr_t w = 0, intptr_t l = 0) {
    return nppData._sendMessage(getCurScintilla(), msg, w, l);
}

static void notImplemented(const char *what) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *a = [NSAlert new];
        a.messageText = @PLUGIN_NAME;
        a.informativeText = [NSString stringWithFormat:
            @"\"%s\" is not implemented yet in this port preview.", what];
        [a runModal];
    });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Docked panel (placeholder — real UI lands in the panel phase)
// ═══════════════════════════════════════════════════════════════════════════

static void ensurePanelView() {
    if (sPanelView) return;
    sPanelView = csvPanelView();
}

static bool panelIsShown() {
    return sPanelView && sPanelView.window != nil && !sPanelView.hiddenOrHasHiddenAncestor;
}

static void toggleLintWindow() {
    ensurePanelView();
    if (g_panelHandle == 0) {
        intptr_t h = npp(NPPM_DMM_REGISTERPANEL,
                         (uintptr_t)(__bridge void *)sPanelView,
                         (intptr_t)"CSV Lint");
        if (h > 0) g_panelHandle = (uint64_t)h;
    }
    if (g_panelHandle == 0) { notImplemented("CSV Lint window (docking unavailable)"); return; }

    bool targetShown = !panelIsShown();
    sPanelVisible = targetShown;
    npp(NPPM_SETMENUITEMCHECK, (uintptr_t)funcItem[0]._cmdID, targetShown ? 1 : 0);
    npp(targetShown ? NPPM_DMM_SHOWPANEL : NPPM_DMM_HIDEPANEL, (uintptr_t)g_panelHandle, 0);
    if (targetShown) csvPanelOnBufferActivated();
}

// ═══════════════════════════════════════════════════════════════════════════
//  Menu commands (stubs where the phase hasn't landed yet)
// ═══════════════════════════════════════════════════════════════════════════

static void cmdLintWindow()       { toggleLintWindow(); }
static void cmdAnalyseReport()    { csvPanelAnalyseReport(); }
static void cmdSelectColumns()    { csvPanelSelectColumns(); }
static void cmdConvertData()      { csvPanelConvertData(); }
static void cmdGenerateMetadata() { csvPanelGenerateMetadata(); }
static void cmdSettings()         { csvPanelShowSettings(); }

static void cmdDocumentation() {
    // Same URL as the Windows plugin's Documentation menu item.
    [[NSWorkspace sharedWorkspace] openURL:
        [NSURL URLWithString:@"https://github.com/BdR76/CSVLint/tree/master/"
                             @"docs#csv-lint-plug-in-documentation"]];
}

static void cmdAbout() {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *a = [NSAlert new];
        a.messageText = @"CSV Lint v" @PLUGIN_VERSION;
        a.informativeText =
            @"CSV Lint plug-in — check syntax, validate data, reformat and "
            @"convert CSV / fixed-width text files.\n\n"
            @"Original Windows plugin by Bas de Reuver (BdR76).\n"
            @"macOS port for Nextpad++.\n\n"
            @"License: GPL-3.0";
        [a addButtonWithTitle:@"OK"];
        [a addButtonWithTitle:@"Visit GitHub"];
        if ([a runModal] == NSAlertSecondButtonReturn)
            [[NSWorkspace sharedWorkspace] openURL:
                [NSURL URLWithString:@"https://github.com/BdR76/CSVLint"]];
    });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Plugin contract
// ═══════════════════════════════════════════════════════════════════════════

extern "C" NPP_EXPORT void setInfo(NppData data) {
    nppData = data;
    csvPanelInit(&nppData);
    csvSettingsIOInit(&nppData);
    csvSettingsLoad();

    int idx = 0;
    auto addItem = [&](const char *name, PFUNCPLUGINCMD func) {
        strlcpy(funcItem[idx]._itemName, name, NPP_MENU_ITEM_SIZE);
        funcItem[idx]._pFunc = func;
        funcItem[idx]._init2Check = false;
        funcItem[idx]._pShKey = nullptr;
        idx++;
    };
    auto addSep = [&]() { addItem("", nullptr); };

    // 1:1 with the Windows plugin's menu (Main.cs SetCommand table).
    addItem("CSV Lint window",     cmdLintWindow);        // 0
    addSep();                                             // 1
    addItem("Analyse data report", cmdAnalyseReport);     // 2
    addItem("Select columns",      cmdSelectColumns);     // 3
    addSep();                                             // 4
    addItem("Convert data",        cmdConvertData);       // 5
    addItem("Generate metadata",   cmdGenerateMetadata);  // 6
    addSep();                                             // 7
    addItem("Settings",            cmdSettings);          // 8
    addItem("Documentation",       cmdDocumentation);     // 9
    addItem("About",               cmdAbout);             // 10
}

extern "C" NPP_EXPORT const char *getName() {
    return PLUGIN_NAME;
}

extern "C" NPP_EXPORT FuncItem *getFuncsArray(int *nbF) {
    *nbF = NB_FUNC;
    return funcItem;
}

extern "C" NPP_EXPORT void beNotified(SCNotification *n) {
    switch (n->nmhdr.code) {
        case NPPN_READY:
        case NPPN_BUFFERACTIVATED:
            csvPanelOnBufferActivated();
            break;

        case NPPN_FILECLOSED:
            csvPanelOnFileClosed((uintptr_t)n->nmhdr.idFrom);
            break;

        case SCN_MODIFIED:
            if (n->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))
                csvPanelOnModified();
            break;

        case NPPN_SHUTDOWN:
            csvSettingsSave();   // persist dialog-remembered values
            csvPanelShutdown();
            if (g_panelHandle > 0) {
                npp(NPPM_DMM_UNREGISTERPANEL, (uintptr_t)g_panelHandle, 0);
                g_panelHandle = 0;
            }
            sPanelView = nil;
            break;
        default:
            break;
    }
}

extern "C" NPP_EXPORT intptr_t messageProc(uint32_t, uintptr_t, intptr_t) {
    return 1;
}
