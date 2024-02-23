package duel

import "encoding/json"

// TODO: replace with protobuf

const (
	Entertainment MatchType = "1"
	Rank          MatchType = "2"
	Special       MatchType = "3"
	Tournament    MatchType = "4"
	YgoDay        MatchType = "11"
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

type MatchInfo struct {
	Condition     uint32      `json:"Condition"`
	SignUpStartAt string      `json:"SignUpStartAt"`
	StartAt       string      `json:"StartAt"`
	Player        MatchPlayer `json:"player"`
}

type InfoResponse struct {
	Name     string      `json:"Name"`
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
}

type MatchBottom struct {
	Type  uint32     `json:"type"`
	Title MatchTitle `json:"title"`
}

type MatchListInfo struct {
	Name    string      `json:"name"`
	Id      uint32      `json:"id"`
	Type    uint32      `json:"type"`
	StartAt int64       `json:"startAtTimestamp"`
	Role    string      `json:"role"`
	Bottom  MatchBottom `json:"bottom"`
}

type ListResponse struct {
	Matches []MatchListInfo `json:"matchs"`
}

type ListParams struct {
	AreaId     string      `json:"area_id"`
	CityId     string      `json:"city_id"`
	IsOcg      bool        `json:"is_ocg"`
	Type       []MatchType `json:"types"`
	NumberType uint32      `json:"player_number_type"`
	StartType  uint32      `json:"match_start_type"`
	Keywords   string      `json:"keywords"`
}

// CaptchaResponse
type CaptchaResponse struct {
	Result string `json:"res"`
}
