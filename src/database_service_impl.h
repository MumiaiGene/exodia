/**
 * @author [gengyishuang]
 * @email [gengyishuang@baidu.com]
 * @create date 2020-12-16 18:12:02
 * @modify date 2020-12-16 18:12:02
 * @desc [http service to find card info from database]
 */


#ifndef EXODIA_DATABASE_SERVICE_IMPL_H
#define EXODIA_DATABASE_SERVICE_IMPL_H

#include "http_api.pb.h"
#include "database.h"

namespace exodia {

class DatabaseServiceImpl : public DatabaseService
{
private:
    /* data */
    ExodiaDatabase *_db;
public:
    explicit DatabaseServiceImpl(ExodiaDatabase *db) : _db(db) {};

    void Card(google::protobuf::RpcController *controller,
              const CardRequest *request,
              CardResponse *response,
              google::protobuf::Closure *done);
};


}

#endif