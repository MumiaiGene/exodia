package router

import (
	"fmt"
	"log"
	"net/http"

	"exodia.cn/pkg/bot"
	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/task"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

// Challenge Router
type ChallengeRequest struct {
	Challenge string `json:"challenge"`
	Type      string `json:"type"`
	Token     string `json:"token"`
}

func ChallengeHandler(ctx *gin.Context) {
	var req ChallengeRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	ctx.JSON(
		http.StatusOK,
		gin.H{
			"challenge": req.Challenge,
		},
	)
}

// Match Related Router
type ListMatchRequest struct {
	UserId string          `json:"open_id"`
	Param  duel.ListParams `json:"param"`
}

func ListMatchRouter(ctx *gin.Context) {
	var req ListMatchRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	token := duel.GetUserToken(req.UserId)
	if token == "" {
		ctx.JSON(
			http.StatusForbidden,
			gin.H{
				"msg": "user not logged in or timed out",
			},
		)
		return
	}

	client := duel.NewMatchClient(token)
	resp, err := client.ListMatches(&req.Param)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": err.Error(),
			},
		)
		return
	}

	ctx.JSON(
		http.StatusOK,
		gin.H{"msg": "ok", "matches": resp.Matches},
	)
}

type SignUpMatchRequest struct {
	UserId string           `json:"open_id"`
	Param  duel.SignUpParam `json:"param"`
}

func SignUpMatchRouter(ctx *gin.Context) {
	var req SignUpMatchRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	token := duel.GetUserToken(req.UserId)
	if token == "" {
		ctx.JSON(
			http.StatusForbidden,
			gin.H{
				"msg": "user not logged in or timed out",
			},
		)
		return
	}

	client := duel.NewMatchClient(token)
	if err = client.SignUpMatch(req.Param.MatchId, req.Param.NeedCaptcha); err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": err.Error(),
			},
		)
		return
	}

	ctx.JSON(
		http.StatusOK,
		gin.H{"msg": "ok"},
	)
}

func ScheduleMatchRouter(ctx *gin.Context) {
	var req SignUpMatchRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	token := duel.GetUserToken(req.UserId)
	if token == "" {
		ctx.JSON(
			http.StatusForbidden,
			gin.H{
				"msg": "user not logged in or timed out",
			},
		)
		return
	}

	params := task.ScheduleParam{
		MatchId:     req.Param.MatchId,
		MatchName:   req.Param.MatchName,
		AutoSignUp:  req.Param.AutoSignUp,
		NeedCaptcha: req.Param.NeedCaptcha,
		Token:       token,
	}
	s := task.CreateSchedule(req.UserId, params)
	s.Start()

	ctx.JSON(
		http.StatusOK,
		gin.H{"msg": "ok"},
	)
}

// User Related Router
func ListUserRouter(ctx *gin.Context) {
	users := duel.ListUser()
	code := http.StatusOK
	resp := gin.H{"msg": "ok"}
	if len(users) == 0 {
		code = http.StatusNotFound
		resp["msg"] = "empyt user list"
	}

	resp["users"] = users

	ctx.JSON(
		code, resp,
	)
}

func AddUserRouter(ctx *gin.Context) {
	var new duel.UserMataData
	err := ctx.ShouldBindBodyWith(&new, binding.JSON)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"msg": "invalid request body",
			},
		)
		return
	}

	duel.UpdateUser(new.UserId, &new)

	ctx.JSON(
		http.StatusOK,
		gin.H{"msg": "ok"},
	)
}

// Message Action Router
func MessageRouteHandler(ctx *gin.Context) {
	var req bot.MessageActionRequest
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.Error(fmt.Errorf("invalid request body"))
		ctx.JSON(
			http.StatusOK,
			gin.H{},
		)
		return
	}

	resp, err := MessageActionHandler(req.OpenId, req.Action)
	if err != nil {
		ctx.Error(err)
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{},
		)
		return
	}

	ctx.JSON(
		http.StatusOK, resp,
	)
}

// Event Related Router
func EventRouteHandler(ctx *gin.Context) {
	var req bot.EventRequest
	var resp gin.H = gin.H{"msg": "ok"}
	err := ctx.ShouldBindBodyWith(&req, binding.JSON)
	if err != nil {
		ctx.Error(fmt.Errorf("invalid request body"))
		ctx.JSON(
			http.StatusOK,
			gin.H{},
		)
		return
	}

	log.Printf("event id: %s, type:%s, time: %s", req.Header.EventId, req.Header.EventType, req.Header.CreateTime)

	if _, ok := EventRouterMap[req.Header.EventType]; !ok {
		ctx.Error(fmt.Errorf("invalid event: %s", req.Header.EventType))
		ctx.JSON(
			http.StatusOK,
			gin.H{},
		)
		return
	}
	code, err := EventRouterMap[req.Header.EventType].Handler(req.Event)
	if err != nil {
		ctx.Error(err)
	}

	ctx.JSON(
		code, resp,
	)
}
