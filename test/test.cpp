#include <cstdio>
#include <sqlite3.h>
#include <stdlib.h>

// id 卡密
// ot 1-ocg 2-tcg 3-o+t
// alias 异画？
// setcode = 0
// type 卡片类型
// atk = 1600
// def = 5 or link 
// level = 2
// race = 16777216 种族
// attribute = 32 属性
// category = 2147483651 ?
// name = 蛮力攻击实施员
// desc = 效果怪兽2只

static int callback(void *NotUsed, int argc, char **argv, char **azColName)
{
    int i;
    printf("%s = %s\n", azColName[0], argv[0] ? argv[0] : "NULL");
    return 0;
    for (i=0; i<argc; i++) {
        printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
    }
    printf("\n");
    return 0;
}

int main(int argc, char **argv)
{
    sqlite3 *db;
    char *zErrMsg = 0;
    sqlite3_stmt* pStmt;
    int rc = sqlite3_open("conf/cards.cdb", &db);

    if (argc < 2) {
        printf("lack of sql command\n");
        return -1;
    }
    printf("sql: %s\n", argv[1]);
    rc = sqlite3_exec(db, argv[1], callback, 0, &zErrMsg);
    if (rc != 0) {
        printf("sql err: %s\n", zErrMsg);
    }
    // rc = sqlite3_prepare_v2(db, "show tables", -1, &pStmt, 0);
    sqlite3_close(db);

    // int value = 0;
    // char strbuf[256];
    // sscanf("setname\t0x140\t魔救\tアダマシア\n", "%x %240[^\t\n]", &value, strbuf);
    // printf("%d, %s\n", value, strbuf);

    return 0;
}
