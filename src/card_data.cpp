#include "card_data.h"

#include <iostream>

namespace exodia
{

const uint32_t prefix_mask = 0x49f20f0;
const uint32_t suffix_mask = 0x7;
const uint32_t ability_mask = 0x3601e00;

const char *card_type_map[] {
    "怪兽",
    "魔法",
    "陷阱",
    "",
    "通常",
    "效果",
    "融合",
    "仪式",
    "",
    "灵魂",
    "同盟",
    "二重",
    "调整",
    "同调",
    "",
    "",
    "速攻",
    "永续",
    "装备",
    "场地",
    "反击",
    "反转",
    "卡通",
    "超量",
    "灵摆",
    "特殊召唤",
    "连接",
};

const char *card_attr_map[] {
    "地",
    "水",
    "炎",
    "风",
    "光",
    "暗",
    "神",
    "魔",
    "罠"
};

const char *card_race_map[] {
    "战士",
    "魔法师",
    "天使",
    "恶魔",
    "不死",
    "机械",
    "水",
    "炎",
    "岩石",
    "鸟兽",
    "植物",
    "昆虫",
    "雷",
    "龙",
    "兽",
    "兽战士",
    "恐龙",
    "鱼",
    "海龙",
    "爬虫",
    "念动力",
    "幻神兽",
    "创造神",
    "幻龙",
    "电子界"
};

void ExodiaCardData::init_card_data(unsigned int id, sqlite3_stmt* pStmt)
{
    _card_id = id;
    _ot = sqlite3_column_int(pStmt, 1);
    _alias = sqlite3_column_int(pStmt, 2);
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

const std::string ExodiaCardData::race_string() const 
{
    int index = string_index(_race);
    return card_race_map[index];
}

const std::string ExodiaCardData::attr_string() const 
{
    int index = string_index(_attribute);
    if (check_card_type((int)ExodiaCardType::TYPE_SPELL)) {
        index = (int)ExodiaCardAttribute::ATTRIBUTE_MAGIC;
    } else if (check_card_type((int)ExodiaCardType::TYPE_TRAP)) {
        index = (int)ExodiaCardAttribute::ATTRIBUTE_TRAP;
    }
    
    return card_attr_map[index];
}

int ExodiaCardData::check_card_type(int n) const
{
    return flag_bit_isset(_type, n);
}

const std::string ExodiaCardData::type_string() const
{
    std::string str = std::string("");
    int prefix = string_index(_type & prefix_mask);
    int suffix = string_index(_type & suffix_mask);
    if (prefix < 0) {
        prefix = (int)ExodiaCardType::TYPE_NORMAL;
    }

    if (prefix >= 0 && suffix >= 0) {
        str = std::string(card_type_map[prefix]) + std::string(card_type_map[suffix]);
    }

    return str;
}

const std::string ExodiaCardData::ability() const
{
    uint32_t mask = (uint32_t)1<<(int)ExodiaCardType::TYPE_MAX;
    uint32_t ability = _type & ability_mask;
    int delimiter = 0;
    std::string str = "";
    while (mask) {
        int index = string_index(ability & mask);
        if (index >= 0) {
            if (delimiter) {
                str += std::string("|") + std::string(card_type_map[index]);
            } else {
                str += std::string(card_type_map[index]);
            }
            delimiter = 1;
        }
        mask = mask >> 1;
    }

    if (delimiter == 0 && check_card_type((int)ExodiaCardType::TYPE_EFFECT)) {
        // no ability but effect monster
        int index = (int)ExodiaCardType::TYPE_EFFECT;
        str = std::string(card_type_map[index]);
    }

    return str;
}

} // namespace exodia
