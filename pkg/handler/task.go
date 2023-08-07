package handler

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"

	"exodia.cn/pkg/manager"
	"exodia.cn/pkg/models"
	"github.com/gin-gonic/gin"
)

type TaskRequestParam struct {
	Name       string            `json:"name"`
	MatchTasks manager.MatchTask `json:"match_task"`
}

func AddTaskHandler(ctx *gin.Context) {
	var params TaskRequestParam

	err := ctx.BindJSON(&params)
	if err != nil {
		ctx.JSON(
			http.StatusBadRequest,
			gin.H{
				"code": http.StatusBadRequest,
				"msg":  err.Error(),
			},
		)
		return
	}

	log.Printf("task name: %s", params.Name)

	task := models.Task{
		Type: "match",
		Name: params.Name,
		Detail: &manager.MatchTask{
			AreaId: params.MatchTasks.AreaId,
			ZoneId: params.MatchTasks.ZoneId,
			IsOcg:  params.MatchTasks.IsOcg,
			Type:   params.MatchTasks.Type,
		},
	}

	manager.TaskManager.AddTask(task)

	ctx.JSON(
		http.StatusOK,
		gin.H{
			"code": http.StatusOK,
			"msg":  "Success",
		},
	)
}

func ListTaskHandler(ctx *gin.Context) {
	list := manager.TaskManager.ListTask()
	if len(list) == 0 {
		ctx.JSON(
			http.StatusNotFound,
			gin.H{
				"code": http.StatusNotFound,
				"msg":  "empty task list",
			},
		)
		return
	}

	data, err := json.Marshal(list)
	if err != nil {
		ctx.JSON(
			http.StatusInternalServerError,
			gin.H{
				"code": http.StatusInternalServerError,
				"msg":  err.Error(),
			},
		)
		return
	}

	ctx.JSON(
		http.StatusOK,
		gin.H{
			"code": http.StatusOK,
			"msg":  string(data),
		},
	)
}
