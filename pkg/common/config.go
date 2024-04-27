package common

import (
	"fmt"
	"path"
	"path/filepath"

	"github.com/spf13/viper"
)

// AppName for app register, should add ldflags:
// go build -ldflags "-X exodia.cn/pkg/common.AppName=exodia"
var AppName = "exodia"

var Config ExodiaConfig

const (
	DEFAULT_PORT   = 8080
	DEFAULT_LOGDIR = "/var/log/exodia"
)

type BaseConfig struct {
	LogPath string `mapstructure:"log_dir"`
	Port    int    `mapstructure:"port"`
}

type BotConfig struct {
	WebHook   string `mapstructure:"webhook"`
	AppId     string `mapstructure:"app_id"`
	AppSecret string `mapstructure:"app_secret"`
}

type WxConfig struct {
	Code string `mapstructure:"code"`
}

type MatchConfig struct {
	Host      string `mapstructure:"host"`
	Secret    string `mapstructure:"secret"`
	Iv        string `mapstructure:"iv"`
	SigPrefix string `mapstructure:"sig_prefix"`
	Token     string `mapstructure:"token"`
}

type CaptchaConfig struct {
	Secret string `mapstructure:"secret"`
	Iv     string `mapstructure:"iv"`
}

type UserConfig struct {
	Id    string `mapstructure:"id"`
	Name  string `mapstructure:"name"`
	Card  string `mapstructure:"card"`
	Phone string `mapstructure:"phone"`
	Token string `mapstructure:"token"`
	Area  uint32 `mapstructure:"area"`
}

type ExodiaConfig struct {
	Base    BaseConfig    `mapstructure:"base"`
	Match   MatchConfig   `mapstructure:"match"`
	Captcha CaptchaConfig `mapstructure:"captcha"`
	Bot     BotConfig     `mapstructure:"bot"`
	Wx      WxConfig      `mapstructure:"wx"`
	Users   []UserConfig  `mapstructure:"user"`
}

func init() {
	configFile := fmt.Sprintf("%s.yml", AppName)
	configPath := path.Join("conf/", configFile)
	viper.SetConfigName(filepath.Base(configPath))
	viper.SetConfigType(filepath.Ext(configPath)[1:])
	viper.AddConfigPath(filepath.Dir(configPath))

	if err := viper.ReadInConfig(); err != nil {
		panic(err)
	}
	if err := viper.Unmarshal(&Config); err != nil {
		panic(err)
	}

	// set default
	if Config.Base.Port == 0 {
		Config.Base.Port = DEFAULT_PORT
	}
	if Config.Base.LogPath == "" {
		Config.Base.LogPath = DEFAULT_LOGDIR
	}
}
