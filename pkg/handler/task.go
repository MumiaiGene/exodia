package handler

import (
	"exodia.cn/pkg/message"
)

const (
	SignUpKeyPattern = "报名"

	SignUpReply = "报名成功"
)

func SignUpHandler(openId string, text string) {
	meta := loadUserMetaData(openId)
	if meta.State != StateLoggedIn {
		message.SendTextMessage(UnLoggedReply, openId)
		return
	}

	message.SendTextMessage(SignUpReply, openId)
}
