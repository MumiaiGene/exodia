package handler

import (
	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/message"
)

const (
	SignUpKeyPattern = "报名"

	SignUpReply = "报名成功"
)

func SignUpHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateLoggedIn {
		message.SendTextMessage(UnLoggedReply, openId)
		return
	}

	message.SendTextMessage(SignUpReply, openId)
}
