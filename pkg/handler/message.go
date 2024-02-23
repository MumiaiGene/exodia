package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"

	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/message"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

const (
	SELECT_REGION_MESSAGE = "select_region"
	SELECT_CITY_MESSAGE   = "select_city"
)

type MessageHandler struct {
}

type MentionEvent struct {
	Key       string `json:"key"`
	Id        UserId `json:"id"`
	Name      string `json:"name"`
	TenantKey string `json:"tenant_key"`
}

type EventSender struct {
	Type      string `json:"sender_type"`
	Id        UserId `json:"sender_id"`
	TenantKey string `json:"tenant_key"`
}

type EventMessage struct {
	Id       string         `json:"message_id"`
	RootId   string         `json:"root_id"`
	ParentId string         `json:"parent_id"`
	ChatId   string         `json:"chat_id"`
	ChatType string         `json:"chat_type"`
	Type     string         `json:"message_type"`
	Content  string         `json:"content"`
	Mentions []MentionEvent `json:"mentions"`
}

type EventRecvMsg struct {
	Sender  EventSender  `json:"sender"`
	Message EventMessage `json:"message"`
}

type EventRecvMsgRequest struct {
	Event EventRecvMsg `json:"event"`
}

type MessageActionValue struct {
	CardId string `json:"card_id"`
	Type   string `json:"custom_msg_type"`
	Region string `json:"select_region"`
}

type MessageAction struct {
	Tag    string
	Option string
	// TODO: interface
	Value MessageActionValue `json:"value"`
}

type MessageActionRequest struct {
	AppId     string        `json:"app_id"`
	OpenId    string        `json:"open_id"`
	UserId    string        `json:"user_id"`
	ChatId    string        `json:"open_chat_id"`
	MessageId string        `json:"open_message_id"`
	TenantKey string        `json:"tenant_key"`
	Token     string        `json:"token"`
	Action    MessageAction `json:"action"`
}

type PatternFunc func(string, string, string)

type MessageFunc func(req *MessageActionRequest) (int, *message.InteractiveContent, error)

var PatternHandlerMap = map[string]PatternFunc{
	LoginKeyPattern:  LoginHandler,
	PhoneKeyPattern:  PhoneHandler,
	VerifyKeyPattern: VerifyHandler,
	SignUpKeyPattern: SignUpHandler,
}

var MessageHandlerMap = map[string]MessageFunc{
	SELECT_REGION_MESSAGE: SelectRegionHandler,
	SELECT_CITY_MESSAGE:   SelectCityHandler,
}

func (*MessageHandler) Handler(ctx *gin.Context) (int, error) {
	var req EventRecvMsgRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		return http.StatusBadRequest, errors.New("invalid request body")
	}

	recv := req.Event.Sender.Id.OpenId
	if req.Event.Message.ChatId != "" {
		recv = req.Event.Message.ChatId
	}
	if req.Event.Message.Type == "text" {
		var content message.TextContent
		err := json.Unmarshal([]byte(req.Event.Message.Content), &content)
		if err != nil {
			message.SendTextMessage(fmt.Sprintf("invalid message content: %s", err.Error()), recv)
			return http.StatusOK, err
		}

		text := content.Text
		for _, mention := range req.Event.Message.Mentions {
			text = strings.ReplaceAll(text, mention.Key, "")
		}
		text = strings.TrimSpace(text)

		log.Printf("recv msg: %s", text)
		for p, handler := range PatternHandlerMap {
			match, _ := regexp.MatchString(p, text)
			if match {
				go handler(req.Event.Sender.Id.OpenId, text, recv)
				return http.StatusOK, nil
			}
		}
		InvalidHandler(req.Event.Sender.Id.OpenId, text, recv)
	}

	return http.StatusOK, nil
}

func SelectRegionHandler(req *MessageActionRequest) (int, *message.InteractiveContent, error) {
	region_list := make([]message.SelectOption, 0)
	city_list := make([]message.SelectOption, 0)
	for region := range duel.CityMap {
		region_list = append(region_list, message.SelectOption{Text: region, Value: region})
	}
	for city := range duel.CityMap[req.Action.Option] {
		city_list = append(city_list, message.SelectOption{Text: city, Value: city})
	}
	vars := message.LoginSuccessVariable{
		UserId:     duel.GetUserId(req.OpenId),
		OpenId:     req.OpenId,
		RegionText: req.Action.Option,
		CityText:   SelectRegion,
		RegionList: region_list,
		CityList:   city_list,
	}

	resp := &message.InteractiveContent{
		Type: "template",
		Data: message.TemplateData{
			Id:       req.Action.Value.CardId,
			Variable: vars,
		},
	}
	duel.SetCityCode(req.OpenId, duel.CityMap[req.Action.Option][SelectRegion])
	return http.StatusOK, resp, nil
}

func SelectCityHandler(req *MessageActionRequest) (int, *message.InteractiveContent, error) {
	region_list := make([]message.SelectOption, 0)
	city_list := make([]message.SelectOption, 0)
	for region := range duel.CityMap {
		region_list = append(region_list, message.SelectOption{Text: region, Value: region})
	}
	for city := range duel.CityMap[req.Action.Value.Region] {
		city_list = append(city_list, message.SelectOption{Text: city, Value: city})
	}
	vars := message.LoginSuccessVariable{
		UserId:     duel.GetUserId(req.OpenId),
		OpenId:     req.OpenId,
		RegionText: req.Action.Value.Region,
		CityText:   req.Action.Option,
		RegionList: region_list,
		CityList:   city_list,
	}

	resp := &message.InteractiveContent{
		Type: "template",
		Data: message.TemplateData{
			Id:       req.Action.Value.CardId,
			Variable: vars,
		},
	}
	return http.StatusOK, resp, nil
}

func MessageRouteHandler(ctx *gin.Context) {
	var req MessageActionRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	code, resp, err := MessageHandlerMap[req.Action.Value.Type](&req)
	if err != nil {
		ctx.JSON(
			code,
			gin.H{
				"msg": err.Error(),
			},
		)
		return
	}

	ctx.JSON(
		code, resp,
	)
}
