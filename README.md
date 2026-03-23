# MySQL XtraBackup Quick Restore

这个目录提供“一键恢复并拉起可访问 MySQL”的流程，适配你的 `*_full` + `*_inc` 备份结构。

## 快速开始

1. 进入目录：

```bash
cd /Volumes/M4_Ext_SSD/Projects/nothing/ops/mysql-restore
```

2. 执行恢复并启动 MySQL：

```bash
./run-restore.sh --backup-dir /你的备份目录
```

默认会恢复“最新全量备份 + 同周期增量备份”，并把 MySQL 暴露到 `3307`。

## 连接数据库

```bash
mysql -h 127.0.0.1 -P 3307 -u root -p
```

默认 root 密码来自 `MYSQL_ROOT_PASSWORD`，未设置时为 `my_password`。

## 常用参数

指定某个全量备份时间点恢复（例如 `20250622_190001_full`）：

```bash
./run-restore.sh --backup-dir /你的备份目录 --full 20250622_190001
```

强制覆盖已有恢复数据（重刷 volume）：

```bash
./run-restore.sh --backup-dir /你的备份目录 --force
```

自定义映射端口：

```bash
./run-restore.sh --backup-dir /你的备份目录 --port 3310
```

## 停止容器

```bash
docker compose -f /Volumes/M4_Ext_SSD/Projects/nothing/ops/mysql-restore/docker-compose.restore.yml down
```
