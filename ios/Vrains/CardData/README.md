# 卡片数据与图片资源

`CardData/` 提供 App 使用的本地 SQLite 数据库、卡图、运行时 SQL 和界面素材。Xcode 将整个目录复制到 App Bundle，App 从 `CardData/` 子目录读取资源。

## 目录结构

```text
CardData/
├── README.md
├── catalog-runtime.sql
├── catalog.sqlite
├── neuron-ja.sqlite
├── neuron-index.json
├── NeuronArtworks/
├── BackPrint.png
├── CardShare/
├── DeckAssets/
├── InterfaceIcons/
└── NeuronUI/
```

| 文件或目录 | 作用 |
| --- | --- |
| `catalog.sqlite` | 卡片属性、各语言文本、别名、卡包、收录、罕贵、禁限卡表和 JHS 版本映射 |
| `catalog-runtime.sql` | 创建 App 查询使用的视图、资料状态表和索引 |
| `neuron-ja.sqlite` | Neuron 日文资料及卡片、异画与资源文件的映射 |
| `neuron-index.json` | 卡图下载资源的索引与版本信息 |
| `NeuronArtworks/` | 按 App 文件命名规则保存的离线 PNG 卡图 |
| `BackPrint.png` | 卡图加载时使用的卡背占位图 |
| `CardShare/` | 卡片分享图片的排版素材 |
| `DeckAssets/` | 卡组界面、投入数量及卡组展示素材 |
| `InterfaceIcons/` | 卡片属性、种类和状态等图标 |
| `NeuronUI/` | 卡片列表使用的界面素材 |

## 数据库加载

首次打开卡片数据库时，App 将 `catalog.sqlite` 复制到 Application Support 下的 `Exodia/Catalog-v2.sqlite`，检查数据库版本、完整性和外键。之后的查询和资料更新使用该可写副本。

`CardDatabase` 打开连接时读取并执行 `catalog-runtime.sql`：

- `app_cards` 将卡片属性、语言文本和别名整理为 App 查询字段，定义名称与效果文本的来源优先级。
- `app_releases` 综合卡包收录与发售记录，提供各地区已发售的最早收录。
- `app_limits` 按日期与赛制选择最新且完整的禁限卡表记录。
- `catalog_state` 保存本地资料的版本与检查状态。
- 索引支持按罕贵和语言查询收录资料。

视图直接查询底层表。SQL 使用 `IF NOT EXISTS`，支持重复执行。

## 资源准备与管理

源码仓库管理 `README.md` 和 `catalog-runtime.sql`。数据库与图片资源通过项目根目录的 `ios/scripts/local_resources.py unpack <资源包路径>` 还原。

资源包保存数据库快照与小型素材。完整卡图从配置指定的 ZIP 下载，脚本使用 Neuron 数据库将资源文件映射为卡片及异画编号，校验、解密后写入 `NeuronArtworks/`。Xcode 构建时将还原的离线卡图一起打包到 App。

配置、签名和资源迁移命令见 [iOS 开发说明](../../README.md)。
