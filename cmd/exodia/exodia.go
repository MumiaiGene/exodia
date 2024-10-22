package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path"
	"syscall"
	"time"

	"exodia.cn/pkg/common"
	"exodia.cn/pkg/duel"
	"exodia.cn/pkg/router"
	"exodia.cn/pkg/task"
	"github.com/gin-gonic/gin"
)

func main() {
	g := gin.New()
	g.Use(gin.Logger(), gin.Recovery())

	// Bot Router
	g.POST("/event", router.EventRouteHandler)
	g.POST("/message", router.MessageRouteHandler)
	g.POST("/challenge", router.ChallengeHandler)

	// API Router
	userRouter := g.Group("/user")
	{
		userRouter.POST("/add", router.AddUserRouter)
		userRouter.GET("/list", router.ListUserRouter)
	}
	matchRouter := g.Group("/match")
	{
		matchRouter.POST("/signup", router.SignUpMatchRouter)
		matchRouter.POST("/list", router.ListMatchRouter)
		matchRouter.POST("/schedule", router.ScheduleMatchRouter)
	}

	duel.InitUser(common.Config.Users)

	task.GlobalManager.StartConsume()

	srv := http.Server{
		Addr:    fmt.Sprintf(":%d", common.Config.Base.Port),
		Handler: g,
	}

	log.Println("Server starting")

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("Failed to start server, err: ", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutdown Server ...")

	task.GlobalManager.StopConsume()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server Shutdown:", err)
	}

	// catching ctx.Done(). timeout of 5 seconds.
	select {
	case <-ctx.Done():
		log.Println("timeout of 5 seconds.")
	default:

	}
	log.Println("Server exiting")
}

func init() {
	gin.SetMode(gin.ReleaseMode)
	gin.DisableConsoleColor()

	logPath := path.Join(common.Config.Base.LogPath)
	logFile, err := os.OpenFile(path.Join(logPath, "exodia.log"), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0644)
	if err != nil {
		log.Panic(err)
	}
	log.SetOutput(logFile)
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	ginLogFile, err := os.OpenFile(path.Join(logPath, "access.log"), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0644)
	if err != nil {
		log.Panic(err)
	}

	gin.DefaultWriter = ginLogFile
}
