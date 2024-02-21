package message

import "encoding/json"

type TemplateVariable interface{}

type LoginSuccessVariable struct {
	OpenId     string         `json:"open_id"`
	UserId     string         `json:"user_id"`
	RegionText string         `json:"region_text"`
	CityText   string         `json:"city_text"`
	RegionList []SelectOption `json:"region_list"`
	CityList   []SelectOption `json:"city_list"`
}

type SelectRegionVariable struct {
	CityList []SelectOption `json:"city_list"`
}

type SelectOption struct {
	Text  string `json:"text"`
	Value string `json:"value"`
}

type TemplateData struct {
	Id       string           `json:"template_id"`
	Variable TemplateVariable `json:"template_variable"`
}

type InteractiveContent struct {
	Type string       `json:"type"`
	Data TemplateData `json:"data"`
}

type TextContent struct {
	Text string `json:"text"`
}

func newTextMessage(text string) *Message {
	content := TextContent{
		Text: text,
	}
	res, err := json.Marshal(content)
	if err != nil {
		return nil
	}
	msg := &Message{
		Type:    "text",
		Content: string(res),
	}

	return msg
}

func newTemplateInteractive(templateId string, v TemplateVariable) *Message {
	content := InteractiveContent{
		Type: "template",
		Data: TemplateData{
			Id:       templateId,
			Variable: v,
		},
	}
	res, err := json.Marshal(content)
	if err != nil {
		return nil
	}
	msg := &Message{
		Type:    "interactive",
		Content: string(res),
	}

	return msg
}
