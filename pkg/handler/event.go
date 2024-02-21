package handler

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

const (
	EVENT_RECV_MESSAGE = "im.message.receive_v1"
)

// TODO: replace with protobuf

type EventHeader struct {
	EventId    string `json:"event_id"`
	Token      string `json:"token"`
	CreateTime string `json:"create_time"`
	EventType  string `json:"event_type"`
	TenantKey  string `json:"tenant_key"`
	AppId      string `json:"app_id"`
}

type EventRequest struct {
	Schema string      `json:"schema"`
	Header EventHeader `json:"header"`
}

type UserId struct {
	UnionId string `json:"union_id"`
	UserId  string `json:"user_id"`
	OpenId  string `json:"open_id"`
}

type EventHandler interface {
	Handler(*gin.Context) (int, error)
}

var EventHandlerMap = map[string]EventHandler{
	EVENT_RECV_MESSAGE: &MessageHandler{},
}

func EventRouteHandler(ctx *gin.Context) {
	var req EventRequest
	var resp gin.H = gin.H{"msg": "ok"}
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

	log.Printf("event_id: %s, time: %s", req.Header.EventId, req.Header.CreateTime)
	if _, ok := EventHandlerMap[req.Header.EventType]; !ok {
		ctx.JSON(
			http.StatusNotFound,
			gin.H{
				"msg": "invalid event type",
			},
		)
		return
	}
	code, err := EventHandlerMap[req.Header.EventType].Handler(ctx)
	if err != nil {
		resp = gin.H{
			"msg": err.Error(),
		}
	}

	ctx.JSON(
		code, resp,
	)
}
