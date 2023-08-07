package manager

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"exodia.cn/pkg/models"
)

const (
	DEFAULT_INTERVAL = 10
)

var Chan chan *Message
var TaskManager *Manager

type Content struct {
	Text string `json:"text"`
}

type Message struct {
	Type    string  `json:"msg_type"`
	Content Content `json:"content"`
}

type Manager struct {
	client            *http.Client
	timer             *time.Ticker
	taskList          []models.Task
	msgChannel        chan *Message
	cancelConsumeFunc context.CancelFunc
	taskHandlerMap    map[string]TaskHandler
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

func CreateManager() *Manager {
	m := new(Manager)
	interval := time.Duration(DEFAULT_INTERVAL) * time.Second
	m.timer = time.NewTicker(interval)
	m.client = &http.Client{}
	m.msgChannel = Chan
	m.taskHandlerMap = TaskHandlerMap
	m.StartConsume()

	//task := models.Task{
	//	Type: "match",
	//	Name: "游戏王之日",
	//	Detail: &MatchTask{
	//		AreaId: "310112",
	//		ZoneId: "9",
	//		IsOcg:  false,
	//		Type:   []MatchType{YgoDay},
	//	},
	//}
	//m.AddTask(task)

	go m.Start()
	return m
}

func (m *Manager) Start() {
	defer m.timer.Stop()

	log.Println("Start manager")
	for range m.timer.C {
		for _, task := range m.taskList {
			err := m.taskHandlerMap[task.Type].DoTask(task.Detail)
			if err != nil {
				msg := NewTextMessage(fmt.Sprintf(DoTaskError, err.Error()))
				m.sendMessage(msg)
				log.Printf("Failed to do task, name: %s, err: %v", task.Name, err)
			}
		}
	}
}

func (m *Manager) Stop() {
	m.timer.Stop()
}

func (m *Manager) AddTask(task models.Task) {
	m.taskHandlerMap[task.Type].Init()
	m.taskList = append(m.taskList, task)
	log.Printf("Succeed to add task: %s", task.Name)
}

func (m *Manager) ListTask() []models.Task {
	return m.taskList
}

func (m *Manager) StartConsume() {
	ctx, cancel := context.WithCancel(context.TODO())
	m.cancelConsumeFunc = cancel

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				m.consumeHandler(<-m.msgChannel)
			}
		}
	}()
}

func (m *Manager) sendMessage(msg *Message) error {
	// 手动加一下
	url := ""
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	r, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}

	r.Header.Add("Content-Type", "application/json; charset=utf-8")

	resp, err := m.client.Do(r)
	if err != nil {
		return err
	}

	defer resp.Body.Close()

	data := &models.MessageResponse{}
	err = json.NewDecoder(resp.Body).Decode(data)
	if err != nil {
		return err
	}

	if data.Code != 0 {
		return errors.New(data.Msg)
	}

	return nil
}

func (m *Manager) consumeHandler(msg *Message) {
	log.Printf("new message: %s", msg.Content.Text)
	err := m.sendMessage(msg)
	if err != nil {
		log.Printf("Failed to send message, err: %v", err)
	}
}

func init() {
	Chan = make(chan *Message, 100)
}
