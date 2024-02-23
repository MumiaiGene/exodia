package handler

import (
	"net/http"

	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/task"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

type ListMatchRequest struct {
	UserId string          `json:"open_id"`
	Param  duel.ListParams `json:"param"`
}

type SignUpParam struct {
	MatchId     string `json:"match_id"`
	MatchName   string `json:"match_name"`
	AutoSignUp  bool   `json:"auto_signup"`
	NeedCaptcha bool   `json:"need_captcha"`
}

type SignUpMatchRequest struct {
	UserId string      `json:"open_id"`
	Param  SignUpParam `json:"param"`
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
