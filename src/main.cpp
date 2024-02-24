#include <stdlib.h>
#include "database.h"

#define CARD_DATABASE_FILE  "conf/cards.cdb"
#define CARD_STRING_CONF    "conf/strings.conf"

int main(int argc, char **argv)
{
    int ret = 0;
    exodia::ExodiaDatabase db;

    ret = db.load_card_database(CARD_DATABASE_FILE);
    if (ret != 0) {
        printf("load cdb error!\n");
    }
    printf("load cdb successfully!\n");

    ret = db.load_set_strings(CARD_STRING_CONF);
    if (ret != 0) {
        printf("load strings error!\n");
    }
    printf("load strings successfully!\n");

    return 0;
}
