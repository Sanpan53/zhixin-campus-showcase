# 知新校园 · 智能知识库（面试展示版）

> **本仓库为面试展示版本，仅提供部署配置和技术说明，不包含完整业务源码及敏感数据。**
> 完整源码可在技术面试时通过屏幕共享讲解。

一个面向校园规章、办事指南与课程资料的 RAG（Retrieval-Augmented Generation）知识库系统。学生用自然语言提问，系统从私有文档中召回依据、生成带引用的答案，并按学生 / 教师 / 管理员角色和知识库授权做权限隔离。

本展示包用于让面试官或 HR 快速理解项目做了什么、怎么运行、技术取舍是什么；不用于生产部署。

---

## 1. 项目背景

校园里的制度文件、办事指南、培养方案和课程资料通常分散在多个系统里。学生想查“宿舍钥匙能借多久”“换宿舍找谁批”“本科生能借几本书”，往往要在 PDF、通知和 FAQ 之间来回翻找，而且很难判断答案是否仍然有效。

这个项目要解决三个问题：

1. **找得到**：多格式文档统一入库，普通文档（md、pdf、Excel、docx、doc）和 QA/FAQ 文档分别采用合适的分块策略。
2. **答得准、可核实**：向量检索 + 全文检索双路召回，RRF 融合后精排，生成答案必须带来源引用。
3. **权限隔离**：学生 / 教师 / 管理员三级角色，知识库级 ACL，检索前逐库校验权限。

---

## 2. 核心能力

| 能力        | 说明                                                                         |
| ----------- | ---------------------------------------------------------------------------- |
| 多格式解析  | PDF / DOCX / DOC / Markdown / TXT / HTML；旧版 DOC 经 LibreOffice 转换后解析 |
| 双分块模式  | 普通文档采用结构感知 + 滑动窗口分块；QA/FAQ 文档按“一问一答”生成 Chunk     |
| QA 格式校验 | 空问题、缺答案、短答案、重复问题、无法识别正文等生成可视化报告               |
| 混合检索    | pgvector 向量检索 + PostgreSQL 全文检索，RRF 融合去重                        |
| 查询增强    | HyDE 生成假设答案，与原问题两路召回后再融合                                  |
| 精排与降级  | Reranker 对候选精排；超时或失败时回退到 RRF 排序，不让整条链路崩掉           |
| 引用溯源    | 生成时使用 `[参考N]` 编号，后处理解析引用并关联文档、章节、页码和摘要      |
| 流式问答    | SSE 逐字输出，支持多轮会话和历史记录                                         |
| 权限隔离    | 学生 / 教师 / 管理员角色 + 知识库 ACL，请求入口逐库校验                      |
| 效果评估    | Hit Rate / MRR / Faithfulness，支持按评估版本对比                            |
| 可观测性    | 健康检查、TraceId 日志、Prometheus 指标（完整部署包含）                      |

---

## 3. 系统架构

![系统架构](docs/architecture.png)

**两条管道：**

- **离线索引**：上传 → 解析与校验 → 类型判定 → 分块 → Embedding → 入库（Chunk + 向量 + tsvector）→ 索引完成。
- **在线问答**：提问 → 权限校验 → HyDE 查询改写 → 向量 / 全文双路召回 → RRF 融合 → Reranker 精排 → 置信度过滤 → 上下文裁剪 → Prompt + LLM → SSE 流式答案 + 引用。

![关键流程](docs/workflow.png)

---

## 4. 界面展示

以下截图来自本地演示环境，用于展示实际页面与交互流程。截图中的示例数据可能与随附种子数据不同，页面品牌和文案以实际运行版本为准；办公地点和联系电话已脱敏。

### 4.1 首页与知识库管理

![首页](docs/首页.png)

*首页：搜索入口、常用分类、热门问题和最近更新。*

![知识库列表](docs/知识库展示.png)

*知识库管理：知识库数量、可见性、当前用户权限和文档管理入口。*

### 4.2 文档入库与分块

![文档管理](docs/文档界面.png)

*文档管理：多格式上传、索引状态、文档模式、Chunk 数量和重建索引入口。*

![普通文档 Chunk](docs/文档切分内容.png)

*普通文档分块：按章节和页码切分，可查看内容摘要与 Token 数。*

![QA 文档管理](docs/QA文档界面.png)

*QA 文档入库：自动识别文档模式，展示有效问答对和异常数量。*

![QA 文档 Chunk](docs/QA文档切分内容.png)

*QA 分块：按“一问一答”生成 Chunk，保留分类、适用对象和审核状态；联系方式已脱敏。*

### 4.3 智能问答与引用溯源

![QA 对话](docs/QA对话.png)

*带引用的问答：答案标注来源文档，展示耗时并支持有帮助 / 没帮助反馈；联系方式已脱敏。*

![多源引用](docs/对话框.png)

*多源引用：回答中的每条依据都能追溯到具体文档和 Chunk。*

### 4.4 评估与成本观测

![评估结果](docs/性能评测.png)

*评估结果：演示环境“高频问答”知识库的 12 题标注集，Hit Rate 12/12、MRR 0.8604、Faithfulness 1.0000。*

![评估数据集](docs/性能评测数据集.png)

*评估数据集：题目、期望答案和期望 Chunk 标注界面；涉及办公地点与电话的答案已脱敏。*

![成本监控](docs/成本监控.png)

*成本与 Token 监控：按 Context / Generation 拆分，观察问答链路的成本结构。*

---

## 5. 技术栈

| 层级     | 技术                                                             |
| -------- | ---------------------------------------------------------------- |
| 前端     | React 18、TypeScript、Vite、Ant Design、Zustand                  |
| 后端     | Python 3.11、FastAPI、SQLAlchemy 2.0、Pydantic                   |
| 数据库   | PostgreSQL 16、pgvector、PostgreSQL 全文检索                     |
| 缓存     | Redis 7                                                          |
| 文件存储 | MinIO（S3 兼容）                                                 |
| 大模型   | 阿里云百炼 DashScope：Qwen Plus、text-embedding-v3、qwen3-rerank |
| 部署     | Docker Compose、Nginx、多阶段镜像构建                            |
| 监控     | Prometheus、Grafana（完整部署包含；本展示版为最小运行环境）      |

> 模型、Embedding 和 Reranker 均为第三方 API；前端页面基于开源管理端模板修改。项目的主要工作在后端的 RAG 链路、权限、评估和部署。

---

## 6. 仓库内容

```text
project-showcase/
├── README.md                 # 项目背景、架构、启动说明
├── PROJECT_CASE.md           # 职责、难点、指标口径、个人贡献、已知局限
├── docker-compose.yml        # 一键运行（只引用预构建镜像）
├── .env.example              # 仅占位符，不含真实凭证
├── .gitignore
├── config/
│   └── db/
│       ├── 01-schema.sql     # 表结构（部署资产，不含业务源码）
│       └── 02-seed.sql       # 虚构演示种子数据
├── docs/
│   ├── architecture.png      # 系统架构图
│   ├── workflow.png          # 关键流程图
│   └── *.png                 # 界面、评估与成本监控截图
└── sample-data/
    ├── README.md             # 演示数据说明与操作步骤
    ├── docs/                 # 虚构的普通文档
    ├── qa/                   # 虚构的 QA 格式文档
    └── eval/                 # 演示评估问题集
```

**本仓库不包含：** 前后端业务源码、自动化测试、真实用户数据、内部地址、API Key、`.git` 历史。`sample-data/` 为虚构示例；界面截图仅用于展示功能，联系方式已脱敏。镜像由完整源码仓库单独构建后推送。

---

## 7. 快速开始

### 7.1 环境要求

- Docker Desktop 或 Docker Engine，包含 Docker Compose v2
- 建议至少 4 GB 可用内存
- 一个可用的阿里云百炼 DashScope API Key（用于生成、Embedding 和精排）
- 能访问镜像仓库（如果镜像设为私有，需要先登录）
- 两个镜像已发布到 `ghcr.io/sanpan53/...`；如果镜像未发布或未登录，`docker compose up` 会报 `manifest unknown` / `unauthorized`

### 7.2 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，至少替换以下内容：

```dotenv
APP_IMAGE=ghcr.io/sanpan53/zhixin-campus-app:1.0.1
FRONTEND_IMAGE=ghcr.io/sanpan53/zhixin-campus-frontend:1.0.1

DASHSCOPE_API_KEY=your_dashscope_api_key_here
DB_PASSWORD=change-me-db-password
MINIO_ROOT_PASSWORD=change-me-minio-password
```

> `.env` 只保存在本地。不要提交到 Git，也不要通过聊天工具发送真实 Key。

如果镜像是私有包，先登录：

```bash
echo "$GHCR_READ_TOKEN" | docker login ghcr.io -u sanpan53 --password-stdin
```

`GHCR_READ_TOKEN` 应是只读、短期有效的 Personal Access Token（至少包含 `read:packages`），不要使用带写权限的个人令牌。

### 7.3 启动

```bash
docker compose pull
docker compose up -d
docker compose ps
```

首次启动会拉取镜像，并在 PostgreSQL 数据卷为空时执行 `config/db/01-schema.sql` 和 `02-seed.sql`。如果本地已有同名旧镜像，先执行 `docker compose pull`，避免继续使用旧版本。

> 初始化脚本只在数据卷为空时执行。如果之前运行过旧版展示包，数据库里仍是旧的种子数据；需要先执行 `docker compose down -v` 清空数据卷，再重新启动。

### 7.4 检查运行状态

```bash
curl -fsS http://localhost:8000/health | python3 -m json.tool
```

返回 `"status": "UP"`，且 `db`、`redis`、`minio` 均为 `UP`，表示后端已就绪。

> 健康检查只覆盖本地依赖组件，**不检查 DashScope**。第一次提问时才会真正调用模型服务；如果 Key 无效，健康检查仍然可能是 UP。

### 7.5 访问地址

| 服务          | 地址                                                        | 说明                      |
| ------------- | ----------------------------------------------------------- | ------------------------- |
| Web 应用      | [http://localhost:3000](http://localhost:3000)               | 系统主入口                |
| Swagger API   | [http://localhost:8000/docs](http://localhost:8000/docs)     | 后端接口文档              |
| 健康检查      | [http://localhost:8000/health](http://localhost:8000/health) | 依赖组件状态              |
| MinIO Console | [http://localhost:9001](http://localhost:9001)               | 可选，账号密码见 `.env` |

PostgreSQL、Redis 和 MinIO 的 S3 API 均未映射到宿主机，只在 Compose 内网通信。

### 7.6 演示账号

| 用户名       | 密码      | 角色   | 可用范围                         |
| ------------ | --------- | ------ | -------------------------------- |
| `admin`      | `demo123` | 管理员 | 全部功能                         |
| `teacher001` | `demo123` | 教师   | 问答、公开库、人事处库及文档管理 |
| `student001` | `demo123` | 学生   | 问答、公开库、计算机学院库       |

> 这些账号写死在演示版认证实现中，仅用于本地演示。公开部署前必须替换为正式认证方案，不能直接上线。

### 7.7 停止与重置

```bash
docker compose down       # 停止并保留数据卷
docker compose down -v    # 停止并删除数据库、缓存和对象存储数据
```

`down -v` 会永久删除本地演示数据，请在确认不需要保留后执行。

---

## 8. 五分钟演示路径

详细操作见 [`sample-data/README.md`](sample-data/README.md)。

1. 用 `admin / demo123` 登录。
2. 进入“知识库管理”，在“校园制度”上传 `sample-data/docs/01-学生宿舍管理办法.md` 和 `02-奖学金申请指南.md`。
3. 在“校园服务与办事指南”上传 `03-图书馆服务说明.md`，以及 QA 格式的 `qa/04-校园服务问答.md`（文档类型选择“QA/FAQ 文档”）。
4. 可选：在“计算机课程资料”上传 `05-数据库系统概论-复习提纲.md`，在“人事制度”上传 `06-教师请假与调课流程.md`，用于演示私有知识库和权限隔离。
5. 等待状态变为“已完成”，打开 Chunk 窗口检查分块边界和 QA 报告。
6. 在“智能问答”提这些问题，观察流式输出和引用来源：
   - “宿舍钥匙忘带了可以借多久？”
   - “换宿舍需要经过哪些人批准？”
   - “本科生一次能借几本书？”
7. 分别用 `student001`、`teacher001` 登录，对比知识库列表，并分别提问课程问题和人事问题，演示权限隔离。
8. 用 `admin` 进入“效果评估”，查看 Hit Rate / MRR / Faithfulness 的含义和 Chunk 标注流程。

---

## 9. 效果评估

评估流水线计算三项指标：

| 指标         | 含义                            | 计算方式                                        |
| ------------ | ------------------------------- | ----------------------------------------------- |
| Hit Rate     | 期望 Chunk 是否出现在精排结果中 | 命中题数 / 总题数                               |
| MRR          | 首个正确 Chunk 的排名质量       | 每题取 `1/rank`，未命中计 0，再对总题数求平均 |
| Faithfulness | 答案相对检索上下文的忠实程度    | 对带参考答案的题调用忠实性检查，取平均          |

**评估现状：**

- 完整源码仓库中有 50 道题的固定测试集，覆盖 5 个知识库，每个知识库 10 题；40 题 `dev`、10 题 `holdout`；25 题 easy、25 题 medium。
- 截至 2026-10-21，50 题的 `expected_chunk_ids` 全部为 `null`，`review_status` 为 `pending_chunk_annotation`。
- 因此 50 题固定测试集当前**没有可复现的 Hit Rate / MRR 基线**；完成 Chunk 标注前运行评估，命中会计为 0。12 题演示集的结果见第 4 节，两者口径不同，不能混用。
- 界面截图展示的是演示环境“高频问答”知识库的 12 题标注集（12 题均已标注）：Hit Rate 12/12、MRR 0.8604、Faithfulness 1.0000；这是单库小样本结果，用于验证评估流程，不代表 50 题固定测试集或线上泛化效果。
- 评估代码的命中判定使用精排 Top-10（`RERANK_TOP_K=10`），因此指标口径是 **Hit@10 / MRR@10**。
- Faithfulness 由项目内的 LLM 判定器打分，不是直接调用 RAGAS 库。

详细的评测协议和指标定义见 [`PROJECT_CASE.md`](PROJECT_CASE.md)。所有指标均以实际运行结果为准。

---

## 10. 安全边界与已知限制

- **认证是演示实现**：演示账号写死在代码中，token 存在单进程内存里。多 worker / 多副本部署会导致 token 不共享；生产应接 SSO / LDAP，并把 token 或会话迁移到 Redis / 数据库。
- **没有 HTTPS、限流、WAF 和上传内容审计**：对外提供服务前必须补齐。
- **MinIO 控制台端口 9001 映射到宿主机**：仅便于本地查看；共享演示环境建议关闭该端口映射。
- **中文全文检索使用 PostgreSQL `simple` 配置**，没有接 zhparser / pg_jieba，中文分词效果有限；当前检索主要依赖向量召回，全文召回作为精确词的补充。
- **不做 OCR**：扫描版 PDF 需要先完成 OCR，再上传。
- **置信度过滤是软过滤**：低于阈值的 Chunk 会被剔除；如果全部低于阈值，会保留最高分的 1 条，而不是直接返回“未找到”。只有候选完全为空时才会返回未找到。
- **没有正式迁移工具**：`01-schema.sql` 只在空数据卷首次启动时执行；已有数据升级需要备份后手动执行迁移脚本。
- **评估数据口径不同**：50 题固定测试集尚未完成标注；12 题演示集已完成标注，但样本较小，不能作为泛化效果结论。
- **外部模型依赖**：生成、Embedding、Reranker 都依赖 DashScope；延迟、额度和可用性不受本项目控制。Reranker 有 800ms 超时降级，生成和 Embedding 没有本地兜底。

---

## 11. 常见问题

### 启动时报错 `APP_IMAGE` / `DASHSCOPE_API_KEY` 未设置

说明还没有正确复制或填写 `.env`。执行 `cp .env.example .env`，替换所有 `your-*` 和 `change-me-*` 占位符。

### 拉取镜像返回 401 / 403

镜像可能是私有包。先执行 `docker login ghcr.io`，并确认令牌有 `read:packages` 权限；如果镜像不存在，检查标签是否与 `.env` 中一致。

### `docker compose ps` 里 app 一直是 unhealthy

```bash
docker compose logs --tail=200 app
curl -v http://localhost:8000/health
```

常见原因是数据库密码不一致、PostgreSQL 初始化脚本执行失败、Redis / MinIO 还没就绪，或宿主机端口被占用。

### 上传文档后一直停在“处理中”或索引失败

依次检查：

```bash
docker compose ps
docker compose logs --tail=200 app
curl -fsS http://localhost:8000/health
```

常见原因：DashScope Key 无效、文件格式异常、QA 文档问答不成对、扫描 PDF 未 OCR、数据库缺少字段。

### Hit Rate / MRR 为 0，但 Faithfulness 很高

这通常不是“检索完全失效”，而是评估题还没有标注期望 Chunk。未标注时 `expected_chunk_ids` 为空，代码会把每题都判为未命中。需要先完成期望 Chunk 标注，再运行评估；标注流程见 [`PROJECT_CASE.md`](PROJECT_CASE.md)。

---

## 12. 数据与许可

- `sample-data/` 中的结构化示例数据为虚构；`docs/` 中的界面截图来自开发环境，仅用于展示功能，其中办公地点和联系电话已脱敏。
- 本展示包未声明开源许可证。未经项目所有者许可，不得复制、分发或用于商业用途。
- 如需在演示中使用真实文档，请先取得授权并完成脱敏；不要把真实学生信息、教师信息或内部地址提交到仓库或镜像。

---

**维护者：** 吴梦成 · <mm9y1688@163.com> · [GitHub @Sanpan53](https://github.com/Sanpan53)

**相关文档：** [`PROJECT_CASE.md`](PROJECT_CASE.md) · [`sample-data/README.md`](sample-data/README.md)
