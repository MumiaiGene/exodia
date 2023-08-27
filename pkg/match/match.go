package match

// TODO: replace with protobuf

const (
	Entertainment MatchType = "1"
	Rank          MatchType = "2"
	Special       MatchType = "3"
	Tournament    MatchType = "4"
	YgoDay        MatchType = "11"
)

type MatchType string

type Match struct {
	Name    string      `json:"name"`
	Id      uint32      `json:"id"`
	Type    uint32      `json:"type"`
	StartAt int64       `json:"startAtTimestamp"`
	Role    string      `json:"role"`
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

type MatchData struct {
	Id       uint32    `json:"id"`
	Token    string    `json:"token"`
	Matches  []Match   `json:"matchs"`
	IsSignup bool      `json:"isSignup"`
	Info     MatchInfo `json:"info"`
	Role     string    `json:"role"`
}

type MatchResponse struct {
	Code uint32    `json:"code"`
	Data MatchData `json:"data"`
	Msg  string    `json:"msg"`
}

type ListMatchesRequest struct {
	AreaId string      `json:"area_id"`
	ZoneId string      `json:"zone_id"`
	IsOcg  bool        `json:"is_ocg"`
	Type   []MatchType `json:"types"`
}
