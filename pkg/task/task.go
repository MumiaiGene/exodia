package task

import (
	"errors"
	"fmt"
	"log"
	"time"

	"exodia.cn/pkg/match"
)

const (
	UnStartedText  = "发现比赛: %s, 比赛时间: %s, 报名未开始"
	ReadyText      = "发现比赛: %s, 比赛时间: %s, 报名已开始, 剩余人数: %d/%d"
	WaitText       = "报名已满: %s, 比赛时间: %s, 报名人数: %d"
	SignedText     = "报名成功: %s"
	TimeFormat     = "2006-01-02 15:04"
	RetryErrorText = "重试多次, 任务异常中断"
	DoTaskError    = "任务执行失败, 错误原因: %s"
)

const (
	MAX_RETRY             = 5
	SIGNUP_TIME_FORMAT    = "2006-12-12T16:00:00+08:00"
	COUNTDOWN_TEXT_FORMAT = "比赛【%s】报名时间还剩: %d%s"
	START_TEXT_FORMAT     = "比赛【%s】已经开始, 任务结束"
)

const (
	UnStarted MatchStatus = 0
	Ready     MatchStatus = 1
	Wait      MatchStatus = 2
	Signed    MatchStatus = 3
)

type MatchStatus uint32

type Task struct {
	Id         string
	Name       string
	Interval   int
	SignUpAt   int64 `json:"signup_at"`
	StartAt    int64 `json:"start_at"`
	AutoSignUp bool  `json:"auto_signup"`
	Timer      *time.Ticker
}

func (task *Task) DoTask(client *match.MatchClient) {
	retry := MAX_RETRY
	var hour int64
	var minute int64
	var second int64
	for range task.Timer.C {
		Succeed, err := task.production(client)
		if err != nil {
			retry--
			// SendTextMessage(fmt.Sprintf(DoTaskError, err.Error()))
			log.Printf("Failed to do task, name: %s, err: %v", task.Name, err)
		} else if retry < MAX_RETRY {
			retry++
		}

		if Succeed {
			// SendTextMessage(fmt.Sprintf(SignedText, task.Name))
			log.Printf(SignedText, task.Name)
			break
		}

		if task.StartAt <= time.Now().Unix() {
			// SendTextMessage(fmt.Sprintf(START_TEXT_FORMAT, task.Name))
			break
		}

		duration := task.SignUpAt - time.Now().Unix()
		// log.Printf("报名时间还剩: %d秒", duration)
		var text string
		if duration >= 3600 {
			if hour != duration/3600 {
				hour = duration / 3600
				text = fmt.Sprintf(COUNTDOWN_TEXT_FORMAT, task.Name, duration/3600, "小时")
				// SendTextMessage(text)
			}
		} else if duration >= 60 {
			if minute != duration/600 {
				minute = duration / 600
				text = fmt.Sprintf(COUNTDOWN_TEXT_FORMAT, task.Name, duration/60, "分钟")
				// SendTextMessage(text)
			}
		} else if duration >= 10 {
			if second != duration/10 {
				second = duration / 10
				text = fmt.Sprintf(COUNTDOWN_TEXT_FORMAT, task.Name, duration, "秒")
				// SendTextMessage(text)
			}
		}

		log.Println(text)

		if retry == 0 {
			// SendTextMessage(RetryErrorText)
			break
		}
	}
}

func (task *Task) production(client *match.MatchClient) (bool, error) {
	var flag bool

	if task.SignUpAt == 0 {
		data, err := client.ShowMatchDetail(task.Id)
		if err != nil {
			log.Printf("Failed to show match detail, err: %v", err)
			return false, errors.New("show match error")
		}
		if data.Role == "player" {
			return true, nil
		}

		signup, _ := time.Parse(time.RFC3339, data.Info.SignUpStartAt)
		start, _ := time.Parse(time.RFC3339, data.Info.StartAt)
		task.SignUpAt = signup.Unix()
		task.StartAt = start.Unix()
		flag = true
		log.Printf("报名时间时间: %s", data.Info.SignUpStartAt)
	}

	if task.SignUpAt-time.Now().Unix() <= 0 {
		if !flag {
			data, err := client.ShowMatchDetail(task.Id)
			if err != nil {
				log.Printf("Failed to show match detail, err: %v", err)
				return false, errors.New("show match error")
			}
			if data.Info.Player.SignCount == data.Info.Player.PlayerCount {
				log.Printf("报名已满: %d/%d", data.Info.Player.SignCount, data.Info.Player.PlayerCount)
				return false, nil
			}
		}
		if task.AutoSignUp {
			err := client.SignUpMatch(task.Id)
			if err != nil {
				return false, err
			}
		}
		return true, nil
	}

	return false, nil
}
