// CsvConvert — port of CsvEdit.cs ConvertToSQL/XML/JSON. Host-free: takes
// document text + definition + options, returns the generated script.
#pragma once
#include <string>
#include <vector>
#include "CsvDefinition.h"

struct CsvConvertOptions {
    int         sqlDialect = 0;    // 0=MySQL/MariaDB 1=MS-SQL 2=PostgreSQL
    int         batchSize  = 1000; // SQL insert / HTML table batch size
    std::string tableName;         // empty = derive from file name
    std::string fileNameNoExt;     // for the default table name + ScriptInfo
    std::string fileName;          // with extension (HTML <title>)
    std::vector<std::string> commentLines;   // ScriptInfo header lines
    // HTML only (generateCSS)
    int         cssStyle   = 1;    // 0=none 1=minimal 2=zebra rows 3=zebra cols
                                   // 4=CSV Lint colors
    int         defaultFg  = 0x000000;   // editor default text color (RRGGBB),
    int         defaultBg  = 0xFFFFFF;   // style 4 body colors
    // Style 4 palette: (fg,bg) RRGGBB per column slot, cycled with nth-child.
    // The Windows original reads these from its lexer styles; the macOS port
    // colors columns with indicators, so the host blends and passes them in.
    std::vector<std::pair<int,int>> columnColors;
};

namespace CsvConvert {

/// CREATE TABLE + batched INSERTs + comment scaffolding.
/// NOTE (C# parity): may downgrade Integer enum columns to String in `csvdef`.
std::string ToSQL(const std::string &text, CsvDefinition &csvdef,
                  const CsvConvertOptions &opt);

std::string ToXML(const std::string &text, CsvDefinition &csvdef,
                  const CsvConvertOptions &opt);

std::string ToJSON(const std::string &text, CsvDefinition &csvdef,
                   const CsvConvertOptions &opt);

/// Standalone HTML document with the data as one <table> per batch.
/// Values are emitted as-is (no date/decimal conversion), HTML-escaped.
std::string ToHTML(const std::string &text, CsvDefinition &csvdef,
                   const CsvConvertOptions &opt);

}  // namespace CsvConvert
