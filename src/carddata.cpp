#include "carddata.h"

namespace exodia
{

void ExodiaCardData::init_card_data(unsigned int id, sqlite3_stmt* pStmt)
{
    _id = id;
    _ot = sqlite3_column_int(pStmt, 1);
    // _alias = sqlite3_column_int(pStmt, 2);
    _setcode = sqlite3_column_int64(pStmt, 3);
    _type = sqlite3_column_int(pStmt, 4);
    _attack = sqlite3_column_int(pStmt, 5);
    _defense = sqlite3_column_int(pStmt, 6);
    _level = sqlite3_column_int(pStmt, 7);
    _race = sqlite3_column_int(pStmt, 8);
    _attribute = sqlite3_column_int(pStmt, 9);
    // _category = sqlite3_column_int(pStmt, 10);
    _name = (const char*)sqlite3_column_text(pStmt, 12);
    _text = (const char*)sqlite3_column_text(pStmt, 13);
}

} // namespace exodia
