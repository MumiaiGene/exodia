package task

import (
	"log"
)

type ScheduleParam struct {
	MatchId     string
	MatchName   string
	AutoSignUp  bool
	NeedCaptcha bool
	Token       string
	UserName    string
	UserCard    string
}

type Schedule struct {
	UserId string
	Params ScheduleParam
	task   *Task
}

func CreateSchedule(userId string, params ScheduleParam) *Schedule {
	s := new(Schedule)
	s.UserId = userId
	s.Params = params

	return s
}

func (s *Schedule) Start() {
	log.Printf("Start schedule for %s, ", s.Params.MatchName)

	task := &Task{
		Id:          s.Params.MatchId,
		UserId:      s.UserId,
		Name:        s.Params.MatchName,
		Interval:    1,
		AutoSignUp:  s.Params.AutoSignUp,
		NeedCaptcha: s.Params.NeedCaptcha,
		Token:       s.Params.Token,
		UserName:    s.Params.UserName,
		UserCardId:  s.Params.UserCard,
	}
	s.task = task

	GlobalManager.SendTask(task)
}

func (s *Schedule) Stop() {

}
