package handler

import (
	"fmt"
	"net/http"

	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/message"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

const (
	LoginKeyPattern  = "登录"
	PhoneKeyPattern  = "^(@.+ )*1[0-9]{10}"
	VerifyKeyPattern = "^(@.+ )*[0-9]{5}$"
	LogoutKeyPattern = "登出"

	LoginReply    = "请输入手机号"
	PhoneReply    = "请输入验证码"
	VerifyReply   = "登录成功"
	UnLoggedReply = "请先登录"
	RepeatedReply = "不需要重复登录"

	SelectRegion = "先选择地区"
)

var InvalidInputMap = map[duel.UserState]string{
	duel.StateInitial:    "未识别的指令: %s",
	duel.StateWaitPhone:  "手机号格式不正确: %s",
	duel.StateWaitVerify: "验证码不正确: %s",
}

func LoginHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state == duel.StateLoggedIn {
		message.SendTextMessage(RepeatedReply, recvId)
		return
	}

	duel.PrepareUser(openId)

	message.SendTextMessage(LoginReply, recvId)
}

func PhoneHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateWaitPhone {
		return
	}
	err := duel.SendVerifyCode(openId, text)
	if err != nil {
		message.SendTextMessage(err.Error(), recvId)
		return
	}
	message.SendTextMessage(PhoneReply, recvId)
}

func VerifyHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateWaitVerify {
		return
	}
	err := duel.Login(openId, text)
	if err != nil {
		message.SendTextMessage(err.Error(), recvId)
		return
	}

	region_list := make([]message.SelectOption, 0)
	city_list := make([]message.SelectOption, 0)
	for region := range duel.CityMap {
		region_list = append(region_list, message.SelectOption{Text: region, Value: region})
	}
	city_list = append(city_list, message.SelectOption{Text: SelectRegion, Value: SelectRegion})

	t := message.LoginSuccessVariable{
		OpenId:     openId,
		UserId:     duel.GetUserId(openId),
		RegionText: SelectRegion,
		CityText:   SelectRegion,
		RegionList: region_list,
		CityList:   city_list,
	}

	message.SendInteractive(recvId, message.LoginSuccess, t)
}

func InvalidHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)

	message.SendTextMessage(fmt.Sprintf(InvalidInputMap[state], text), recvId)
}

func ListUserRouter(ctx *gin.Context) {
	users := duel.ListUser()
	code := http.StatusOK
	resp := gin.H{"msg": "ok"}
	if len(users) == 0 {
		code = http.StatusNotFound
		resp["msg"] = "empyt user list"
	}

	resp["users"] = users

	ctx.JSON(
		code, resp,
	)
}

func AddUserRouter(ctx *gin.Context) {
	var new duel.UserMataData
	err := ctx.ShouldBindBodyWith(&new, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	duel.UpdateUser(new.UserId, &new)

	ctx.JSON(
		http.StatusOK,
		gin.H{"msg": "ok"},
	)
}
