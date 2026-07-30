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
