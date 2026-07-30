// CsvLintPanel — the docked CSV Lint window (port of Forms/CsvLintWindow.cs)
// plus the per-file definition registry and the indicator-based column
// coloring that replaces the Windows external lexer.
#pragma once
#import <Cocoa/Cocoa.h>
#include "NppPluginInterfaceMac.h"

/// One-time wiring; `data` must outlive the plugin.
void csvPanelInit(NppData *data);

/// The dockable content view (created lazily).
NSView *csvPanelView(void);

/// NPPN_BUFFERACTIVATED — port of Main.CSVChangeFileTab(): look up / infer the
/// definition for the current file, refresh the panel, recolor.
void csvPanelOnBufferActivated(void);

/// NPPN_FILECLOSED — drop the stored definition (Main.RemoveCSVdef).
void csvPanelOnFileClosed(uintptr_t bufferID);

/// SCN_MODIFIED (insert/delete) — debounced recoloring.
void csvPanelOnModified(void);

/// NPPN_SHUTDOWN — release UI and timers.
void csvPanelShutdown(void);
