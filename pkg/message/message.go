package message

import (
	"context"
	"errors"
	"log"
	"strings"

	"exodia.cn/pkg/common"
	"github.com/google/uuid"

	lark "github.com/larksuite/oapi-sdk-go/v3"
	larkim "github.com/larksuite/oapi-sdk-go/v3/service/im/v1"
)

const (
	LoginSuccess = "ctp_AAgl7ar1SWwK"
)

var client *MessageClient

type Message struct {
	Type    string `json:"msg_type"`
	Content string `json:"content"`
}

type MessageClient struct {
	client *lark.Client
}

func NewMessageClient() *MessageClient {
	// 创建 Client
	// 如需SDK自动管理租户Token的获取与刷新，可调用lark.WithEnableTokenCache(true)进行设置
	client := &MessageClient{
		client: lark.NewClient(common.Config.Bot.AppId, common.Config.Bot.AppSecret, lark.WithEnableTokenCache(true)),
	}
	return client
}

func SendTextMessage(text string, receiveId string) error {
	msg := newTextMessage(text)
	if msg == nil {
		return errors.New("failed to build text message")
	}
	return client.sendMessage(msg, receiveId)
}

func SendInteractive(receiveId string, templateId string, v TemplateVariable) error {
	msg := newTemplateInteractive(templateId, v)
	if msg == nil {
		return errors.New("failed to build interactive message")
	}
	return client.sendMessage(msg, receiveId)
}

func (c *MessageClient) sendMessage(msg *Message, receiveId string) error {
	receiveIdType := "open_id"
	if strings.HasPrefix(receiveId, "oc") {
		receiveIdType = "chat_id"
	}

	// 创建请求对象
	req := larkim.NewCreateMessageReqBuilder().
		ReceiveIdType(receiveIdType).
		Body(larkim.NewCreateMessageReqBodyBuilder().
			ReceiveId(receiveId).
			MsgType(msg.Type).
			Content(string(msg.Content)).
			Uuid(uuid.New().String()).
			Build()).
		Build()

	// 发起请求
	// 如开启了SDK的Token管理功能，就无需在请求时调用larkcore.WithTenantAccessToken("-xxx")来手动设置租户Token了
	resp, err := c.client.Im.Message.Create(context.Background(), req)

	// 处理错误
	if err != nil {
		log.Println(err)
		return err
	}

	// 服务端错误处理
	if !resp.Success() {
		log.Println(resp.Code, resp.Msg, resp.RequestId())
		return errors.New(resp.Msg)
	}

	// 业务处理
	// fmt.Println(larkcore.Prettify(resp))

	return nil
}

func init() {
	client = NewMessageClient()
}
