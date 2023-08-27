package message

import (
	"context"
	"encoding/json"
	"errors"
	"log"

	"exodia.cn/pkg/common"
	"github.com/google/uuid"

	lark "github.com/larksuite/oapi-sdk-go/v3"
	larkim "github.com/larksuite/oapi-sdk-go/v3/service/im/v1"
)

var client *MessageClient

type Content struct {
	Text string `json:"text"`
}

type Message struct {
	Type    string  `json:"msg_type"`
	Content Content `json:"content"`
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

func NewTextMessage(text string) *Message {
	msg := &Message{
		Type: "text",
		Content: Content{
			Text: text,
		},
	}

	return msg
}

func SendTextMessage(text string, receiveId string) error {
	msg := NewTextMessage(text)
	return client.sendMessage(msg, receiveId)
}

func (c *MessageClient) sendMessage(msg *Message, receiveId string) error {
	content, err := json.Marshal(msg.Content)
	if err != nil {
		log.Println(err)
		return err
	}

	// 创建请求对象
	req := larkim.NewCreateMessageReqBuilder().
		ReceiveIdType("open_id").
		Body(larkim.NewCreateMessageReqBodyBuilder().
			ReceiveId(receiveId).
			MsgType("text").
			Content(string(content)).
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
