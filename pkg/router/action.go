package router

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"exodia.cn/pkg/bot"
	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/task"
)

type MessageActionFunc func(openId string, action bot.MessageAction) (*bot.InteractiveContent, error)

var messageActionMap = map[string]MessageActionFunc{
	bot.SelectRegionComponent: selectRegionHandler,
	bot.MatchListComponent:    signUpMatchHandler,
}

func signUpMatchHandler(openId string, action bot.MessageAction) (*bot.InteractiveContent, error) {
	value := &bot.SignUpMatchValue{}
	if err := json.Unmarshal(action.Value, value); err != nil {
		return nil, err
	}

	client := duel.NewMatchClient(duel.GetUserToken(openId))
	info, err := client.ShowMatchDetail(value.MatchId)
	if err != nil {
		return nil, err
	}
	address := info.Info.Basic.Address
	mType := duel.MatchType(fmt.Sprint(info.Info.Type))
	typeColor := duel.GetMatchTypeColor(mType)
	typeString := duel.GetMatchTypeString(mType)
	tc, _ := time.Parse(time.RFC3339, info.Info.StartAt)
	start := tc.Format(TimeFormat)
	total := info.Info.Player.PlayerCount
	signup := info.Info.Player.SignCount
	needCaptcha := duel.IsMatchNeedCaptcha(mType)
	title := ""
	buttonAction := showMatchText

	if info.Role == "player" {
		bot.SendTextMessage(fmt.Sprintf("[%s]已经报名", info.Info.Name), openId)
		return &bot.InteractiveContent{}, nil
	}

	err = client.CheckPlayer(value.MatchId)
	if err != nil {
		log.Printf("Failed to check player, err: %v", err)
		bot.SendTextMessage(fmt.Sprintf("[%s]报名失败: %v", info.Info.Name, err), openId)
		return &bot.InteractiveContent{}, nil
	}

	signupAt, _ := time.Parse(time.RFC3339, info.Info.SignUpStartAt)
	duration := time.Until(signupAt)
	if duration.Seconds() > 0 || info.Bottom.Title.Status == "待开放" {
		params := task.ScheduleParam{
			MatchId:     value.MatchId,
			MatchName:   info.Info.Name,
			AutoSignUp:  true,
			NeedCaptcha: needCaptcha,
			Token:       duel.GetUserToken(openId),
			UserName:    duel.GetUserName(openId),
			UserCard:    duel.GetUserCardId(openId),
		}
		s := task.CreateSchedule(openId, params)
		s.Start()

		title = info.Info.Name + "[已订阅]"
	} else {
		err = client.SignUpMatch(value.MatchId, needCaptcha)
		if err != nil {
			log.Printf("Failed to signup match, err: %v", err)
			bot.SendTextMessage(fmt.Sprintf("[%s]报名失败: %v", info.Info.Name, err), openId)
			return &bot.InteractiveContent{}, nil
		} else {
			title = info.Info.Name + "[报名成功]"
			buttonAction = playerText
		}
	}

	match := bot.MatchObject{
		Id:       value.MatchId,
		MarkDown: fmt.Sprintf(markDownFormat, info.Info.Name, typeColor, typeString, start, address, signup, total),
		Action:   buttonAction,
	}

	matchSet := make([]bot.MatchObject, 0)
	vars := bot.ListMatchVariable{
		MatchSet: append(matchSet, match),
		Title:    title,
	}

	resp := &bot.InteractiveContent{
		Type: "template",
		Data: bot.TemplateData{
			Id:       bot.MatchListComponent,
			Variable: vars,
		},
	}

	return resp, nil
}

func selectRegionHandler(openId string, action bot.MessageAction) (*bot.InteractiveContent, error) {
	value := &bot.SelectRegionValue{}
	if err := json.Unmarshal(action.Value, value); err != nil {
		return nil, err
	}

	regionList := make([]bot.SelectOption, 0)
	cityList := make([]bot.SelectOption, 0)
	selectRegion := SelectRegionText
	selectCity := SelectRegionText

	if value.Type == selectRegionAction {
		selectRegion = action.Option
		selectCity = SelectRegionText
	} else if value.Type == selectCityAction {
		selectRegion = value.Region
		selectCity = action.Option
	}

	for region := range duel.AreaMap {
		regionList = append(regionList, bot.SelectOption{Text: region, Value: region})
	}
	for city := range duel.AreaMap[selectRegion] {
		cityList = append(cityList, bot.SelectOption{Text: city, Value: city})
	}

	vars := bot.SelectRegionVariable{
		UserId:     duel.GetUserId(openId),
		OpenId:     openId,
		RegionText: selectRegion,
		CityText:   selectCity,
		RegionList: regionList,
		CityList:   cityList,
	}

	resp := &bot.InteractiveContent{
		Type: "template",
		Data: bot.TemplateData{
			Id:       bot.SelectRegionComponent,
			Variable: vars,
		},
	}

	if value.Type == selectCityAction {
		code, ok := duel.AreaMap[selectRegion][selectCity]
		if ok {
			area, _ := strconv.Atoi(code)
			duel.SetAreaCode(openId, uint32(area))
		}
	}

	return resp, nil
}

func MessageActionHandler(openId string, action bot.MessageAction) (*bot.InteractiveContent, error) {
	value := &bot.CommonActionValue{}
	if err := json.Unmarshal(action.Value, value); err != nil {
		return nil, err
	}

	if _, ok := messageActionMap[value.CardId]; !ok {
		return nil, errors.New("invalid message action")
	}

	return messageActionMap[value.CardId](openId, action)
}
