package duel

import (
	"encoding/json"
)

// TODO: replace with protobuf

const (
	Entertainment MatchType = "1"
	Rank          MatchType = "2"
	Special       MatchType = "3"
	Tournament    MatchType = "4"
	YgoDay        MatchType = "11"
	TournamentSp  MatchType = "19"

	defaultMatchText  = "比赛"
	defaultMatchColor = "neutral"
)

type MatchType string

type MatchData struct {
	Name    string `json:"name"`
	Id      uint32 `json:"id"`
	Type    uint32 `json:"type"`
	StartAt int64  `json:"startAtTimestamp"`
	Role    string `json:"role"`
}

type MatchResponse struct {
	Code uint32          `json:"code"`
	Data json.RawMessage `json:"data"`
	Msg  string          `json:"msg"`
}

// LoginResponse
type LoginResponse struct {
	Id    uint32 `json:"id"`
	Token string `json:"token"`
}

// InfoResponse
type MatchPlayer struct {
	SignCount   uint32 `json:"sign_count"`
	PlayerCount uint32 `json:"player_count"`
}

type MatchBasicInfo struct {
	Address string `json:"address_info"`
}

type MatchInfo struct {
	Name             string         `json:"Name"`
	Type             uint32         `json:"Type"`
	Condition        uint32         `json:"Condition"`
	SignUpStartAt    string         `json:"SignUpStartAt"`
	StartAt          string         `json:"StartAt"`
	Basic            MatchBasicInfo `json:"basic_info"`
	Player           MatchPlayer    `json:"player"`
	NeedIdentityCard bool           `json:"is_card"`
}

type InfoResponse struct {
	Info     MatchInfo   `json:"info"`
	Role     string      `json:"role"`
	IsSignup bool        `json:"isSignup"`
	Bottom   MatchBottom `json:"bottom"`
}

// ListResponse
type MatchTitle struct {
	Status          string `json:"text"`
	SignUpTotal     uint32 `json:"signUpTotal"`
	AlreadySignedUp uint32 `json:"alreadySignedUp"`
	CountDown       uint32 `json:"countdown"`
}

type MatchBottom struct {
	Type  uint32     `json:"type"`
	Title MatchTitle `json:"title"`
}

type MatchListInfo struct {
	Name    string      `json:"name"`
	Address string      `json:"address"`
	Id      uint32      `json:"id"`
	Type    uint32      `json:"type"`
	Rule    uint32      `json:"rule"`
	StartAt int64       `json:"startAtTimestamp"`
	Role    string      `json:"role"`
	Bottom  MatchBottom `json:"bottom"`
}

type ListResponse struct {
	Matches []MatchListInfo `json:"matchs"`
}

type ListParams struct {
	AreaId     uint32      `json:"area_id"`
	CityId     uint32      `json:"city_id"`
	IsOcg      bool        `json:"is_ocg"`
	Type       []MatchType `json:"types"`
	NumberType uint32      `json:"player_number_type"`
	StartType  uint32      `json:"match_start_type"`
	Keywords   string      `json:"keywords"`
}

type SignUpParam struct {
	MatchId     string `json:"match_id"`
	MatchName   string `json:"match_name"`
	AutoSignUp  bool   `json:"auto_signup"`
	NeedCaptcha bool   `json:"need_captcha"`
}

// CaptchaResponse
type CaptchaResponse struct {
	Result string `json:"res"`
}

var MatchTypeToString = map[MatchType]string{
	Entertainment: "娱乐赛",
	Rank:          "积分赛",
	Special:       "特殊赛",
	Tournament:    "巡回赛",
	YgoDay:        "游戏王之日",
	TournamentSp:  "巡回赛特别场",
}

var MatchTypeToColor = map[MatchType]string{
	Entertainment: "green",
	Rank:          "red",
	Special:       "yellow",
	Tournament:    "blue",
	YgoDay:        "purple",
	TournamentSp:  "orange",
}

func GetMatchTypeString(matchType MatchType) string {
	if _, ok := MatchTypeToString[matchType]; !ok {
		return defaultMatchText
	}

	return MatchTypeToString[matchType]
}

func GetMatchTypeColor(matchType MatchType) string {
	if _, ok := MatchTypeToColor[matchType]; !ok {
		return defaultMatchColor
	}

	return MatchTypeToColor[matchType]
}

func IsMatchNeedCaptcha(matchType MatchType) bool {
	if matchType == Tournament || matchType == TournamentSp {
		return true
	}

	return false
}
