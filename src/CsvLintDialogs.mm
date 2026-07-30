#import "CsvLintDialogs.h"

// ── shared modal-dialog scaffolding ─────────────────────────────────────────

@interface CsvDlgController : NSObject
@property(nonatomic) NSModalResponse response;
@end
@implementation CsvDlgController
- (void)ok:(id)sender     { [NSApp stopModalWithCode:NSModalResponseOK]; }
- (void)cancel:(id)sender { [NSApp stopModalWithCode:NSModalResponseCancel]; }
- (void)radioPick:(id)sender {}   // shared action so sibling radios group
@end

static NSWindow *makeDialog(NSString *title, CGFloat w, CGFloat h) {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, w, h)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = title;
    win.releasedWhenClosed = NO;
    return win;
}

static NSTextField *addLabel(NSView *v, NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.frame = NSMakeRect(x, y, w, 18);
    l.font = [NSFont systemFontOfSize:12];
    [v addSubview:l];
    return l;
}

static NSTextField *addField(NSView *v, NSString *value, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, w, 22)];
    f.stringValue = value ?: @"";
    f.font = [NSFont systemFontOfSize:12];
    [v addSubview:f];
    return f;
}

static NSPopUpButton *addPopup(NSView *v, NSArray<NSString *> *items,
                               CGFloat x, CGFloat y, CGFloat w) {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, w, 25)
                                                  pullsDown:NO];
    [p addItemsWithTitles:items];
    [v addSubview:p];
    return p;
}

static NSButton *addCheck(NSView *v, NSString *title, bool on,
                          CGFloat x, CGFloat y, CGFloat w) {
    NSButton *c = [NSButton checkboxWithTitle:title target:nil action:nil];
    c.frame = NSMakeRect(x, y, w, 20);
    c.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [v addSubview:c];
    return c;
}

/// OK/Cancel row; returns YES when the user confirmed.
static bool runDialog(NSWindow *win, CsvDlgController *ctl) {
    NSView *v = win.contentView;
    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:ctl action:@selector(ok:)];
    ok.frame = NSMakeRect(v.frame.size.width - 170, 10, 75, 28);
    ok.keyEquivalent = @"\r";
    [v addSubview:ok];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:ctl action:@selector(cancel:)];
    cancel.frame = NSMakeRect(v.frame.size.width - 90, 10, 75, 28);
    cancel.keyEquivalent = @"\033";
    [v addSubview:cancel];

    [win center];
    [win makeKeyAndOrderFront:nil];
    NSModalResponse r = [NSApp runModalForWindow:win];
    [win orderOut:nil];
    return r == NSModalResponseOK;
}

static NSArray<NSString *> *columnTitles(const CsvDefinition &csvdef) {
    NSMutableArray *cols = [NSMutableArray array];
    for (auto &f : csvdef.Fields)
        [cols addObject:[NSString stringWithUTF8String:f.Name.c_str()] ?: @"?"];
    return cols;
}

// ── SortForm ────────────────────────────────────────────────────────────────

bool csvDlgSort(const CsvDefinition &csvdef, int &sortColumn, bool &sortAscending,
                bool &sortValue) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Sort data", 320, 160);
    NSView *v = win.contentView;

    addLabel(v, @"Sort on column:", 15, 125, 120);
    NSPopUpButton *colPopup = addPopup(v, columnTitles(csvdef), 140, 121, 165);

    NSPopUpButton *dirPopup = addPopup(v, @[@"Ascending", @"Descending"], 140, 88, 165);
    addLabel(v, @"Order:", 15, 92, 120);

    NSPopUpButton *valPopup = addPopup(v, @[@"Sort on value", @"Sort on length of value"],
                                       140, 55, 165);
    addLabel(v, @"Sort by:", 15, 59, 120);

    if (!runDialog(win, ctl)) return false;
    sortColumn = (int)colPopup.indexOfSelectedItem;
    sortAscending = dirPopup.indexOfSelectedItem == 0;
    sortValue = valPopup.indexOfSelectedItem == 0;
    return true;
}

// ── ColumnSplitForm ("Add column") ──────────────────────────────────────────

bool csvDlgColumnSplit(const CsvDefinition &csvdef, int &splitCode, int &splitColumn,
                       std::string &param1, std::string &param2, bool &removeOrg) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Add new column", 360, 235);
    NSView *v = win.contentView;

    addLabel(v, @"Column:", 15, 200, 110);
    NSPopUpButton *colPopup = addPopup(v, columnTitles(csvdef), 130, 196, 215);

    addLabel(v, @"Operation:", 15, 167, 110);
    NSPopUpButton *opPopup = addPopup(v, @[
        @"Pad with character (par.1=char, par.2=length)",
        @"Search and replace (par.1=search, par.2=replace)",
        @"Split valid and invalid values",
        @"Split on character (par.1=char, par.2=Nth)",
        @"Split on position (par.2=position)",
    ], 130, 163, 215);

    addLabel(v, @"Parameter 1:", 15, 134, 110);
    NSTextField *p1 = addField(v, @"", 130, 130, 215);
    addLabel(v, @"Parameter 2:", 15, 105, 110);
    NSTextField *p2 = addField(v, @"", 130, 101, 215);

    NSButton *rem = addCheck(v, @"Remove original column", false, 130, 74, 215);

    if (!runDialog(win, ctl)) return false;
    splitCode = (int)opPopup.indexOfSelectedItem + 1;
    splitColumn = (int)colPopup.indexOfSelectedItem;
    param1 = p1.stringValue.UTF8String ?: "";
    param2 = p2.stringValue.UTF8String ?: "";
    removeOrg = rem.state == NSControlStateValueOn;
    return true;
}

// ── ReformatForm ────────────────────────────────────────────────────────────

bool csvDlgReformat(const CsvDefinition &csvdef, std::string &newSeparator,
                    bool &updateSeparator, std::string &newDateTime,
                    std::string &newDecimal, std::string &replaceCrLf, bool &alignVert) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Reformat data", 380, 260);
    NSView *v = win.contentView;

    NSButton *updSep = addCheck(v, @"Change separator to:", false, 15, 222, 160);
    NSPopUpButton *sepPopup = addPopup(v, @[@"Comma ,", @"Semicolon ;", @"Tab", @"Pipe |",
                                            @"Fixed width"], 180, 218, 185);
    // preselect something different from the current separator
    if (csvdef.Separator == ',') [sepPopup selectItemAtIndex:1];

    addLabel(v, @"Datetime format:", 15, 189, 160);
    NSTextField *dtField = addField(v, @"", 180, 185, 185);
    dtField.placeholderString = @"e.g. yyyy-MM-dd (empty = unchanged)";

    addLabel(v, @"Decimal separator:", 15, 156, 160);
    NSPopUpButton *decPopup = addPopup(v, @[@"(unchanged)", @"Point .", @"Comma ,"],
                                       180, 152, 185);

    addLabel(v, @"Replace CR/LF in values by:", 15, 123, 160);
    NSTextField *crlfField = addField(v, @" ", 180, 119, 185);

    NSButton *align = addCheck(v, @"Align columns vertically", false, 180, 92, 185);

    if (!runDialog(win, ctl)) return false;

    static const char *seps[] = {",", ";", "\t", "|", "\0"};
    long sidx = sepPopup.indexOfSelectedItem;
    newSeparator = sidx == 4 ? std::string(1, '\0') : seps[sidx];
    updateSeparator = updSep.state == NSControlStateValueOn;
    newDateTime = dtField.stringValue.UTF8String ?: "";
    long didx = decPopup.indexOfSelectedItem;
    newDecimal = didx == 0 ? "" : (didx == 1 ? "." : ",");
    replaceCrLf = crlfField.stringValue.UTF8String ?: " ";
    alignVert = align.state == NSControlStateValueOn;
    return true;
}

// ── DetectColumnsForm (manual parameters) ───────────────────────────────────

bool csvDlgDetectColumns(char &sep, std::string &widths, bool &header, int &skip,
                         char &comm) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Detect columns parameters", 380, 235);
    NSView *v = win.contentView;

    addLabel(v, @"Separator:", 15, 197, 150);
    NSPopUpButton *sepPopup = addPopup(v, @[@"Comma ,", @"Semicolon ;", @"Tab", @"Pipe |",
                                            @"Fixed width"], 170, 193, 195);

    addLabel(v, @"Fixed widths (comma sep.):", 15, 164, 150);
    NSTextField *widField = addField(v, @"", 170, 160, 195);
    widField.placeholderString = @"e.g. 8, 6, 12";

    NSButton *head = addCheck(v, @"First line contains column names", true, 170, 133, 200);

    addLabel(v, @"Skip first lines:", 15, 104, 150);
    NSTextField *skipField = addField(v, @"0", 170, 100, 60);

    addLabel(v, @"Comment character:", 15, 75, 150);
    NSTextField *commField = addField(v, @"#", 170, 71, 60);

    if (!runDialog(win, ctl)) return false;

    static const char sepChars[] = {',', ';', '\t', '|', '\0'};
    sep = sepChars[sepPopup.indexOfSelectedItem];
    widths = widField.stringValue.UTF8String ?: "";
    header = head.state == NSControlStateValueOn;
    skip = skipField.integerValue >= 0 ? (int)skipField.integerValue : 0;
    NSString *cs = commField.stringValue;
    comm = cs.length ? (char)[cs characterAtIndex:0] : '\0';
    return true;
}

// ── ColumnsSelectForm ───────────────────────────────────────────────────────

@interface CsvColSelectController : CsvDlgController <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NSMutableArray<NSString *> *names;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *checked;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *order;   // original indexes
@property(nonatomic, weak) NSTableView *table;
@end
@implementation CsvColSelectController
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return self.names.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col
                  row:(NSInteger)row {
    NSButton *cb = [tv makeViewWithIdentifier:@"c" owner:nil];
    if (!cb) {
        cb = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggled:)];
        cb.identifier = @"c";
        cb.font = [NSFont systemFontOfSize:12];
    }
    cb.title = self.names[row];
    cb.tag = row;
    cb.state = self.checked[row].boolValue ? NSControlStateValueOn : NSControlStateValueOff;
    return cb;
}
- (void)toggled:(NSButton *)sender {
    if (sender.tag < (NSInteger)self.checked.count)
        self.checked[sender.tag] = @(sender.state == NSControlStateValueOn);
}
- (void)moveUp:(id)sender   { [self move:-1]; }
- (void)moveDown:(id)sender { [self move:+1]; }
- (void)move:(NSInteger)delta {
    NSInteger row = self.table.selectedRow;
    NSInteger dst = row + delta;
    if (row < 0 || dst < 0 || dst >= (NSInteger)self.names.count) return;
    [self.names exchangeObjectAtIndex:row withObjectAtIndex:dst];
    [self.checked exchangeObjectAtIndex:row withObjectAtIndex:dst];
    [self.order exchangeObjectAtIndex:row withObjectAtIndex:dst];
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:dst] byExtendingSelection:NO];
}
- (void)allNone:(id)sender {
    bool anyOff = false;
    for (NSNumber *n in self.checked) if (!n.boolValue) { anyOff = true; break; }
    for (NSUInteger i = 0; i < self.checked.count; i++) self.checked[i] = @(anyOff);
    [self.table reloadData];
}
@end

bool csvDlgSelectColumns(const CsvDefinition &csvdef, std::vector<int> &selIdx) {
    CsvColSelectController *ctl = [CsvColSelectController new];
    ctl.names = [columnTitles(csvdef) mutableCopy];
    ctl.checked = [NSMutableArray array];
    ctl.order = [NSMutableArray array];
    for (NSUInteger i = 0; i < ctl.names.count; i++) {
        [ctl.checked addObject:@YES];
        [ctl.order addObject:@(i)];
    }

    NSWindow *win = makeDialog(@"Select columns", 360, 330);
    NSView *v = win.contentView;

    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(15, 50, 250, 265)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTableView *tv = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = 226;
    [tv addTableColumn:col];
    tv.headerView = nil;
    tv.dataSource = ctl;
    tv.delegate = ctl;
    scroll.documentView = tv;
    [v addSubview:scroll];
    ctl.table = tv;

    NSButton *up = [NSButton buttonWithTitle:@"Up" target:ctl action:@selector(moveUp:)];
    up.frame = NSMakeRect(275, 285, 70, 26);
    [v addSubview:up];
    NSButton *down = [NSButton buttonWithTitle:@"Down" target:ctl action:@selector(moveDown:)];
    down.frame = NSMakeRect(275, 255, 70, 26);
    [v addSubview:down];
    NSButton *all = [NSButton buttonWithTitle:@"All/None" target:ctl action:@selector(allNone:)];
    all.frame = NSMakeRect(275, 225, 70, 26);
    [v addSubview:all];

    if (!runDialog(win, ctl)) return false;

    selIdx.clear();
    for (NSUInteger i = 0; i < ctl.names.count; i++)
        if (ctl.checked[i].boolValue) selIdx.push_back(ctl.order[i].intValue);
    return !selIdx.empty();
}

// ── DataConvertForm ─────────────────────────────────────────────────────────

bool csvDlgDataConvert(int &convertType, std::string &tableName, int &sqlDialect,
                       int &batchSize) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Convert data", 380, 230);
    NSView *v = win.contentView;

    addLabel(v, @"Convert to:", 15, 192, 130);
    NSPopUpButton *typePopup = addPopup(v, @[@"SQL insert script", @"XML", @"JSON"],
                                        150, 188, 215);
    [typePopup selectItemAtIndex:(convertType >= 0 && convertType <= 2) ? convertType : 0];

    addLabel(v, @"Table/record name:", 15, 159, 130);
    NSTextField *nameField = addField(v, [NSString stringWithUTF8String:tableName.c_str()],
                                      150, 155, 215);
    nameField.placeholderString = @"(empty = use file name)";

    addLabel(v, @"SQL type:", 15, 126, 130);
    NSPopUpButton *sqlPopup = addPopup(v, @[@"MySQL / MariaDB", @"MS-SQL", @"PostgreSQL"],
                                       150, 122, 215);
    [sqlPopup selectItemAtIndex:(sqlDialect >= 0 && sqlDialect <= 2) ? sqlDialect : 0];

    addLabel(v, @"SQL batch size:", 15, 93, 130);
    NSTextField *batchField = addField(v, [NSString stringWithFormat:@"%d", batchSize],
                                       150, 89, 90);

    if (!runDialog(win, ctl)) return false;
    convertType = (int)typePopup.indexOfSelectedItem;
    tableName = nameField.stringValue.UTF8String ?: "";
    sqlDialect = (int)sqlPopup.indexOfSelectedItem;
    batchSize = batchField.integerValue > 0 ? (int)batchField.integerValue : 1000;
    return true;
}

// ── MetaDataGenerateForm ────────────────────────────────────────────────────

bool csvDlgGenerateMetadata(int &metadataType) {
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"Generate metadata", 320, 300);
    NSView *v = win.contentView;

    addLabel(v, @"Generate metadata or script", 15, 268, 290);

    NSTextField *sec1 = addLabel(v, @"Generate metadata", 15, 240, 290);
    sec1.font = [NSFont boldSystemFontOfSize:12];

    NSArray<NSString *> *titles = @[
        @"Schema ini", @"W3C CSV schema JSON", @"Datadictionary CSV",
        @"Python script", @"R-script", @"PowerShell"
    ];
    // y positions: metadata group, then "Generate script" section, script group
    CGFloat ys[6] = {216, 194, 172, 116, 94, 72};
    NSMutableArray<NSButton *> *radios = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton *r = [NSButton radioButtonWithTitle:titles[i]
                                              target:ctl
                                              action:@selector(radioPick:)];
        r.frame = NSMakeRect(30, ys[i], 260, 20);
        r.state = ((int)i == metadataType) ? NSControlStateValueOn : NSControlStateValueOff;
        [v addSubview:r];
        [radios addObject:r];
    }

    NSTextField *sec2 = addLabel(v, @"Generate script", 15, 144, 290);
    sec2.font = [NSFont boldSystemFontOfSize:12];

    if (!runDialog(win, ctl)) return false;
    for (NSUInteger i = 0; i < radios.count; i++)
        if (radios[i].state == NSControlStateValueOn) { metadataType = (int)i; break; }
    return true;
}

// ── Settings window (property-grid parity) ──────────────────────────────────

#include "CsvSettingsIO.h"

/// Row helper: label at x=15, control column at x=280.
static const CGFloat kSetLabelW = 255, kSetCtrlX = 280, kSetCtrlW = 240;

static NSTextField *setRowField(NSView *v, NSString *label, NSString *value,
                                CGFloat y, NSString *help) {
    NSTextField *l = addLabel(v, label, 15, y + 3, kSetLabelW);
    NSTextField *f = addField(v, value, kSetCtrlX, y, kSetCtrlW);
    l.toolTip = help;
    f.toolTip = help;
    return f;
}

static NSButton *setRowCheck(NSView *v, NSString *label, bool on, CGFloat y,
                             NSString *help) {
    NSTextField *l = addLabel(v, label, 15, y + 2, kSetLabelW);
    NSButton *c = addCheck(v, @"", on, kSetCtrlX, y, 40);
    l.toolTip = help;
    c.toolTip = help;
    return c;
}

static NSTextField *setSection(NSView *v, NSString *title, CGFloat y) {
    NSTextField *l = addLabel(v, title, 15, y, 200);
    l.font = [NSFont boldSystemFontOfSize:12];
    return l;
}

bool csvDlgSettings(void) {
    CsvSettings &st = csvSettings();
    CsvDlgController *ctl = [CsvDlgController new];
    NSWindow *win = makeDialog(@"CSV Lint Settings", 540, 610);
    NSView *v = win.contentView;

    // ── Analyze ─────────────────────────────────────────────────────────────
    setSection(v, @"Analyze", 578);
    NSTextField *fComment = setRowField(v, @"Comment character:",
        [NSString stringWithFormat:@"%c", st.CommentCharacter], 550,
        @"Comment character, when the first lines start with this character "
        @"they will be skipped as comment lines");
    NSTextField *fDecMax = setRowField(v, @"Decimal digits maximum:",
        [NSString stringWithFormat:@"%d", st.DecimalDigitsMax], 522,
        @"Maximum amount of decimals for decimal values, if a value has more "
        @"then it's considered a text value. Applies to both autodetecting "
        @"datatypes and validating data.");
    NSButton *cLeadZero = setRowCheck(v, @"Decimal leading zero:",
        st.DecimalLeadingZero, 494,
        @"Decimal values must have leading zero, set to false to accept "
        @"values like .5 or .01");
    NSTextField *fErrTol = setRowField(v, @"Error tolerance (%):",
        [NSString stringWithFormat:@"%d", st.ErrorTolerance], 466,
        @"Error tolerance percentage, when analyzing allow X % errors. For "
        @"example when a column with a 1000 values contains all integers "
        @"except for 9 or fewer non-integer values, then it's still "
        @"interpreted as an integer column.");
    NSTextField *fIntMax = setRowField(v, @"Integer digits maximum:",
        [NSString stringWithFormat:@"%d", st.IntegerDigitsMax], 438,
        @"Maximum amount of digits for integer values, if a value has more "
        @"then it's considered a text value. Useful to distinguish (bar)codes "
        @"and actual numeric values.");
    NSTextField *fUnique = setRowField(v, @"Unique values maximum:",
        [NSString stringWithFormat:@"%d", st.UniqueValuesMax], 410,
        @"Maximum unique values when reporting or detecting coded values, if "
        @"column contains more than it's not reported.");
    NSTextField *fYearMax = setRowField(v, @"Year maximum:",
        [NSString stringWithFormat:@"%d", st.YearMaximum], 382,
        @"When detecting or validating date or datetime values, years larger "
        @"than this value will be considered as out-of-range.");
    NSTextField *fYearMin = setRowField(v, @"Year minimum:",
        [NSString stringWithFormat:@"%d", st.YearMinimum], 354,
        @"When detecting or validating date or datetime values, years smaller "
        @"than this value will be considered as out-of-range.");

    // ── Edit ────────────────────────────────────────────────────────────────
    setSection(v, @"Edit", 322);
    NSTextField *lQuotes = addLabel(v, @"Reformat, apply quotes:", 15, 297, kSetLabelW);
    NSPopUpButton *pQuotes = addPopup(v, @[
        @"None, minimal quotes", @"Values with spaces", @"All string values",
        @"All non-numeric values", @"All values"], kSetCtrlX, 292, kSetCtrlW);
    NSString *helpQuotes = @"Reformat dataset, apply quotes option.";
    lQuotes.toolTip = helpQuotes;
    pQuotes.toolTip = helpQuotes;
    if (st.ReformatQuotes >= 0 && st.ReformatQuotes <= 4)
        [pQuotes selectItemAtIndex:st.ReformatQuotes];
    NSButton *cTrim = setRowCheck(v, @"Trim values:", st.TrimValues, 266,
        @"Trim values when editing, sorting or analyzing data. Recommended, "
        @"because when disabled the column datatypes will not always be "
        @"detected correctly.");
    NSTextField *fYear2 = setRowField(v, @"Two digit year maximum:",
        [NSString stringWithUTF8String:st.TwoDigitYearMaxStr.c_str()], 238,
        @"Maximum year for two digit year date values. For example, when set "
        @"to 2030 the year values 30 and 31 will be interpreted as 2030 and "
        @"1931. Set as CurrentYear for current year.");

    // ── General ─────────────────────────────────────────────────────────────
    setSection(v, @"General", 206);
    NSTextField *fSyntax = setRowField(v, @"Auto syntax limit (bytes):",
        [NSString stringWithFormat:@"%d", st.AutoSyntaxLimit], 178,
        @"Automatically apply column colors and result syntax highlighting "
        @"only when the file is smaller than this size, to prevent freezing "
        @"on large files.");
    NSTextField *fQuoteCh = setRowField(v, @"Default quote character:",
        [NSString stringWithFormat:@"%c", st.DefaultQuoteChar], 150,
        @"Default quote character, typically double quote \" or single quote '");
    NSTextField *fNull = setRowField(v, @"Null keyword:",
        [NSString stringWithUTF8String:st.NullKeyword.c_str()], 122,
        @"A case-sensitive keyword that will be treated as an empty value, "
        @"typically NULL, NaN, NA or None depending on your data.");
    NSButton *cSepColor = setRowCheck(v, @"Separator color:", st.SeparatorColor, 94,
        @"Include separator in syntax highlighting colors. Set to false and "
        @"the separator characters are not colored.");
    NSTextField *fSeps = setRowField(v, @"Separators:",
        [NSString stringWithUTF8String:
            csvSettingsEscapeSeparators(st.Separators).c_str()], 66,
        @"Preferred characters when automatically detecting the separator "
        @"character. For special characters like tab, use \\t or hexadecimal "
        @"escape sequence \\u0009 or \\x09.");

    if (!runDialog(win, ctl)) return false;

    auto firstChar = [](NSTextField *f, char dflt) {
        std::string s = f.stringValue.UTF8String ?: "";
        return s.empty() ? dflt : s[0];
    };
    auto intOr = [](NSTextField *f, int dflt, int minv) {
        std::string s = f.stringValue.UTF8String ?: "";
        if (s.empty()) return dflt;
        int n = atoi(s.c_str());
        return n < minv ? dflt : n;
    };

    st.CommentCharacter   = firstChar(fComment, '#');
    st.DecimalDigitsMax   = intOr(fDecMax, 20, 0);
    st.DecimalLeadingZero = cLeadZero.state == NSControlStateValueOn;
    st.ErrorTolerance     = intOr(fErrTol, 1, 0);
    st.ErrorTolerancePerc = 0.01f * st.ErrorTolerance;
    st.IntegerDigitsMax   = intOr(fIntMax, 12, 1);
    st.UniqueValuesMax    = intOr(fUnique, 15, 1);
    st.YearMaximum        = intOr(fYearMax, 2050, 1);
    st.YearMinimum        = intOr(fYearMin, 1900, 1);
    st.ReformatQuotes     = (int)pQuotes.indexOfSelectedItem;
    st.TrimValues         = cTrim.state == NSControlStateValueOn;
    csvSettingsApplyTwoDigitYearMax(fYear2.stringValue.UTF8String ?: "");
    st.AutoSyntaxLimit    = intOr(fSyntax, 1024 * 1024, 1024);
    st.DefaultQuoteChar   = firstChar(fQuoteCh, '"');
    st.NullKeyword        = fNull.stringValue.UTF8String ?: "NaN";
    st.SeparatorColor     = cSepColor.state == NSControlStateValueOn;
    st.Separators         = csvSettingsUnescapeSeparators(fSeps.stringValue.UTF8String ?: "");
    return true;
}
