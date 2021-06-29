#ifndef EXODIA_DATABASE_H
#define EXODIA_DATABASE_H

#include <fstream>
#include <mutex>
#include <unordered_map>
#include <sqlite3.h>

#include "card_data.h"

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
    mutable std::mutex _update_mutex;

public:
    ExodiaDatabase(/* args */) {}
    ~ExodiaDatabase() {}

    int load_card_database(const char *filename);
    int load_set_strings(const char *filename);

    const CardMap& card_map() const { return _card_map; }

    ExodiaCardData& show_card_data_by_id(unsigned int id);

    template <typename Func> 
    void traverse_card_map(Func func) const {
        // std::lock_guard<std::mutex> lock(_update_mutex);
        for (const auto& kv : _card_map) {
            func(kv.second);
        }
    }
    
};

}

#endif
