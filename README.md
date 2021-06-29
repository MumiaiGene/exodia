# exodia
A brpc project to build a ygo-cards website

## QuickStart
```text
❯ curl https://www.exodia.cn/DatabaseService/Card -d '{"name": "青眼白龙"}'

{
    "err_no": 0,
    "err_msg": "success",
    "card_list": [
        {
            "id": 9433350,
            "name": "罪 青眼白龙",
            "text": "这张卡不能通常召唤。从卡组把1只「青眼白龙」除外的场合可以特殊召唤。\r\n①：「罪」怪兽在场上只能有1只表侧表示存在。\r\n②：只要这张卡在怪兽区域存在，其他的自己怪兽不能攻击宣言。\r\n③：没有场地魔法卡表侧表示存在的场合这张卡破坏。",
            "type": "效果怪兽",
            "attack": 3000,
            "defense": 2500,
            "level": 8,
            "race": "龙",
            "attribute": "暗",
            "ability": "特殊召唤"
        },
        {
            "id": 89631139,
            "name": "青眼白龙",
            "text": "以高攻击力著称的传说之龙。任何对手都能粉碎，其破坏力不可估量。",
            "type": "通常怪兽",
            "attack": 3000,
            "defense": 2500,
            "level": 8,
            "race": "龙",
            "attribute": "光",
            "ability": ""
        }
    ]
}
```
## Contribute code
Make sure your code style conforms to [google C++ coding style](https://google.github.io/styleguide/cppguide.html). Indentation is preferred to be 4 spaces.
## Feedback and Getting involved
- Report bugs, ask questions or give suggestions by [Github Issues](https://github.com/MumiaiGene/exodia/issues)
- Subscribe mailing list(genemumiai@qq.com) to get updated with the project
