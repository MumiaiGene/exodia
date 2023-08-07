package manager

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"exodia.cn/pkg/common"
	"exodia.cn/pkg/models"
)

const (
	MATCH_SERVER = "https://match-service.yugioh-card-cn.com"
	// 自己获取一个
	CODE         = ""
	MAX_RETRY    = 5
	ERRCODE      = 10314
)

const (
	Entertainment MatchType = "1"
	Rank          MatchType = "2"
	Special       MatchType = "3"
	Tournament    MatchType = "4"
	YgoDay        MatchType = "11"
)

const (
	UnStarted MatchStatus = 0
	Ready     MatchStatus = 1
	Wait      MatchStatus = 2
	Signed    MatchStatus = 3
)

const (
	UnStartedText  = "发现比赛: %s, 比赛时间: %s, 报名未开始"
	ReadyText      = "发现比赛: %s, 比赛时间: %s, 报名已开始, 剩余人数: %d/%d"
	WaitText       = "报名已满: %s, 比赛时间: %s, 报名人数: %d"
	SignedText     = "报名成功: %s, 注意比赛时间: %s"
	TimeFormat     = "2006-01-02 15:04"
	RetryErrorText = "重试多次, 程序异常退出"
	DoTaskError    = "任务执行失败, 错误原因: %s"
)

type MatchStatus uint32
type MatchType string

type MatchClient struct {
	client *http.Client
	host   string
	token  string
	retry  uint32
}

type MatchInterface struct {
	client *MatchClient
}

type MatchTask struct {
	AreaId string      `json:"area_id"`
	ZoneId string      `json:"zone_id"`
	IsOcg  bool        `json:"is_ocg"`
	Type   []MatchType `json:"types"`
}

type MatchResult struct {
	Id              string
	Name            string
	Type            uint32
	StartAt         int64
	SignUpTotal     uint32
	AlreadySignedUp uint32
	Status          MatchStatus
	Notice          uint32
	NextNotice      uint32
}

func (m *MatchInterface) Init() {
	m.client = &MatchClient{
		client: &http.Client{},
		host:   MATCH_SERVER,
		retry:  MAX_RETRY,
	}
}

func (m *MatchInterface) DoTask(detail interface{}) error {
	if m.client.retry == 0 {
		msg := NewTextMessage(RetryErrorText)
		Chan <- msg
		time.Sleep(5 * time.Second)
		log.Panic(msg.Content.Text)
	}

	task := detail.(*MatchTask)
	if m.client.token == "" {
		err := m.client.getToken()
		if err != nil {
			return errors.New("get token error")
		}
		log.Printf("Succeed to get token: %s", m.client.token)
	}

	matches, err := m.client.listMatches(task)
	if err != nil {
		log.Printf("Failed to find match, err: %v", err)
		return errors.New("list matches error")
	}
	log.Printf("Find %d match in this round", len(matches))
	for _, match := range matches {
		total := match.Bottom.Title.SignUpTotal
		signup := match.Bottom.Title.AlreadySignedUp
		res := &MatchResult{
			Name:            match.Name,
			Id:              fmt.Sprint(match.Id),
			Type:            match.Type,
			StartAt:         match.StartAt,
			SignUpTotal:     total,
			AlreadySignedUp: signup,
		}
		if total == 0 {
			res.Status = UnStarted
		} else if total == signup {
			res.Status = Wait
		} else if match.Bottom.Title.Status == "待参加" {
			res.Status = Signed
		} else {
			res.Status = Ready
		}

		model, _ := common.GlobalCache.LoadEntry(res.Id)
		if model == nil {
			createMatch(res)
		} else {
			cache := model.(*MatchResult)
			updateMatch(cache, res)
		}
	}
	return nil
}

func createMatch(match *MatchResult) {
	msg := &Message{
		Type: "text",
	}
	switch match.Status {
	case UnStarted:
		match.NextNotice = 60
		match.Notice = 60
		msg.Content.Text = fmt.Sprintf(UnStartedText, match.Name, time.Unix(match.StartAt, 0).Format(TimeFormat))
	case Ready:
		match.NextNotice = 60
		match.Notice = 60
		msg.Content.Text = fmt.Sprintf(ReadyText, match.Name, time.Unix(match.StartAt, 0).Format(TimeFormat), match.AlreadySignedUp, match.SignUpTotal)
	default:
		return
	}

	common.GlobalCache.SaveEntry(match.Id, match)

	Chan <- msg
}

func updateMatch(old, new *MatchResult) {
	msg := &Message{
		Type: "text",
	}

	switch new.Status {
	case UnStarted:
		if old.Notice > 0 {
			old.Notice--
			return
		} else {
			old.NextNotice = 2 * old.NextNotice
			old.Notice = old.NextNotice
		}
		msg.Content.Text = fmt.Sprintf(UnStartedText, new.Name, time.Unix(new.StartAt, 0).Format(TimeFormat))

	case Signed:
		msg.Content.Text = fmt.Sprintf(SignedText, new.Name, time.Unix(new.StartAt, 0).Format(TimeFormat))
		common.GlobalCache.DeleteEntry(new.Id)

	case Wait:
		if old.Status == Wait {
			return
		}
		old.Status = Wait
		msg.Content.Text = fmt.Sprintf(WaitText, new.Name, time.Unix(new.StartAt, 0).Format(TimeFormat), new.SignUpTotal)

	case Ready:
		if old.Notice > 0 && old.AlreadySignedUp == new.AlreadySignedUp {
			old.Notice--
			return
		} else if old.AlreadySignedUp != new.AlreadySignedUp {
			old.NextNotice = 60
			old.Notice = 60
			old.AlreadySignedUp = new.AlreadySignedUp
		} else {
			old.NextNotice = 2 * old.NextNotice
			old.Notice = old.NextNotice
		}
		msg.Content.Text = fmt.Sprintf(ReadyText, new.Name, time.Unix(new.StartAt, 0).Format(TimeFormat), new.AlreadySignedUp, new.SignUpTotal)
	}

	Chan <- msg
}

func (c *MatchClient) doPost(url string, body string) (*models.MatchResponse, error) {
	r, err := http.NewRequest("POST", url, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	r.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	if c.token != "" {
		r.Header.Add("authorization", "Bearer "+c.token)
	}

	resp, err := c.client.Do(r)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()

	data := &models.MatchResponse{}
	err = json.NewDecoder(resp.Body).Decode(data)
	if err != nil {
		return nil, err
	}

	if data.Code != 200 {
		c.token = ""
		c.retry--
		return nil, errors.New(data.Msg)
	}

	if c.retry < MAX_RETRY {
		c.retry++
	}

	return data, nil
}

func (c *MatchClient) getToken() error {
	params := url.Values{}
	params.Add("mode", "2")
	params.Add("code", "0c1Ptc000c6qrQ1EiZ200i0xYm3Ptc0v")
	params.Add("appid", "3")
	params.Add("user_id", "581")
	params.Add("encrypted", "miao")
	params.Add("iv", "miao")
	body := params.Encode()
	url := c.host + "/v1/user/platform/login/applets"

	resp, err := c.doPost(url, body)
	if err != nil {
		return err
	}

	c.token = resp.Data.Token

	return nil
}

func (c *MatchClient) listMatches(task *MatchTask) ([]models.Match, error) {
	params := url.Values{}
	params.Add("status", "2")
	params.Add("page", "1")
	params.Add("limit", "200")
	params.Add("area_code", task.AreaId)
	params.Add("zone_id", task.ZoneId)
	if task.IsOcg {
		params.Add("condition", "[\"2\"]")
	}
	if len(task.Type) > 0 {
		arr, err := json.Marshal(task.Type)
		if err != nil {
			return nil, err
		}
		params.Add("type", string(arr))
	}
	body := params.Encode()

	url := c.host + "/v1/match"

	resp, err := c.doPost(url, body)
	if err != nil {
		return nil, err
	}

	return resp.Data.Matches, nil
}
