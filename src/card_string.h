#ifndef CARD_STRING_H
#define CARD_STRING_H

namespace exodia
{

inline int string_index(uint32_t flags) {
    int index = -1;
    while (flags) {
        flags = flags >> 1;
        index ++;
    }
    return index;
}

inline int flag_bit_isset(uint32_t flags, int n) {
    return flags & ((uint32_t)1<<n);
}

enum class ExodiaCardType {
    TYPE_MONSTER = 0,
    TYPE_SPELL,
    TYPE_TRAP,
    // TYPE_NONE = 3,

    TYPE_NORMAL = 4,
    TYPE_EFFECT,
    TYPE_FUSION,
    TYPE_RITUAL,

    // TYPE_NONE = 8,
    TYPE_SPIRIT = 9,
    TYPE_UNION,
    TYPE_GEMINI,

    TYPE_TUNER,
    TYPE_SYNCHRO,
    // TYPE_NONE = 14,
    // TYPE_NONE = 15,

    TYPE_QUICK_PLAY = 16,
    TYPE_CONTINUOUS,
    TYPE_EQUIP,
    TYPE_FIELD,

    TYPE_COUNTER,
    TYPE_FLIP,
    TYPE_TOON,
    TYPE_XYZ,

    TYPE_PENDULUM,
    TYPE_SPECIAL,
    TYPE_LINK,

    TYPE_MAX
};

enum class ExodiaCardAttribute {
    ATTRIBUTE_EARTH = 0,
    ATTRIBUTE_WATER,
    ATTRIBUTE_FIRE,
    ATTRIBUTE_WIND,
    ATTRIBUTE_LIGHT,
    ATTRIBUTE_DARK,
    ATTRIBUTE_GOD,
    ATTRIBUTE_MAGIC,
    ATTRIBUTE_TRAP,

    ATTRIBUTE_MAX
};

enum class ExodiaCardRace {
    RACE_WARRIOR = 0,
    RACE_SPELLCASTER,
    RACE_FAIRY,
    RACE_FIEND,
    RACE_ZOMBIE,
    RACE_MACHINE,
    RACE_AQUA,
    RACE_PYRO,
    RACE_ROCK,
    RACE_WINGED_BEAST,
    RACE_PLANT,
    RACE_INSECT,
    RACE_THUNDER,
    RACE_DRAGON,
    RACE_BEAST,
    RACE_BEAST_WARRIOR,
    RACE_DINOSAUR,
    RACE_FISH,
    RACE_SEA_SERPENT,
    RACE_REPTILE,
    RACE_PSYCHIC,
    RACE_DIVINE_BEAST,
    RACE_CREATOR,
    RACE_WYRM,
    RACE_CYBERSE,

    RACE_MAX
};


} // namespace exodia


#endif