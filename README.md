# claude-stall-guard

让 Claude Code 能**感知**到命令卡在交互式输入上，而不是干等到超时。

Claude Code 的 Bash 工具没有 TTY，命令一旦弹出交互提示（`(y/N)`、`Password:`、
向导问答……）就会无限阻塞，直到 2~10 分钟超时，而且 Claude 只能拿到一个含糊的
"超时"。本工具用 **PTY + 看门狗** 把"看不见的挂起"变成"几秒内返回的明确信号"。

## 工作原理

`bin/stall-guard` 在伪终端（PTY）下运行命令，并定义 **progress = 有新输出 或
进程组 CPU 时间在前进 或 进程组网络流量在动**：

| 情况 | 判定 | 默认等待 |
|------|------|----------|
| 无 progress，且最后一行长得像交互提示（`(y/N)`、`Password:`、`? xxx`、npm 默认值提示等） | 卡在等输入 | 10s（`--prompt-idle`） |
| 无 progress，无可识别提示 | 通用卡死 | 30s（`--idle`） |
| 安静但 CPU 在忙（编译、测试…） | 正常工作 | 永不杀 |
| 安静、CPU 也闲，但网络字节数在变（慢下载、等服务端长响应…） | 正常工作 | 永不杀 |

网络检测看的是进程组的**累计字节计数器是否变化**（macOS 用 `nettop -n`，无需
root，单次采样约 10ms；Linux 退化为 `/proc/<pid>/io` 的 `rchar/wchar`，即任何
I/O 前进都算 progress）。只持有空闲连接不算——卡在提示上的进程也常挂着 keepalive。
`nettop` 不可用时自动放弃网络检测，行为退回到只看输出 + CPU。

判定卡住后：SIGTERM→SIGKILL 整个进程组，打印带 `[stall-guard] ⛔ STALL DETECTED`
标记的报告（含最后输出 + 给 Claude 的下一步建议），**退出码 99**。
正常结束则透传子进程退出码与全部输出。

`hooks/pretooluse.py` 是 Claude Code 的 PreToolUse hook，通过
`hookSpecificOutput.updatedInput`（需 Claude Code ≥ 2.1.152）把每条 Bash 命令自动
改写成 `stall-guard -c '<原命令>'`。改写后的命令仍走正常权限确认，用户看到的是
改写后的真实命令。

hook 会**跳过**：后台任务（`run_in_background`）、含 `sudo` 的命令（GUI askpass
等用户点击时本来就安静）、已包装的命令、廉价只读命令（`ls`/`git status` 等）、
`STALL_GUARD_DISABLE=1` 时的一切。

## 单独使用

```bash
bin/stall-guard -c 'npm init'                 # ~10s 后报告卡在向导提示
bin/stall-guard --idle 60 -c './slow-build'   # 调大通用阈值
bin/stall-guard -- python3 setup.py install   # argv 形式
```

## 在本仓库内试验 hook（项目本地，不影响全局）

```bash
cd ~/Developments/claude-stall-guard
claude          # 首次会询问是否信任本项目的 settings/hooks，选信任
```

然后让 Claude 跑一条会卡的命令试试，比如：

> Run: bash tests/fake-installer.sh

预期：~10 秒后 Claude 收到 `[stall-guard] ⛔ STALL DETECTED`（exit 99），并主动
改用非交互方式（如 `yes | …`）或交还给你。

## 全局安装

试验满意后，装到全局让**所有项目**的 Claude Code 会话生效。一行安装（无需
clone，脚本会自己拉取仓库 tarball）：

```bash
curl -fsSL https://raw.githubusercontent.com/sunfmin/claude-stall-guard/main/install.sh | bash
```

或在 clone 好的仓库里：

```bash
bash install.sh             # 安装 / 更新（幂等）
bash install.sh --uninstall # 卸载（一行式加 `-s -- --uninstall`）
```

安装做三件事：

1. 拷贝 `bin/stall-guard` 与 `hooks/pretooluse.py` 到
   `~/.local/share/claude-stall-guard/`（hook 按自身相对路径找 guard，
   二者永远是配套版本）；
2. 软链 `~/.local/bin/stall-guard`，方便手动使用；
3. 把 PreToolUse 条目**合并**进 `~/.claude/settings.json`——只追加/刷新
   自己的条目，其他 hook 与配置一概不动；写入前自动备份为
   `settings.json.bak-<时间戳>`。

重复运行只刷新文件不重复加条目；卸载移除以上全部（settings 同样先备份）。
仅对新开的 Claude Code 会话生效，已开的会话需重启。更新本仓库后重跑
`bash install.sh` 即可升级。

## 配置（环境变量 / 命令前缀）

| 变量 | 默认 | 说明 |
|------|------|------|
| `STALL_GUARD_PROMPT_IDLE` | 10 | 识别出提示时的判定秒数 |
| `STALL_GUARD_IDLE` | 30 | 无提示时的通用判定秒数 |
| `STALL_GUARD_TERM` | dumb | 子进程 TERM（dumb 可减少 spinner/ANSI 干扰） |
| `STALL_GUARD_DISABLE` | - | `=1` 时 hook 不包装任何命令 |

在对话里也可以对单条命令临时调参——hook 会把 `STALL_GUARD_*` 前缀提升到
包装器上：`STALL_GUARD_IDLE=300 ./long-quiet-task.sh`。

## 测试

```bash
bash tests/run-tests.sh   # 22 个用例：检测、误杀防护、退出码透传、hook、安装器
```

## 已知限制

- 纯启发式：持续动画的 spinner 会被当作"有输出"；零输出、零 CPU、零流量的
  合法等待（如等定时器、等人工触发的外部事件）超过 `--idle` 仍会被误杀——用
  `STALL_GUARD_IDLE=300` 前缀放宽。反过来，后台有周期性心跳/遥测流量的进程
  即使真卡在提示上，也可能因流量被当作 progress 而延迟判定。
- 检测到卡住只能"杀掉并报告"，无法替你作答；自动应答请用 `yes |` / `expect`。
- 需要 `ps -o pgid=,pid=,time=`（macOS/BSD 自带；Linux procps 同样支持）。
  网络检测在 macOS 依赖 `nettop`（系统自带）；Linux 上以 `/proc/<pid>/io`
  近似（含磁盘 I/O）；都不可用时该项检测自动停用。
