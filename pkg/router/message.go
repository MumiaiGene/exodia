package router

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"

	"exodia.cn/pkg/bot"
	"exodia.cn/pkg/duel"
)

type MessageHandler struct {
}

type PatternFunc func(string, string, string)

var invalidInputMap = map[duel.UserState]string{
	duel.StateInitial:    "未识别的指令: %s",
	duel.StateWaitPhone:  "手机号格式不正确: %s",
	duel.StateWaitVerify: "验证码不正确: %s",
	duel.StateLoggedIn:   "未识别的指令: %s",
}

var patternHandlerMap = map[string]PatternFunc{
	LoginKeyPattern:  loginHandler,
	PhoneKeyPattern:  phoneHandler,
	VerifyKeyPattern: verifyHandler,
	MatchKeyPattern:  matchHandler,
	// SignUpKeyPattern: SignUpHandler,
}

func matchHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateLoggedIn {
		bot.SendTextMessage(UnLoggedReply, recvId)
		return
	}

	listMatchHandler(openId, recvId)
}

func loginHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state == duel.StateLoggedIn {
		bot.SendTextMessage(RepeatedReply, recvId)
		return
	}

	duel.PrepareUser(openId)

	bot.SendTextMessage(LoginReply, recvId)
}

func phoneHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateWaitPhone {
		return
	}
	err := duel.SendVerifyCode(openId, text)
	if err != nil {
		bot.SendTextMessage(err.Error(), recvId)
		return
	}
	bot.SendTextMessage(PhoneReply, recvId)
}

func verifyHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)
	if state != duel.StateWaitVerify {
		return
	}
	err := duel.Login(openId, text)
	if err != nil {
		bot.SendTextMessage(err.Error(), recvId)
		return
	}

	region_list := make([]bot.SelectOption, 0)
	city_list := make([]bot.SelectOption, 0)
	for region := range duel.AreaMap {
		region_list = append(region_list, bot.SelectOption{Text: region, Value: region})
	}
	city_list = append(city_list, bot.SelectOption{Text: SelectRegionText, Value: SelectRegionText})

	t := bot.SelectRegionVariable{
		OpenId:     openId,
		UserId:     duel.GetUserId(openId),
		RegionText: SelectRegionText,
		CityText:   SelectRegionText,
		RegionList: region_list,
		CityList:   city_list,
	}

	bot.SendInteractive(recvId, bot.SelectRegionComponent, t)
}

func invalidHandler(openId string, text string, recvId string) {
	state := duel.GetUserState(openId)

	bot.SendTextMessage(fmt.Sprintf(invalidInputMap[state], text), recvId)
}

func (*MessageHandler) Handler(data json.RawMessage) (int, error) {
	event := &bot.EventRecvMsg{}
	if err := json.Unmarshal(data, event); err != nil {
		return http.StatusBadRequest, err
	}

	recv := event.Sender.Id.OpenId
	if event.Message.ChatId != "" {
		recv = event.Message.ChatId
	}
	if event.Message.Type == "text" {
		var content bot.TextContent
		err := json.Unmarshal([]byte(event.Message.Content), &content)
		if err != nil {
			bot.SendTextMessage(fmt.Sprintf("invalid message content: %s", err.Error()), recv)
			return http.StatusOK, err
		}

		text := content.Text
		for _, mention := range event.Message.Mentions {
			text = strings.ReplaceAll(text, mention.Key, "")
		}
		text = strings.TrimSpace(text)

		log.Printf("recv msg: %s", text)
		for p, handler := range patternHandlerMap {
			match, _ := regexp.MatchString(p, text)
			if match {
				go handler(event.Sender.Id.OpenId, text, recv)
				return http.StatusOK, nil
			}
		}
		invalidHandler(event.Sender.Id.OpenId, text, recv)
	}

	return http.StatusOK, nil
}
