package router

import (
	"encoding/json"
)

const (
	EVENT_RECV_MESSAGE = "im.message.receive_v1"
	EVENT_CLICK_MENU   = "application.bot.menu_v6"

	selectRegionAction = "select_region"
	selectCityAction   = "select_city"

	LoginKeyPattern  = "登录"
	PhoneKeyPattern  = "^(@.+ )*1[0-9]{10}"
	VerifyKeyPattern = "^(@.+ )*[0-9]{5}$"
	LogoutKeyPattern = "登出"
	MatchKeyPattern  = "比赛"

	LoginReply    = "请输入手机号"
	PhoneReply    = "请输入验证码"
	VerifyReply   = "登录成功"
	UnLoggedReply = "请先登录"
	RepeatedReply = "不需要重复登录"

	SelectRegionText = "先选择地区"
)

var EventRouterMap = map[string]BotEventHandler{
	EVENT_RECV_MESSAGE: &MessageHandler{},
	EVENT_CLICK_MENU:   &EventMenuHandler{},
}

type BotEventHandler interface {
	Handler(json.RawMessage) (int, error)
}
