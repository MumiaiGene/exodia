package models

type Match struct {
	Name    string      `json:"name"`
	Id      uint32      `json:"id"`
	Type    uint32      `json:"type"`
	StartAt int64       `json:"startAtTimestamp"`
	Bottom  MatchBottom `json:"bottom"`
}

type MatchTitle struct {
	Status          string `json:"text"`
	SignUpTotal     uint32 `json:"signUpTotal"`
	AlreadySignedUp uint32 `json:"alreadySignedUp"`
}

type MatchBottom struct {
	Title MatchTitle `json:"title"`
}

type MatchInfo struct {
	Condition     uint32 `json:"Condition"`
	SignUpStartAt string `json:"SignUpStartAt"`
}

type MatchData struct {
	Id        uint32    `json:"id"`
	Token     string    `json:"token"`
	Matches   []Match   `json:"matchs"`
	IsSignup  bool      `json:"isSignup"`
	MatchInfo MatchInfo `json:"info"`
}

type MatchResponse struct {
	Code uint32    `json:"code"`
	Data MatchData `json:"data"`
	Msg  string    `json:"msg"`
}
