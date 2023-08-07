package handler

import (
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

type ChallengeParams struct {
	Challenge string `json:"challenge"`
	Token     string `json:"token"`
	Type      string `json:"type"`
}

func ChallengeHandler(ctx *gin.Context) {
	var param ChallengeParams
	err := ctx.BindJSON(&param)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println(param.Challenge)

	ctx.JSON(
		http.StatusOK,
		gin.H{
			"challenge": param.Challenge,
		},
	)
}
