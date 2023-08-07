package models

type Task struct {
	Type   string `json:"type"`
	Name   string `json:"name"`
	Detail interface{}
}
