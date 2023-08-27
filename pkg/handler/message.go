package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"

	"exodia.cn/pkg/message"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
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
	Id       string       `json:"message_id"`
	RootId   string       `json:"root_id"`
	ParentId string       `json:"parent_id"`
	ChatId   string       `json:"chat_id"`
	ChatType string       `json:"chat_type"`
	Type     string       `json:"message_type"`
	Content  string       `json:"content"`
	Mentions MentionEvent `json:"mentions"`
}

type EventRecvMsg struct {
	Sender  EventSender  `json:"sender"`
	Message EventMessage `json:"message"`
}

type EventRecvMsgRequest struct {
	Event EventRecvMsg `json:"event"`
}

type PatternFunc func(string, string)

var PatternHandlerMap = map[string]PatternFunc{
	LoginKeyPattern:  LoginHandler,
	PhoneKeyPattern:  PhoneHandler,
	VerifyKeyPattern: VerifyHandler,
	SignUpKeyPattern: SignUpHandler,
}

func (*MessageHandler) Handler(ctx *gin.Context) (int, error) {
	var req EventRecvMsgRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		return http.StatusBadRequest, errors.New("invalid request body")
	}

	if req.Event.Message.Type == "text" {
		recv := req.Event.Sender.Id.OpenId
		var content message.Content
		err := json.Unmarshal([]byte(req.Event.Message.Content), &content)
		if err != nil {
			message.SendTextMessage(fmt.Sprintf("invalid message content: %s", err.Error()), recv)
			return http.StatusOK, err
		}

		for p, handler := range PatternHandlerMap {
			match, _ := regexp.MatchString(p, content.Text)
			if match {
				go handler(recv, content.Text)
				return http.StatusOK, nil
			}
		}
		InvalidHandler(recv, content.Text)
	}

	return http.StatusOK, nil
}
