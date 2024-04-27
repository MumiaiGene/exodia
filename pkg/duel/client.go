package duel

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"exodia.cn/pkg/common"
)

const DefaultUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36 MicroMessenger/6.8.0(0x16080000) NetType/WIFI MiniProgramEnv/Mac MacWechat/WMPF MacWechat/3.8.6(0x13080610) XWEB/1156"

type MatchClient struct {
	client *http.Client
	host   string
	token  string
}

func NewMatchClient(token string) *MatchClient {
	client := &MatchClient{
		client: &http.Client{
			Timeout: 3 * time.Second,
		},
		host:  common.Config.Match.Host,
		token: token,
	}

	return client
}

func (c *MatchClient) addCommonHeader(r *http.Request) {
	r.Header.Add("accept", "*/*")
	r.Header.Add("sec-fetch-site", "cross-site")
	r.Header.Add("sec-fetch-mode", "cors")
	r.Header.Add("sec-fetch-dest", "empty")
	r.Header.Add("accept-encoding", "gzip, deflate, br")
	r.Header.Add("accept-language", "zh-CN,zh;q=0.9")
	r.Header.Add("xweb_xhr", "1")
	r.Header.Add("referer", "https://servicewechat.com/wx0f162bee4c2192be/107/page-frame.html")
	r.Header.Add("user-agent", DefaultUA)
}

func (c *MatchClient) doPost(url string, body string, sig bool) (json.RawMessage, error) {
	var result MatchResponse
	r, err := http.NewRequest("POST", url, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	c.addCommonHeader(r)
	r.Header.Add("content-type", "application/x-www-form-urlencoded")
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
	c.addCommonHeader(r)
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

	start := time.Now()
	resp, err := c.client.Do(r)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()

	log.Printf("path: %s, response: %v", r.URL.Path, resp.StatusCode)

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	log.Printf("path: %s, latency: %v", r.URL.Path, time.Since(start))

	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	if result.Code != 200 {
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
	params.Add("status", fmt.Sprint(p.Status))
	params.Add("page", fmt.Sprint(p.Page))
	params.Add("limit", fmt.Sprint(p.Limit))
	if p.AreaId > 0 {
		params.Add("area_code", fmt.Sprint(p.AreaId))
	}
	if p.CityId > 0 {
		params.Add("city_id", fmt.Sprint(p.CityId))
	}
	if p.StartType > 0 {
		params.Add("match_start_type", fmt.Sprint(p.StartType))
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

func (c *MatchClient) SendIdentityCard(matchId string, name string, cardId string) error {
	params := url.Values{}
	params.Add("match_id", matchId)
	params.Add("name", name)
	params.Add("card", cardId)
	body := params.Encode()

	url := c.host + "/v1/match/card/info"

	_, err := c.doPost(url, body, true)
	if err != nil {
		return err
	}

	return nil
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

func (c *MatchClient) ListRanking() (*RankingResponse, error) {
	params := url.Values{}
	params.Add("type", "2")
	params.Add("page", "1")
	params.Add("limit", "40")
	body := params.Encode()

	url := c.host + "/v1/points/ranking"

	data, err := c.doPost(url, body, true)
	if err != nil {
		return nil, err
	}

	resp := &RankingResponse{}

	if err = json.Unmarshal(data, &resp); err != nil {
		return nil, err
	}

	return resp, nil
}

func (c *MatchClient) ShowSwissInfo(matchId string, limit uint32) (*SwissRankResponse, error) {
	baseUrl, _ := url.Parse(c.host + "/v1/match/against/resultswiss/" + matchId)
	params := url.Values{}
	params.Add("page", "1")
	params.Add("limit", fmt.Sprint(limit))
	baseUrl.RawQuery = params.Encode()

	data, err := c.doGet(baseUrl.String(), true)
	if err != nil {
		return nil, err
	}

	resp := &SwissRankResponse{}

	if err = json.Unmarshal(data, &resp); err != nil {
		return nil, err
	}

	return resp, nil
}
