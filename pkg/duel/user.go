package duel

import (
	"errors"
	"fmt"
	"log"

	"exodia.cn/pkg/common"
)

var userMetaCache *common.Cache

const (
	StateInitial    UserState = 0
	StateWaitPhone  UserState = 1
	StateWaitVerify UserState = 2
	StateLoggedIn   UserState = 3
	StateExpired    UserState = 4
)

type UserState int

type UserMataData struct {
	UserId   string    `json:"user_id"`
	State    UserState `json:"state"`
	Phone    string    `json:"phone"`
	Token    string    `json:"token"`
	AreaCode uint32    `json:"area"`
	Name     string
	Card     string
}

func Login(openId string, code string) error {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return errors.New("unknown openid")
	}

	user := model.(*UserMataData)
	client := NewMatchClient("")
	resp, err := client.Login(user.Phone, code)
	if err != nil {
		return err
	}

	log.Printf("succeed to get token for %d, token: %s", resp.Id, resp.Token)

	user.UserId = fmt.Sprint(resp.Id)
	user.State = StateLoggedIn
	user.Token = resp.Token

	return nil
}

func SendVerifyCode(openId string, phone string) error {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return errors.New("unknown openid")
	}

	user := model.(*UserMataData)
	client := NewMatchClient("")

	err := client.SendVerifyCode(phone)
	if err != nil {
		return err
	}

	user.State = StateWaitVerify
	user.Phone = phone
	user.Token = ""

	return nil
}

func PrepareUser(openId string) {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		user := &UserMataData{UserId: openId}
		user.State = StateWaitPhone
		userMetaCache.SaveEntry(user.UserId, user)
	} else {
		user := model.(*UserMataData)
		user.State = StateWaitPhone
	}
}

func ListUser() []*UserMataData {
	result := make([]*UserMataData, 0)
	userMetaCache.ListEntry(func(key, value any) bool {
		user := value.(*UserMataData)
		result = append(result, user)
		return true
	})

	return result
}

func UpdateUser(openId string, new *UserMataData) error {
	var user *UserMataData
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		user = &UserMataData{UserId: openId, State: StateInitial}
		userMetaCache.SaveEntry(user.UserId, user)
	} else {
		user = model.(*UserMataData)
	}

	user.Phone = new.Phone
	user.Token = new.Token
	user.AreaCode = new.AreaCode

	if user.Phone == "" {
		user.State = StateWaitPhone
	} else if user.Token == "" {
		user.State = StateWaitVerify
	} else if user.Token != "" {
		user.State = StateLoggedIn
	}

	return nil
}

func SetAreaCode(openId string, city uint32) {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return
	}

	user := model.(*UserMataData)
	user.AreaCode = city
}

func GetAreaCode(openId string) uint32 {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return 0
	}

	user := model.(*UserMataData)
	return user.AreaCode
}

func GetUserState(openId string) UserState {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return StateInitial
	}

	user := model.(*UserMataData)
	return user.State
}

func GetUserToken(openId string) string {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return ""
	}

	user := model.(*UserMataData)
	return user.Token
}

func GetUserName(openId string) string {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return ""
	}

	user := model.(*UserMataData)
	return user.Name
}

func GetUserCardId(openId string) string {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return ""
	}

	user := model.(*UserMataData)
	return user.Card
}

func GetUserId(openId string) string {
	model, _ := userMetaCache.LoadEntry(openId)
	if model == nil {
		return ""
	}

	user := model.(*UserMataData)
	return user.UserId
}

func InitUser(users []common.UserConfig) {
	for _, user := range users {
		meta := &UserMataData{
			UserId:   user.Id,
			Phone:    user.Phone,
			Token:    user.Token,
			AreaCode: user.Area,
			Name:     user.Name,
			Card:     user.Card,
			State:    StateLoggedIn,
		}

		log.Printf("Added User: %s, Token: %s", user.Id, user.Token)
		userMetaCache.SaveEntry(meta.UserId, meta)
	}
}

func init() {
	userMetaCache = common.NewCache()
}
