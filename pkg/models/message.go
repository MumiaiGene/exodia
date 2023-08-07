package models

type MessageResponse struct {
	Code uint   `json:"code"`
	Msg  string `json:"msg"`
	// Type      string `json:"data"`
}
