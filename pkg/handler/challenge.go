package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
)

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
