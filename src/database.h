#ifndef EXODIA_DATABASE_H
#define EXODIA_DATABASE_H

#include <unordered_map>
#include <sqlite3.h>

#include "carddata.h"

// TODO: instead of gflag temporarily
#define SQL_CARD_DATA "select * from datas,texts where datas.id=texts.id"
#define SET_STRINGS_LEN 256

namespace exodia {

typedef std::unordered_map<unsigned int, ExodiaCardData> CardMap;
typedef std::unordered_map<unsigned int, ExodiaSetString> SetMap;

class ExodiaDatabase
{
private:
    /* data */
    CardMap _card_map;
    SetMap _set_map;

public:
    ExodiaDatabase(/* args */);
    ~ExodiaDatabase();

    int load_card_database(const char *filename);
    int load_set_strings(const char *filename);
    
};

ExodiaDatabase::ExodiaDatabase(/* args */)
{
}

ExodiaDatabase::~ExodiaDatabase()
{
}

int ExodiaDatabase::load_card_database(const char *filename)
{
    sqlite3 *db;
    sqlite3_stmt* pStmt;
    unsigned int id = 0;
    int step = 0;

    if (sqlite3_open(filename, &db) != SQLITE_OK) {
        printf("failed to open cdb file!\n");
        return -1;
    }

    if (sqlite3_prepare_v2(db, SQL_CARD_DATA, -1, &pStmt, 0) != SQLITE_OK) {
        printf("failed to exec sql!\n");
        sqlite3_close(db);
        return -1;
    }

    while ((step = sqlite3_step(pStmt)) != SQLITE_DONE) {
        if (step == SQLITE_BUSY || step == SQLITE_ERROR || step == SQLITE_MISUSE) {
            printf("failed to sql step!\n");
            sqlite3_finalize(pStmt);
            sqlite3_close(db);
            return -1;
        }

        id = sqlite3_column_int(pStmt, 0);
#ifdef DEBUG
        printf("card id: %u\n", id);
#endif
        _card_map[id].init_card_data(id, pStmt);

    }

    sqlite3_finalize(pStmt);
    sqlite3_close(db);
    return 0;
}

int ExodiaDatabase::load_set_strings(const char *filename)
{
    char buf[SET_STRINGS_LEN] = {0};
    std::ifstream file(filename);
    if (!file) {
        return -1;
    }

    while (file.getline(buf, sizeof(buf))) {
        std::string type, id, zh, jp;
        unsigned int set_id;
        std::stringstream line(buf);
        line >> type;
        if (type != "!setname") {
            continue;
        }
        line >> id >> zh >> jp;
        sscanf(id.c_str(), "%x", &set_id);
        // printf("set_id: %u, %s\n", set_id, zh.c_str());
        _set_map[set_id]._id = set_id;
        _set_map[set_id]._set_name = zh;
    }

    return 0;
}

}

#endif
