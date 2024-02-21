package duel

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
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

func (c *MatchClient) doPost(url string, body string, sig bool) (json.RawMessage, error) {
	var result MatchResponse
	r, err := http.NewRequest("POST", url, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	r.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	if c.token != "" {
		r.Header.Add("authorization", "Bearer "+c.token)
	}
	if sig {
		signature, err := genSignature()
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

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	if result.Code != 200 {
		c.token = ""
		return nil, errors.New(result.Msg)
	}

	return result.Data, nil
}

func (c *MatchClient) doGet(url string, sig bool) (json.RawMessage, error) {
	var result MatchResponse
	r, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	if c.token != "" {
		r.Header.Add("authorization", "Bearer "+c.token)
	}
	if sig {
		signature, err := genSignature()
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

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	if result.Code != 200 {
		c.token = ""
		return nil, errors.New(result.Msg)
	}

	return result.Data, nil
}

func genSignature() (string, error) {
	text := common.Config.Match.SigPrefix + fmt.Sprint(time.Now().Unix())

	sig, err := common.Encrypt3Des(text, common.Config.Match.Secret, common.Config.Match.Iv)
	if err != nil {
		return "", err
	}

	return sig, nil
}

func findTrueCode(text string) (string, error) {
	captcha, err := common.Decrypt3Des(text, common.Config.Captcha.Secret, common.Config.Captcha.Iv)
	if err != nil {
		return "", err
	}

	res := strings.Split(captcha, ",")
	if len(res) != 3 {
		return "", fmt.Errorf("invalid captcha: %s", captcha)
	}

	code, err := common.Encrypt3Des(res[1], common.Config.Captcha.Secret, common.Config.Captcha.Iv)
	if err != nil {
		return "", err
	}

	return code, nil
}

func (c *MatchClient) ListMatches(p *ListParams) (*ListResponse, error) {
	params := url.Values{}
	params.Add("status", "2")
	params.Add("page", "1")
	params.Add("limit", "32")
	if p.AreaId != "" {
		params.Add("area_code", p.AreaId)
	}
	if p.CityId != "" {
		params.Add("city_id", p.CityId)
	}
	if p.IsOcg {
		params.Add("condition", "[\"2\"]")
	}
	if len(p.Type) > 0 {
		arr, err := json.Marshal(p.Type)
		if err != nil {
			return nil, err
		}
		params.Add("type", string(arr))
	}
	body := params.Encode()

	url := c.host + "/v1/match"

	data, err := c.doPost(url, body, false)
	if err != nil {
		return nil, err
	}

	resp := &ListResponse{}

	if err = json.Unmarshal(data, resp); err != nil {
		return nil, err
	}

	return resp, nil
}

func (c *MatchClient) ShowMatchDetail(matchId string) (*InfoResponse, error) {
	url := c.host + "/v1/match/info/" + matchId
	data, err := c.doGet(url, true)
	if err != nil {
		return nil, err
	}

	resp := &InfoResponse{}

	if err = json.Unmarshal(data, resp); err != nil {
		return nil, err
	}
	return resp, err
}

func (c *MatchClient) GetCaptcha() (string, error) {
	url := c.host + "/v1/captcha"
	data, err := c.doGet(url, true)
	if err != nil {
		return "", err
	}

	resp := &CaptchaResponse{}

	if err = json.Unmarshal(data, resp); err != nil {
		return "", err
	}
	return resp.Result, err
}

func (c *MatchClient) SignUpMatch(matchId string, needCaptcha bool) error {
	baseUrl, _ := url.Parse(c.host + "/v1/match/signup/" + matchId)
	if needCaptcha {
		captcha, err := c.GetCaptcha()
		if err != nil {
			return err
		}

		code, err := findTrueCode(captcha)
		if err != nil {
			return err
		}
		params := url.Values{}
		params.Add("code", code)
		baseUrl.RawQuery = params.Encode()
	}
	_, err := c.doGet(baseUrl.String(), true)
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

func (c *MatchClient) Login(phone string, code string) (*LoginResponse, error) {
	params := url.Values{}
	params.Add("type", "tel")
	params.Add("phone", phone)
	params.Add("code", code)
	body := params.Encode()

	url := c.host + "/v1/user/login"

	data, err := c.doPost(url, body, true)
	if err != nil {
		return nil, err
	}

	resp := &LoginResponse{}

	if err = json.Unmarshal(data, &resp); err != nil {
		return nil, err
	}

	return resp, nil
}

func (c *MatchClient) ListAddress() (*ListAddressResponse, error) {
	url := c.host + "/address"

	data, err := c.doGet(url, false)
	if err != nil {
		return nil, err
	}

	resp := &ListAddressResponse{}

	if err = json.Unmarshal(data, &resp); err != nil {
		return nil, err
	}

	return resp, nil
}
