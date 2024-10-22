package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"exodia.cn/pkg/common"
	"exodia.cn/pkg/duel"
)

func main() {
	var UserMap = map[string]uint32{}
	var UserInMap = map[string]uint32{}

	log.SetOutput(io.Discard)

	if len(common.Config.Users) == 0 {
		fmt.Printf("no user config\n")
		os.Exit(1)
	}

	duel.InitUser(common.Config.Users)

	client := duel.NewMatchClient(common.Config.Users[0].Token)

	rank_resp, err := client.ListRanking()
	if err != nil {
		panic(err)
	}

	for _, res := range rank_resp.Result {
		UserMap[res.Name] = 0
		UserInMap[res.Name] = 0
	}

	time.Sleep(1 * time.Second)

	p := &duel.ListParams{
		IsOcg:     true,
		StartType: 4,
		Type:      make([]duel.MatchType, 0),
		Status:    8, // 已结束
		Limit:     32,
	}
	p.Type = append(p.Type, duel.Rank)

	currentMonth := time.Date(time.Now().Year(), time.Now().Month(), 1, 0, 0, 0, 0, time.Local)

	for page := 1; page <= 20; page++ {
		p.Page = uint32(page)
		num := 0

		resp, err := client.ListMatches(p)
		if err != nil {
			panic(err)
		}

		for _, match := range resp.Matches {
			if match.StartAt < currentMonth.Unix() {
				continue
			}

			swiss_resp, err := client.ShowSwissInfo(fmt.Sprint(match.Id), 128)
			if err != nil {
				swiss_resp, err = client.ShowSwissInfo(fmt.Sprint(match.Id), 128)
				if err != nil {
					panic(err)
				}
			}

			if swiss_resp.Count > 128 {
				fmt.Printf("match: %v %v %v\n", match.Name, swiss_resp.Result[0].Name, swiss_resp.Count)
			}

			for _, swiss := range swiss_resp.Result {
				_, ok := UserMap[swiss.Name]
				if ok {
					UserMap[swiss.Name]++
				}
			}

			num++
		}

		if num == 0 {
			break
		}

		fmt.Printf("processing: page:%v, num: %v\n", page, num)

		time.Sleep(1 * time.Second)
	}

	// 进行中
	p.Status = 3
	p.Page = 1
	p.Limit = 128

	resp, err := client.ListMatches(p)
	if err != nil {
		panic(err)
	}

	if len(resp.Matches) > 128 {
		fmt.Printf("match in process is more than 128\n")
	}

	for _, match := range resp.Matches {
		if match.StartAt < currentMonth.Unix() {
			continue
		}

		swiss_resp, err := client.ShowSwissInfo(fmt.Sprint(match.Id), 128)
		if err != nil {
			fmt.Printf("%v\n", err)
			continue
		}

		for _, swiss := range swiss_resp.Result {
			_, ok := UserInMap[swiss.Name]
			if ok {
				fmt.Printf("%d: %v(%d)\n", swiss.Rank, swiss.Name, swiss.Score)
				UserInMap[swiss.Name]++
			}
		}

	}

	fmt.Println("-----------------------------------------------------")

	for _, res := range rank_resp.Result {
		fmt.Printf("%d: %v[%d+%d] %d\n", res.Rank, res.Name, UserMap[res.Name], UserInMap[res.Name], res.Points)
	}

}
