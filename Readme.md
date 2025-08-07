# postgresbson-docker

本仓库用于自动编译 [buzzm/postgresbson](https://github.com/buzzm/postgresbson) PostgreSQL BSON 扩展，并通过 GitHub Actions workflow 构建和推送 Docker 镜像。

## 功能

- 自动拉取上游 postgresbson 源码并构建
- 可配置 PostgreSQL 版本（默认 16）
- 自动打包为 Docker 镜像并推送到 GitHub Container Registry 或 Docker Hub

## 目录结构

- `Dockerfile`：自动化构建 postgresbson 的 Docker 构建文件
- `.github/workflows/docker.yml`：自动化 CI/CD 工作流

## 使用方法

### 1. 构建 Docker 镜像

```bash
docker build -t postgresbson:latest .
```

### 2. 运行容器

```bash
docker run --rm -it postgresbson:latest
```

### 3. 使用扩展

可以在容器内的 PostgreSQL 使用 `CREATE EXTENSION pgbson;` 来启用该扩展。

## CI/CD

推送代码后，GitHub Actions 将自动：

1. 构建 postgresbson
2. 构建 Docker 镜像
3. 登录并推送到容器仓库

## 可自定义项

- 可在 `Dockerfile` 修改 PostgreSQL 版本
- 可在 workflow 文件自定义镜像标签和推送目标

---

本仓库仅用于自动化构建，源码版权归原项目所有。详情请见 [buzzm/postgresbson](https://github.com/buzzm/postgresbson)。
