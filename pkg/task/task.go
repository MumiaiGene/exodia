package task

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"exodia.cn/pkg/bot"
	"exodia.cn/pkg/duel"
)

var GlobalManager *TaskManager

const (
	UnStartedText  = "发现比赛: %s, 比赛时间: %s, 报名未开始"
	ReadyText      = "发现比赛: %s, 比赛时间: %s, 报名已开始, 剩余人数: %d/%d"
	WaitText       = "报名已满: %s, 比赛时间: %s, 报名人数: %d"
	SignedText     = "报名成功: %s"
	TimeFormat     = "2006-01-02 15:04"
	RetryErrorText = "重试多次, 任务休眠 1 小时"
	DoTaskError    = "任务执行失败, 错误原因: %s"
)

const (
	MAX_RETRY          = 20
	SIGNUP_TIME_FORMAT = "2006-12-12T16:00:00+08:00"
	START_TEXT_FORMAT  = "比赛【%s】已经开始, 任务结束"
)

const (
	UnStarted MatchStatus = 0
	Ready     MatchStatus = 1
	Wait      MatchStatus = 2
	Signed    MatchStatus = 3
)

type MatchStatus uint32

type Task struct {
	Id          string
	UserId      string
	UserName    string
	UserCardId  string
	Name        string
	Interval    int
	SignUpAt    int64 `json:"signup_at"`
	StartAt     int64 `json:"start_at"`
	AutoSignUp  bool  `json:"auto_signup"`
	NeedCaptcha bool
	Token       string
	Timer       *time.Ticker
}

type TaskManager struct {
	taskChannel chan *Task
	taskList    []*Task
	cancelFunc  context.CancelFunc
}

func CreateManager() *TaskManager {
	m := new(TaskManager)
	m.taskChannel = make(chan *Task, 100)
	return m
}

func (m *TaskManager) StartConsume() {
	ctx, cancel := context.WithCancel(context.TODO())
	m.cancelFunc = cancel

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case t := <-m.taskChannel:
				m.AddTask(t)
			}
		}
	}()
}

func (m *TaskManager) StopConsume() {
	for _, task := range m.taskList {
		task.Timer.Stop()
	}
	if m.cancelFunc != nil {
		m.cancelFunc()
	}
}

func (m *TaskManager) AddTask(task *Task) {
	for _, t := range m.taskList {
		if task.UserId == t.UserId && task.Id == t.Id {
			log.Printf("duplicate task %s for %s", task.Name, task.UserId)
			return
		}
	}
	m.taskList = append(m.taskList, task)
	task.Timer = time.NewTicker(time.Duration(task.Interval) * time.Second)
	log.Printf("Succeed to add task: %s", task.Name)

	go task.DoTask()
}

func (m *TaskManager) SendTask(task *Task) {
	m.taskChannel <- task
}

func (task *Task) DoTask() {
	retry := MAX_RETRY
	var hour int64
	var minute int64
	var second int64

	for range task.Timer.C {
		Succeed, err := task.production()
		if err != nil {
			bot.SendTextMessage(fmt.Sprintf(DoTaskError, err.Error()), task.UserId)
			log.Printf("Failed to do task, name: %s, err: %v", task.Name, err)

			retry--
			if retry == 0 {
				task.SignUpAt = 0
				bot.SendTextMessage(RetryErrorText, task.UserId)
				time.Sleep(1 * time.Hour)
				continue
			}

		} else if retry < MAX_RETRY {
			retry++
		}

		if Succeed {
			bot.SendTextMessage(fmt.Sprintf(SignedText, task.Name), task.UserId)
			log.Printf(SignedText, task.Name)
			break
		}

		if task.StartAt <= time.Now().Unix() {
			bot.SendTextMessage(fmt.Sprintf(START_TEXT_FORMAT, task.Name), task.UserId)
			break
		}

		duration := time.Until(time.Unix(task.SignUpAt, 0))
		if duration.Seconds() > 0 {
			log.Printf("报名时间还剩: %s", duration.String())

			flag := false
			if duration.Hours() >= 1 {
				if hour != int64(duration.Hours()) {
					flag = true
					hour = int64(duration.Hours())
				}

			} else if duration.Minutes() >= 1 {
				if minute != int64(duration.Minutes())/10 {
					flag = true
					minute = int64(duration.Minutes()) / 10
				}

			} else {
				if second != int64(duration.Seconds())/10 {
					flag = true
					second = int64(duration.Seconds()) / 10
				}
			}

			if flag {
				bot.SendTextMessage(fmt.Sprintf("报名时间还剩: %s", duration.Round(10*time.Second).String()), task.UserId)
			}
		}

	}
}

func (task *Task) production() (bool, error) {
	client := duel.NewMatchClient(task.Token)

	if task.SignUpAt == 0 {
		data, err := client.ShowMatchDetail(task.Id)
		if err != nil {
			log.Printf("Failed to show match detail, err: %v", err)
			return false, errors.New("show match error")
		}
		if data.Role == "player" {
			return true, nil
		}

		if data.Info.NeedIdentityCard {
			log.Printf("Identity card: %s %s", task.UserName, task.UserCardId)
			err = client.SendIdentityCard(task.Id, task.UserName, task.UserCardId)
			if err != nil {
				log.Printf("Failed to send identity card, err: %v", err)
			}
		}

		signup, _ := time.Parse(time.RFC3339, data.Info.SignUpStartAt)
		start, _ := time.Parse(time.RFC3339, data.Info.StartAt)
		task.SignUpAt = signup.Unix()
		task.StartAt = start.Unix()

		log.Printf("报名人数: %d/%d", data.Info.Player.SignCount, data.Info.Player.PlayerCount)
		if data.Info.Player.SignCount == data.Info.Player.PlayerCount {
			task.SignUpAt = 0
			return false, nil
		}

		if data.Bottom.Title.Status == "待开放" {
			log.Printf("报名待开放: %s", task.Name)
			if time.Now().Unix() > task.SignUpAt {
				ts := time.Now()
				if ts.Hour() > 13 {
					ts = ts.Add(24 * time.Hour)
				}
				task.SignUpAt = time.Date(ts.Year(), ts.Month(), ts.Day(), 12, 59, 55, 0, ts.Location()).Unix()
			}
		}

	}

	if time.Now().Unix() >= task.SignUpAt {
		err := client.CheckPlayer(task.Id)
		if err != nil {
			log.Printf("Failed to check player, err: %v", err)
			return false, err
		}
		if task.AutoSignUp {
			time.Sleep(1 * time.Second)
			err := client.SignUpMatch(task.Id, task.NeedCaptcha)
			if err != nil {
				log.Printf("Failed to signup match, err: %v", err)
				return false, err
			}

			return true, nil
		}
	}

	return false, nil
}

func init() {
	GlobalManager = CreateManager()
}
