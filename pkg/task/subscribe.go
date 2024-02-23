package task

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/message"
)

type SubscribeResult struct {
	Id              string
	Name            string
	Type            uint32
	StartAt         int64
	SignUpTotal     uint32
	AlreadySignedUp uint32
	Status          MatchStatus
}

type SubscribeParam struct {
	AreaId     string           `json:"area_id"`
	ZoneId     string           `json:"zone_id"`
	IsOcg      bool             `json:"is_ocg"`
	AutoSignUp bool             `json:"auto_signup"`
	Type       []duel.MatchType `json:"types"`
	Interval   int              `json:"interval"`
	Token      string           `json:"token"`
}

type Subscribe struct {
	UserId      string
	Params      SubscribeParam
	taskChannel chan *Task
	taskList    []*Task
	cancelFunc  context.CancelFunc
	client      *duel.MatchClient
	timer       *time.Ticker
}

func CreateSubscribe(userId string, params SubscribeParam) *Subscribe {
	s := new(Subscribe)
	s.UserId = userId
	s.Params = params
	s.taskChannel = make(chan *Task, 100)
	s.client = duel.NewMatchClient(s.Params.Token)

	go s.Start()
	return s
}

func (s *Subscribe) Start() {
	log.Printf("Start subscribe for %s", s.UserId)
	s.startConsume()

	s.timer = time.NewTicker(time.Duration(s.Params.Interval) * time.Second)
	for range s.timer.C {
		result, err := s.searchTask()
		if err != nil {
			message.SendTextMessage(err.Error(), s.UserId)
			continue
		}
		log.Printf("Find %d match in this round", len(result))

		for _, match := range result {
			var text string
			switch match.Status {
			case UnStarted:
				text = fmt.Sprintf(UnStartedText, match.Name, time.Unix(match.StartAt, 0).Format(TimeFormat))
			case Wait:
				text = fmt.Sprintf(WaitText, match.Name, time.Unix(match.StartAt, 0).Format(TimeFormat), match.SignUpTotal)
			case Ready:
				text = fmt.Sprintf(ReadyText, match.Name, time.Unix(match.StartAt, 0).Format(TimeFormat), match.AlreadySignedUp, match.SignUpTotal)
			default:
				continue
			}

			message.SendTextMessage(text, s.UserId)

			task := &Task{
				Id:         match.Id,
				Name:       match.Name,
				Interval:   1,
				AutoSignUp: s.Params.AutoSignUp,
			}
			s.taskChannel <- task
		}
	}
}

func (s *Subscribe) Stop() {
	for _, task := range s.taskList {
		task.Timer.Stop()
	}
	s.cancelFunc()
	s.timer.Stop()
	log.Printf("Stop subscribe for %s", s.UserId)
}

func (s *Subscribe) AddTask(task *Task) {
	s.taskList = append(s.taskList, task)
	task.Timer = time.NewTicker(time.Duration(task.Interval) * time.Second)
	log.Printf("Succeed to add task: %s", task.Name)

	go task.DoTask()
}

// func (m *Manager) ListTask() []*Task {
// 	return m.taskList
// }

func (s *Subscribe) searchTask() ([]*SubscribeResult, error) {
	req := &duel.ListParams{
		AreaId: s.Params.AreaId,
		CityId: s.Params.ZoneId,
		IsOcg:  s.Params.IsOcg,
		Type:   s.Params.Type,
	}

	resp, err := s.client.ListMatches(req)
	if err != nil {
		log.Printf("Failed to find match, err: %v", err)
		return nil, errors.New("list matches error")
	}

	result := make([]*SubscribeResult, 0)

	for _, match := range resp.Matches {
		id := fmt.Sprint(match.Id)
		if s.hasSubscribed(id) {
			continue
		}
		total := match.Bottom.Title.SignUpTotal
		signup := match.Bottom.Title.AlreadySignedUp
		data := &SubscribeResult{
			Name:            match.Name,
			Id:              fmt.Sprint(match.Id),
			Type:            match.Type,
			StartAt:         match.StartAt,
			SignUpTotal:     total,
			AlreadySignedUp: signup,
		}
		if total == 0 {
			data.Status = UnStarted
		} else if match.Role == "player" {
			data.Status = Signed
		} else if total == signup {
			data.Status = Wait
		} else {
			data.Status = Ready
		}

		result = append(result, data)
	}

	return result, nil
}

func (s *Subscribe) hasSubscribed(matchId string) bool {
	for _, task := range s.taskList {
		if task.Id == matchId {
			return true
		}
	}
	return false
}

func (s *Subscribe) startConsume() {
	ctx, cancel := context.WithCancel(context.TODO())
	s.cancelFunc = cancel

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				s.consumeTask(<-s.taskChannel)
			}
		}
	}()
}

func (s *Subscribe) consumeTask(task *Task) {
	log.Printf("add task: %s", task.Name)
	s.AddTask(task)
}
