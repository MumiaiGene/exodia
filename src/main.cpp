#include <stdlib.h>
#include <brpc/server.h>
#include "database_service_impl.h"

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

    brpc::Server server;
    exodia::DatabaseServiceImpl service(&db);
    if (server.AddService(&service, brpc::SERVER_DOESNT_OWN_SERVICE) != 0) {
        printf("Fail to add DatabaseService!\n");
        return -1;
    }

    brpc::ServerOptions option;
    if (server.Start(6324, &option) != 0) {
        printf("Fail to start server!\n");
        return -1;
    }

    // Wait until Ctrl-C is pressed
    server.RunUntilAskedToQuit();
    return 0;
}
