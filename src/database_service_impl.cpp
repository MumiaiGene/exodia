/**
 * @author [gengyishuang]
 * @email [gengyishuang@baidu.com]
 * @create date 2020-12-16 22:47:48
 * @modify date 2020-12-16 22:47:48
 * @desc [description]
 */

#include "database_service_impl.h"

#include <brpc/controller.h>


namespace exodia
{
void DatabaseServiceImpl::Card(google::protobuf::RpcController *controller,
                               const CardRequest *request,
                               CardResponse *response,
                               google::protobuf::Closure *done) {
    
    brpc::ClosureGuard done_guard(done);
    brpc::Controller* cntl = static_cast<brpc::Controller*>(controller);

    _db->traverse_card_map([request, response, this] (const ExodiaCardData& data) {
        size_t found = data.name().find(request->name());
        if (found == std::string::npos) {
            return;
        }

        exodia::CardInfo *info = response->add_card_list();
        info->set_id(data.card_id());
        // info->set_type(data.type());
        info->set_name(data.name());
        info->set_text(data.text());
        info->set_type(data.type_string());
        info->set_attribute(data.attr_string());

        if (data.check_card_type((int)ExodiaCardType::TYPE_MONSTER)) {
            // monster cards

            info->set_level(data.level());
            info->set_race(data.race_string());
            info->set_ability(data.ability());
            info->set_attack(data.attack());

            if (!data.check_card_type((int)ExodiaCardType::TYPE_LINK)) {
                info->set_defense(data.defense());
            }

        }
        
    });

    response->set_err_no(0);
    response->set_err_msg("success");
}

} // namespace exodia
