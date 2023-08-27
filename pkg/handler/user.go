package handler

import (
	"fmt"
	"log"

	"exodia.cn/pkg/common"
	"exodia.cn/pkg/match"
	"exodia.cn/pkg/message"
	"exodia.cn/pkg/task"
)

const (
	LoginKeyPattern  = "登录"
	PhoneKeyPattern  = "^1[0-9]{10}$"
	VerifyKeyPattern = "^[0-9]{5}$"

	LoginReply    = "请输入手机号"
	PhoneReply    = "请输入验证码"
	VerifyReply   = "登录成功"
	UnLoggedReply = "请先登录"
)

const (
	StateInitial    UserState = 0
	StateWaitPhone  UserState = 1
	StateWaitVerify UserState = 2
	StateLoggedIn   UserState = 3
	StateExpired    UserState = 4
)

type UserState int

var InvalidInputMap = map[UserState]string{
	StateInitial:    "未识别的指令: %s",
	StateWaitPhone:  "手机号格式不正确: %s",
	StateWaitVerify: "验证码不正确: %s",
}

type UserMataData struct {
	UserId string
	State  UserState
	Phone  string
	Token  string
	Sub    *task.Subscribe
}

func LoginHandler(openId string, text string) {
	meta := loadUserMetaData(openId)
	meta.State = StateWaitPhone
	meta.Phone = ""
	meta.Token = ""

	message.SendTextMessage(LoginReply, openId)
}

func PhoneHandler(openId string, text string) {
	meta := loadUserMetaData(openId)
	client := match.NewMatchClient("")

	err := client.SendVerifyCode(text)
	if err != nil {
		message.SendTextMessage(err.Error(), openId)
		return
	}

	meta.State = StateWaitVerify
	meta.Phone = text
	meta.Token = ""

	message.SendTextMessage(PhoneReply, openId)
}

func VerifyHandler(openId string, text string) {
	meta := loadUserMetaData(openId)
	client := match.NewMatchClient("")

	token, err := client.Login(meta.Phone, text)
	if err != nil {
		message.SendTextMessage(err.Error(), openId)
		return
	}

	meta.State = StateLoggedIn
	meta.Token = token

	log.Printf("succeed to get token for %s, token: %s", openId, token)
	message.SendTextMessage(VerifyReply, openId)
}

func InvalidHandler(openId string, text string) {
	meta := loadUserMetaData(openId)

	message.SendTextMessage(fmt.Sprintf(InvalidInputMap[meta.State], text), openId)
}

func loadUserMetaData(openId string) *UserMataData {
	model, _ := common.UserMataCache.LoadEntry(openId)
	if model != nil {
		log.Printf("user id: %s, state: %d", model.(*UserMataData).UserId, model.(*UserMataData).State)
		return model.(*UserMataData)
	}

	meta := &UserMataData{UserId: openId, State: StateInitial}
	common.UserMataCache.SaveEntry(meta.UserId, meta)

	return meta
}
