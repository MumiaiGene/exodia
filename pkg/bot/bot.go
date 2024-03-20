package bot

import "encoding/json"

// common block
type UserId struct {
	UnionId string `json:"union_id"`
	UserId  string `json:"user_id"`
	OpenId  string `json:"open_id"`
}

// event block
type EventHeader struct {
	EventId    string `json:"event_id"`
	Token      string `json:"token"`
	CreateTime string `json:"create_time"`
	EventType  string `json:"event_type"`
	TenantKey  string `json:"tenant_key"`
	AppId      string `json:"app_id"`
}

type EventRequest struct {
	Schema string          `json:"schema"`
	Header EventHeader     `json:"header"`
	Event  json.RawMessage `json:"event"`
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

type EventOperator struct {
	Id UserId `json:"operator_id"`
}

type EventMenu struct {
	Key      string        `json:"event_key"`
	Operator EventOperator `json:"operator"`
}

type SignUpMatchValue struct {
	MatchId string `json:"signup_match"`
}

type SelectRegionValue struct {
	Type   string `json:"custom_msg_type"`
	Region string `json:"select_region"`
}

type CommonActionValue struct {
	CardId string `json:"card_id"`
}

type MessageAction struct {
	Tag    string
	Option string

	Value json.RawMessage `json:"value"`
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

// component block
type SelectOption struct {
	Text  string `json:"text"`
	Value string `json:"value"`
}

const (
	SelectRegionComponent = "ctp_AAgl7ar1SWwK"
	MatchListComponent    = "ctp_AAyfbN4qDgf7"
)
