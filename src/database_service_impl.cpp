/**
 * @author [gengyishuang]
 * @email [gengyishuang@baidu.com]
 * @create date 2020-12-16 22:47:48
 * @modify date 2020-12-16 22:47:48
 * @desc [description]
 */

#include <brpc/controller.h>
#include "database_service_impl.h"

namespace exodia
{
void DatabaseServiceImpl::Card(google::protobuf::RpcController *controller,
                               const CardRequest *request,
                               CardResponse *response,
                               google::protobuf::Closure *done) {
    
    brpc::ClosureGuard done_guard(done);
    brpc::Controller* cntl = static_cast<brpc::Controller*>(controller);

    response->set_err_no(0);
    response->set_err_msg("success");
}

} // namespace exodia
