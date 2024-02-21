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
	"exodia.cn/pkg/handler"
	"github.com/gin-gonic/gin"
)

func main() {
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery())

	// Bot Router
	router.POST("/event", handler.EventRouteHandler)
	router.POST("/message", handler.MessageRouteHandler)
	router.POST("/challenge", handler.ChallengeHandler)

	// API Router
	userRouter := router.Group("/user")
	{
		userRouter.POST("/add", handler.AddUserRouter)
		userRouter.GET("/list", handler.ListUserRouter)
	}
	matchRouter := router.Group("/match")
	{
		matchRouter.POST("/signup", handler.SignUpMatchRouter)
		matchRouter.POST("/list", handler.ListMatchRouter)
	}

	srv := http.Server{
		Addr:    fmt.Sprintf(":%d", common.Config.Base.Port),
		Handler: router,
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

	logPath := path.Join(common.Config.Base.LogPath, "exodia.log")
	logFile, err := os.OpenFile(logPath, os.O_RDWR|os.O_CREATE|os.O_APPEND, 0766)
	if err != nil {
		log.Panic(err)
	}
	log.SetOutput(logFile)
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	gin.DefaultWriter = logFile
}
