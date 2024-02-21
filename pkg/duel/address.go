package duel

type AreaInfo struct {
	Id   uint32 `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}

type DuelCity struct {
	AreaInfo
	AreaList []AreaInfo `json:"areaList"`
}

type DuelRegion struct {
	AreaInfo
	CityList []DuelCity `json:"cityList"`
}

type ListAddressResponse struct {
	Result []DuelRegion `json:"res"`
}

var CityMap = map[string]map[string]uint32{}
var AreaMap = map[string]map[string]string{}

func init() {
	client := NewMatchClient("")

	resp, err := client.ListAddress()
	if err == nil {
		for _, region := range resp.Result {
			CityMap[region.Name] = map[string]uint32{}
			AreaMap[region.Name] = map[string]string{}
			for _, city := range region.CityList {
				CityMap[region.Name][city.Name] = city.Id
				AreaMap[region.Name][city.Name] = city.Code
			}
		}
	}
}
