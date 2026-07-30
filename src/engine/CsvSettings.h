// CsvSettings — plain-struct port of Tools/Settings.cs (defaults from its
// DefaultValue attributes). Persistence is host-side; the engine only reads.
#pragma once
#include <string>
#include <ctime>

struct CsvSettings {
    // Analyze
    char        CommentCharacter   = '#';
    int         DecimalDigitsMax   = 20;
    bool        DecimalLeadingZero = true;
    float       ErrorTolerancePerc = 0.01f;   // ErrorTolerance=1 (percent) -> 0.01
    int         IntegerDigitsMax   = 12;
    int         UniqueValuesMax    = 15;
    int         YearMaximum        = 2050;
    int         YearMinimum        = 1900;
    // Edit
    int         ReformatQuotes     = 0;       // 0=minimal 1=spaces 2=strings 3=non-numeric 4=all
    bool        TrimValues         = true;
    int         TwoDigitYearMax    = 0;       // 0 = "CurrentYear" (resolved in ctor)
    // General
    int         AutoSyntaxLimit    = 1024 * 1024;
    char        DefaultQuoteChar   = '"';
    std::string NullKeyword        = "NaN";
    bool        SeparatorColor     = false;
    std::string Separators         = ",;\t|"; // _charSeparators (",;\\t|" unescaped)
    bool        TransparentCursor  = true;

    CsvSettings() {
        std::time_t t = std::time(nullptr);
        std::tm tmv{};
        localtime_r(&t, &tmv);
        TwoDigitYearMax = tmv.tm_year + 1900;  // "CurrentYear" default
    }
};

/// Engine-wide settings instance (the plugin fills it from persisted config).
CsvSettings &csvSettings();
