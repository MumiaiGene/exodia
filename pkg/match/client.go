package match

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"exodia.cn/pkg/common"
)

type MatchClient struct {
	client *http.Client
	host   string
	token  string
}

func NewMatchClient(token string) *MatchClient {
	client := &MatchClient{
		client: &http.Client{},
		host:   common.Config.Match.Host,
		token:  token,
	}

	return client
}

func (c *MatchClient) doPost(url string, body string, sig bool) (*MatchResponse, error) {
	r, err := http.NewRequest("POST", url, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	r.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	if c.token != "" {
		r.Header.Add("authorization", "Bearer "+c.token)
	}
	if sig {
		signature, err := c.genSignature()
		if err != nil {
			return nil, err
		}
		r.Header.Add("signature", signature)
	}

	resp, err := c.client.Do(r)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()

	data := &MatchResponse{}
	err = json.NewDecoder(resp.Body).Decode(data)
	if err != nil {
		return nil, err
	}

	if data.Code != 200 {
		c.token = ""
		return nil, errors.New(data.Msg)
	}

	return data, nil
}

func (c *MatchClient) doGet(url string, sig bool) (*MatchResponse, error) {
	r, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	if c.token != "" {
		r.Header.Add("authorization", "Bearer "+c.token)
	}
	if sig {
		signature, err := c.genSignature()
		if err != nil {
			return nil, err
		}
		r.Header.Add("signature", signature)
	}

	resp, err := c.client.Do(r)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()

	data := &MatchResponse{}
	err = json.NewDecoder(resp.Body).Decode(data)
	if err != nil {
		return nil, err
	}

	if data.Code != 200 {
		c.token = ""
		return nil, errors.New(data.Msg)
	}

	return data, nil
}

func (c *MatchClient) genSignature() (string, error) {
	text := common.Config.Match.SigPrefix + fmt.Sprint(time.Now().Unix())

	sig, err := common.Encrypt3Des(text, common.Config.Match.Secret, common.Config.Match.Iv)
	if err != nil {
		return "", err
	}

	return sig, nil
}

func (c *MatchClient) ListMatches(req *ListMatchesRequest) ([]Match, error) {
	params := url.Values{}
	params.Add("status", "2")
	params.Add("page", "1")
	params.Add("limit", "32")
	if req.AreaId != "" {
		params.Add("area_code", req.AreaId)
	}
	if req.ZoneId != "" {
		params.Add("zone_id", req.ZoneId)
	}
	if req.IsOcg {
		params.Add("condition", "[\"2\"]")
	}
	if len(req.Type) > 0 {
		arr, err := json.Marshal(req.Type)
		if err != nil {
			return nil, err
		}
		params.Add("type", string(arr))
	}
	body := params.Encode()

	url := c.host + "/v1/match"

	resp, err := c.doPost(url, body, false)
	if err != nil {
		return nil, err
	}

	return resp.Data.Matches, nil
}

func (c *MatchClient) ShowMatchDetail(matchId string) (MatchData, error) {
	url := c.host + "/v1/match/info/" + matchId
	resp, err := c.doGet(url, true)
	if err != nil {
		return MatchData{}, err
	}
	return resp.Data, err
}

func (c *MatchClient) SignUpMatch(matchId string) error {
	url := c.host + "/v1/match/signup/" + matchId
	_, err := c.doGet(url, true)
	return err
}

func (c *MatchClient) SendVerifyCode(phone string) error {
	params := url.Values{}
	params.Add("phone", phone)
	body := params.Encode()

	url := c.host + "/v1/msg/send"

	_, err := c.doPost(url, body, true)
	if err != nil {
		return err
	}

	return nil
}

func (c *MatchClient) Login(phone string, code string) (string, error) {
	params := url.Values{}
	params.Add("type", "tel")
	params.Add("phone", phone)
	params.Add("code", code)
	body := params.Encode()

	url := c.host + "/v1/user/login"

	resp, err := c.doPost(url, body, true)
	if err != nil {
		return "", err
	}

	return resp.Data.Token, nil
}
