# Vrains-Universal

Vrains 是使用 Swift / SwiftUI 开发的 iOS 游戏王卡片工具，支持 iOS 17 及以上系统。

## 功能

| 页面 | 功能 |
| --- | --- |
| 主页 | 新闻列表、轮播图、正文阅读及个人资料入口 |
| 卡组 | 卡组管理、主卡组／额外卡组／副卡组编辑、投入数量与合法性检查、模拟起手及图片导出 |
| 决斗 | 卡组、桌宠、场地与服务器选择，演示匹配及原生对战布局预览 |
| 活动 | 比赛查询、详情与报名、个人对局与成绩填报、排名、店铺查询及定位 |
| 查找 | 本地卡片搜索与筛选、详情、异画、收录、罕贵、禁限状态、收藏及图片分享 |

App 使用 SQLite 保存卡片目录与收录资料，使用本地卡图展示卡片，通过外部服务获取新闻、赛事、账号和集换社资料。账号凭据存储在设备 Keychain。

## 目录结构

```text
.
├── .gitignore
├── README.md
├── config/
│   ├── private.example.json       服务与协议配置字段示例
│   └── signing.example.xcconfig   Apple Team 签名配置示例
└── ios/
    ├── README.md                  开发、构建与资源准备说明
    ├── dev.sh                     Xcode 检查、构建、安装与启动入口
    ├── Vrains.xcodeproj/          Xcode 工程与共享 Scheme
    ├── Vrains/                    App 源码与界面资源
    │   ├── Assets.xcassets/       App 图标、颜色与界面图标
    │   └── CardData/              运行时 SQL、数据库与图片资源
    └── scripts/                   资源迁移、配置嵌入与签名工具
```

源码仓库管理 App 源码、Xcode 工程、界面资源、开发脚本和配置示例。实际服务配置存放在 `.private/`，本机签名配置存放在 `config/signing.xcconfig`；数据库、卡图和迁移包由本地资源流程管理。

## 开发入口

按 [iOS 开发说明](ios/README.md) 准备 Xcode、资源包和本机签名配置，在项目根目录执行：

```sh
bash ios/dev.sh doctor
bash ios/dev.sh open
bash ios/dev.sh build
bash ios/dev.sh run
```

数据库与图片的目录和加载方式见 [CardData 说明](ios/Vrains/CardData/README.md)。
