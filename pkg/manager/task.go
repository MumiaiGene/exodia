package manager

type TaskHandler interface {
	Init()
	DoTask(detail interface{}) error
}

var TaskHandlerMap = map[string]TaskHandler{
	"match": &MatchInterface{},
}
