# Vrains iOS

原生 Swift / SwiftUI App，支持 iOS 17 及以上系统。主界面包含主页、卡组、决斗、活动和查找五个页签。

## 目录结构

```text
ios/
├── .gitignore
├── README.md
├── dev.sh
├── Vrains.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/Vrains.xcscheme
├── Vrains/
│   ├── *.swift
│   ├── Info.plist
│   ├── LaunchScreen.storyboard
│   ├── Assets.xcassets/
│   └── CardData/
└── scripts/
    ├── local_resources.py
    ├── device_provisioning.py
    └── validate_simulator_signing.sh
```

| 部分 | 作用 |
| --- | --- |
| `Vrains/` | SwiftUI 页面、业务模型、网络请求、SQLite 数据访问、账号存储及图片导出 |
| `Vrains/Assets.xcassets/` | App 图标、颜色和界面图标，由 Xcode 编译为资源目录 |
| `Vrains/CardData/` | 卡片数据库、运行时 SQL、卡图及界面素材，由 Xcode 整体复制到 App Bundle |
| `Vrains.xcodeproj/` | 定义源码、资源、构建设置、签名检查和配置嵌入阶段 |
| `dev.sh` | 检查开发环境、构建 App、安装并启动模拟器或真机 App |
| `scripts/local_resources.py` | 打包与还原本地资源、读取和校验配置、嵌入构建配置 |
| `scripts/device_provisioning.py` | 检查真机描述文件的账号、设备、App 标识及有效期 |
| `scripts/validate_simulator_signing.sh` | 校验模拟器构建的本地签名设置，保证 Keychain 访问所需的 App 身份 |

## 本机准备

以下命令均在项目根目录执行。

1. 安装 Xcode 和 iOS 模拟器，使用 `xcode-select` 或 `DEVELOPER_DIR` 选择开发环境。
2. 安装卡图解密依赖，并使用本地资源包还原配置、数据库和素材：

   ```sh
   python3 -m pip install cryptography
   python3 ios/scripts/local_resources.py unpack <资源包路径>
   ```

3. 创建 `config/signing.xcconfig`。字段格式参考 `config/signing.example.xcconfig`。模拟器使用本地签名，文件中的 Team ID 可以留空：

   ```xcconfig
   DEVELOPMENT_TEAM =
   ```

   真机使用自己的 Apple Team ID，并在 Xcode 中登录对应的开发账号。Xcode 构建时会读取该文件，模拟器和真机构建都需要准备它。

## 构建与运行

```sh
bash ios/dev.sh doctor
bash ios/dev.sh open
bash ios/dev.sh build
bash ios/dev.sh run
```

`doctor` 检查 Xcode、Swift、iOS SDK 和模拟器；`open` 打开 Xcode 工程；`build` 生成模拟器 App；`run` 编译、安装并启动模拟器 App。`build` 和 `run` 共用 `ios/.build/DerivedData/`，模拟器构建产物位于 `ios/.build/DerivedData/Build/Products/Debug-iphonesimulator/Vrains.app`。

指定模拟器或真机时使用：

```sh
bash ios/dev.sh run <模拟器 UDID>
bash ios/dev.sh run-device <真机 UDID>
```

App 启动时加载本地资料并检查卡包、禁限卡表和卡图更新。用户确认后下载并事务更新数据库。新闻、账号、赛事和集换社功能使用实际服务接口；`--uitesting` 启动参数为界面验证提供模拟数据。

## 配置与资源迁移

| 本机位置 | 内容 |
| --- | --- |
| `.private/config.json` | 服务地址、请求身份和协议参数 |
| `.private/jhs-profile.json` | JHS 协议配置 |
| `config/signing.xcconfig` | 本机 Apple Team 签名配置 |
| `.local-resources/` | 资源迁移 ZIP 与完整卡图下载缓存 |
| `ios/.build/` | 构建、运行与验证产物 |

Xcode 构建阶段调用 `local_resources.py embed-config`，校验两份 JSON，并复制为 App Bundle 中的 `PrivateConfiguration.json` 和 `JHSProtocolProfile.json`。账号凭据由设备 Keychain 管理。

资源包包含 `.private/` 中的服务与协议配置、`CardData/` 中的数据库和小型素材，以及 `Assets.xcassets/`。完整卡图通过配置中的 ZIP 地址下载、解密并还原到 `CardData/NeuronArtworks/`；下载缓存支持复用与续传。本机签名配置由开发者单独管理。

```sh
python3 ios/scripts/local_resources.py pack
python3 ios/scripts/local_resources.py pack --output <新资源包路径>
python3 ios/scripts/local_resources.py unpack <资源包路径>
```

默认资源包为 `.local-resources/vrains-resources.zip`。打包使用 SQLite 备份接口生成数据库快照；还原验证文件清单、大小和 SHA-256。已有文件内容一致时跳过，替换不同内容的文件使用 `unpack <资源包路径> --force`。打包输出需要使用新文件名。资源包包含实际配置，使用安全渠道保存和传递。

`EXODIA_PRIVATE_CONFIG` 指定构建和开发工具读取的共用配置路径；`JHS_PROFILE_SOURCE` 指定构建读取的 JHS 配置路径。
