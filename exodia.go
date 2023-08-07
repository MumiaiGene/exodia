package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"exodia.cn/pkg/handler"
	"exodia.cn/pkg/manager"
	"github.com/gin-gonic/gin"
)

func main() {
	router := gin.New()
	router.Use(gin.Recovery())
	// router.GET("/", hello)
	router.POST("/challenge", handler.ChallengeHandler)
	taskRouter := router.Group("/task")
	{
		taskRouter.POST("/add", handler.AddTaskHandler)
		taskRouter.GET("/list", handler.ListTaskHandler)
	}

	srv := http.Server{
		Addr:    ":8080",
		Handler: router,
	}

	manager.TaskManager = manager.CreateManager()

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

	logfile := "exodia.log"
	logFile, err := os.OpenFile(logfile, os.O_RDWR|os.O_CREATE|os.O_APPEND, 0766)
	if err != nil {
		log.Panic(err)
	}
	log.SetOutput(logFile)
	log.SetFlags(log.LstdFlags | log.Lshortfile)
}
