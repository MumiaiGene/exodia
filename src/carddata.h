#ifndef EXODIA_CARDDATA_H
#define EXODIA_CARDDATA_H

#include <string>
#include <sqlite3.h>

namespace exodia {

struct ExodiaSetString
{
    /* data */
    unsigned int _id;
    std::string _set_name;
};


class ExodiaCardData
{
private:
    /* data */
    unsigned int _id;            // 卡密
    unsigned int _ot;            // ocg or tcg 1-ocg, 2-tcg, 3-both
    // unsigned int _alias;      // 异画
    unsigned long long _setcode; // 字段
    unsigned int _type;          // 卡片类型（怪兽、同调、速攻等各种类别）
    int _attack;                 // 攻击力
    int _defense;                // 防御力
    unsigned int _level;         // 等级、阶级、link值
    unsigned int _race;          // 种族
    unsigned int _attribute;     // 属性
    // unsigned int _category;   // 效果种类吧大概
    // unsigned int _link_marker;   // link标记
    std::string _name;               // 卡名
    std::string _text;               // 描述

public:
    ExodiaCardData(/* args */) {};
    ~ExodiaCardData() {};

    /* init card data from cdb */
    void init_card_data(unsigned int id, sqlite3_stmt* pStmt);
};

}

#endif