// CsvLintDialogs — app-modal parameter dialogs, ports of the WinForms
// dialogs: SortForm, ColumnSplitForm ("Add column"), ReformatForm,
// DetectColumnsForm (manual detect), ColumnsSelectForm. Each returns true on
// OK with the out-parameters filled (ShowDialog parity).
#pragma once
#import <Cocoa/Cocoa.h>
#include <string>
#include <vector>
#include "engine/CsvDefinition.h"

/// SortForm: column + ascending/descending + on value/length.
bool csvDlgSort(const CsvDefinition &csvdef, int &sortColumn, bool &sortAscending,
                bool &sortValue);

/// ColumnSplitForm: operation code 1=Pad 2=Search&Replace 3=Valid/Invalid
/// 4=Split on character 5=Split on position.
bool csvDlgColumnSplit(const CsvDefinition &csvdef, int &splitCode, int &splitColumn,
                       std::string &param1, std::string &param2, bool &removeOrg);

/// ReformatForm.
bool csvDlgReformat(const CsvDefinition &csvdef, std::string &newSeparator,
                    bool &updateSeparator, std::string &newDateTime,
                    std::string &newDecimal, std::string &replaceCrLf, bool &alignVert);

/// DetectColumnsForm (manual detection parameters).
bool csvDlgDetectColumns(char &sep, std::string &widths, bool &header, int &skip,
                         char &comm);

/// ColumnsSelectForm: ordered selection of column indexes.
bool csvDlgSelectColumns(const CsvDefinition &csvdef, std::vector<int> &selIdx);
