package router

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"exodia.cn/pkg/bot"
	"exodia.cn/pkg/duel"
)

const (
	listMatchMenuEvent = "duel_match_list"

	TimeFormat     = "2006-01-02 15:04"
	markDownFormat = "**%s**<text_tag color='%s'>%s</text_tag>\n&#128198; %s\n&#128205; %s\n&#128101; %d/%d"

	listMatchTitle = "一起来决斗-近期比赛列表"

	signUpText    = "报名"
	scheduleText  = "预约"
	showMatchText = "查看"
	playerText    = "待参加"
)

type EventMenuHandler struct {
}

type ClickMenuFunc func(string, string)

var menuHandlerMap = map[string]ClickMenuFunc{
	listMatchMenuEvent: listMatchHandler,
}

func listMatchHandler(openId string, recvId string) {
	params := &duel.ListParams{
		AreaId: duel.GetAreaCode(openId),
		Status: 2,
		Page:   1,
		Limit:  64,
	}
	token := duel.GetUserToken(openId)
	client := duel.NewMatchClient(token)
	resp, err := client.ListMatches(params)
	if err != nil {
		bot.SendTextMessage(err.Error(), openId)
		return
	}

	matchSet := make([]bot.MatchObject, 0)
	for _, match := range resp.Matches {
		name := match.Name
		address := match.Address
		mType := duel.MatchType(fmt.Sprint(match.Type))
		typeColor := duel.GetMatchTypeColor(mType)
		typeString := duel.GetMatchTypeString(mType)
		start := time.Unix(match.StartAt, 0).Format(TimeFormat)
		total := match.Bottom.Title.SignUpTotal
		signup := match.Bottom.Title.AlreadySignedUp
		action := signUpText
		if match.Bottom.Title.CountDown > 0 {
			action = scheduleText
		} else if match.Role == "player" {
			action = playerText
		}

		if mType == duel.Entertainment &&
			!strings.Contains(name, "特别大会") &&
			!strings.Contains(name, "四季大会") {
			continue
		}

		if match.StartAt <= time.Now().Unix() {
			continue
		}

		matchSet = append(matchSet, bot.MatchObject{
			Id:       fmt.Sprint(match.Id),
			MarkDown: fmt.Sprintf(markDownFormat, name, typeColor, typeString, start, address, signup, total),
			Action:   action,
		})

		if len(matchSet) == 20 {
			break
		}
	}

	t := bot.ListMatchVariable{
		MatchSet: matchSet,
		Title:    listMatchTitle,
	}
	bot.SendInteractive(recvId, bot.MatchListComponent, t)
}

func (*EventMenuHandler) Handler(data json.RawMessage) (int, error) {
	event := &bot.EventMenu{}
	if err := json.Unmarshal(data, event); err != nil {
		return http.StatusBadRequest, err
	}

	if _, ok := menuHandlerMap[event.Key]; !ok {
		return http.StatusNotFound, errors.New("unknown event")
	}

	menuHandlerMap[event.Key](event.Operator.Id.OpenId, event.Operator.Id.OpenId)

	return http.StatusOK, nil
}
