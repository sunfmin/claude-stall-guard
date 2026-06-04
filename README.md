# claude-stall-guard

让 Claude Code 能**感知**到命令真的卡死了——不是干等到超时，
并且在杀掉之前先取证：告诉 Claude 它到底阻塞在哪个系统调用上。

## 工作原理：先消解，再检测，最后取证

`bin/stall-guard` **不用 PTY**。它给子命令一套加固过的 stdio：
`stdin=/dev/null`、独立 session（无 controlling terminal）、stdout/stderr 走管道。
仅这一步就消解了绝大多数"等输入"——根本轮不到检测：

- 读 stdin 的提示立刻吃到 EOF，自行了断（`apt` 打印 `Abort.`，`read` 直接返回）；
- 读 `/dev/tty` 的（密码类提示）因为没有控制终端，秒级报错退出；
- pager / 交互向导根本不会启动（`isatty()` 为假）。

剩下的才是真挂死——死等网络对端、读一个永远没数据的 fd、死锁。看门狗定义
**progress = 有新输出 或 进程组 CPU 时间在前进 或 进程组网络流量在动**：

| 情况 | 判定 | 默认等待 |
|------|------|----------|
| 无 progress | 卡死 | 30s（`--idle`） |
| 安静但 CPU 在忙（编译、测试…） | 正常工作 | 永不杀 |
| 安静、CPU 也闲，但网络字节数在变（慢下载、等服务端长响应…） | 正常工作 | 永不杀 |

网络检测看的是进程组的**累计字节计数器是否变化**（macOS 用 `nettop -n`，无需
root，单次采样约 10ms；Linux 退化为 `/proc/<pid>/io` 的 `rchar/wchar`，即任何
I/O 前进都算 progress）。只持有空闲连接不算——卡在提示上的进程也常挂着 keepalive。
`nettop` 不可用时自动放弃网络检测，行为退回到只看输出 + CPU。

判定卡住后，先**探测阻塞点**再杀：逐个询问操作系统进程组里每个进程阻塞在哪个
系统调用上——Linux 读 `/proc/<pid>/wchan` + `/proc/<pid>/syscall`（read 类调用
还会 readlink 出具体 fd 指向什么）；macOS 用 `sample` 取内核栈帧（对自己的子进
程免 root，被拒时退化为 ps 进程状态）。然后 SIGTERM→SIGKILL 整个进程组，打印一
份简短报告（最后输出 + blocked-at 证据），**退出码 99**。怎么处置交给 Claude
自己判断。正常结束则透传子进程退出码与全部输出。

```
[stall-guard] ⛔ STALL DETECTED — no output, CPU or network progress for 30s.
[stall-guard] last output:
[stall-guard]   │ Ok to proceed? (y/N)
[stall-guard] blocked at:
[stall-guard]   │ pid 46005 bash — blocked in read [read]
[stall-guard]   │ pid 46006 bash — waiting for a child process [__wait4]
[stall-guard]   │ pid 46007 sleep — sleeping on a timer [__semwait_signal]
[stall-guard] process group killed; exit 99.
```

`hooks/pretooluse.py` 是 Claude Code 的 PreToolUse hook，通过
`hookSpecificOutput.updatedInput`（需 Claude Code ≥ 2.1.152）把每条 Bash 命令自动
改写成 `stall-guard -c '<原命令>'`。改写后的命令仍走正常权限确认，用户看到的是
改写后的真实命令。

hook 会**跳过**：后台任务（`run_in_background`）、含 `sudo` 的命令（GUI askpass
等用户点击时本来就安静）、已包装的命令、廉价只读命令（`ls`/`git status` 等）、
`STALL_GUARD_DISABLE=1` 时的一切。

## 单独使用

```bash
bin/stall-guard -c 'bash tests/blocked-prompt.sh'  # ~30s 后报告 + 阻塞点证据
bin/stall-guard --idle 60 -c './slow-build'        # 调大阈值
bin/stall-guard -- python3 setup.py install        # argv 形式
```

对比：`bin/stall-guard -c 'bash tests/fake-installer.sh'`（普通的读 stdin 提示）
会因 EOF **直接跑完**，根本不触发检测——这正是设计的第一层。

## 在本仓库内试验 hook（项目本地，不影响全局）

```bash
cd ~/Developments/claude-stall-guard
claude          # 首次会询问是否信任本项目的 settings/hooks，选信任
```

然后让 Claude 跑一条会卡的命令试试，比如：

> Run: bash tests/blocked-prompt.sh

预期：~30 秒（默认 `--idle`）后 Claude 收到 `[stall-guard] ⛔ STALL DETECTED`
（exit 99）和 blocked-at 证据，并主动改用非交互方式（如 `yes | …`）或交还给你。

## 全局安装

### Homebrew（推荐）

```bash
brew install sunfmin/tap/claude-stall-guard
stall-guard-hook enable     # 把 hook 合并进 ~/.claude/settings.json
```

停用 / 卸载：

```bash
stall-guard-hook disable    # 只摘掉 settings.json 里自己的条目
brew uninstall claude-stall-guard
```

`stall-guard-hook enable|disable|status` 只增删**自己的**那一条 PreToolUse
条目，其他 hook 与配置一概不动；任何写入前自动备份
`settings.json.bak-<时间戳>`。条目指向随包安装的 `pretooluse.py`
（Cellar 路径会重写成稳定的 `opt/` 路径，`brew upgrade` 后不失效）。
仅对新开的 Claude Code 会话生效，已开的会话需重启。

### 脚本安装（不用 Homebrew）

一行安装（无需 clone，脚本会自己拉取仓库 tarball）：

```bash
curl -fsSL https://raw.githubusercontent.com/sunfmin/claude-stall-guard/main/install.sh | bash
```

或在 clone 好的仓库里：

```bash
bash install.sh             # 安装 / 更新（幂等）
bash install.sh --uninstall # 卸载（一行式加 `-s -- --uninstall`）
```

装到 `~/.local/share/claude-stall-guard/`，软链
`~/.local/bin/{stall-guard,stall-guard-hook}`，并自动执行
`stall-guard-hook enable`。卸载移除以上全部（settings 同样先备份）。
两种安装方式择一即可。

## 配置（环境变量 / 命令前缀）

| 变量 | 默认 | 说明 |
|------|------|------|
| `STALL_GUARD_IDLE` | 30 | 无 progress 多少秒判定卡死 |
| `STALL_GUARD_TERM` | dumb | 子进程 TERM（dumb 可减少 spinner/ANSI 干扰） |
| `STALL_GUARD_DISABLE` | - | `=1` 时 hook 不包装任何命令 |

在对话里也可以对单条命令临时调参——hook 会把 `STALL_GUARD_*` 前缀提升到
包装器上：`STALL_GUARD_IDLE=300 ./long-quiet-task.sh`。

## 测试

```bash
bash tests/run-tests.sh   # 27 个用例：EOF 自消解、检测、取证、误杀防护、退出码透传、hook、安装器
```

## 已知限制

- 管道下 C stdio 程序会全缓冲 stdout，报告里的"last output"可能缺少未刷新的
  文本（stderr 永远不缓冲，不受影响）；blocked-at 探测给出的是系统调用层面的
  事实，不依赖文本。
- 启发式边界：持续动画的 spinner 会被当作"有输出"；零输出、零 CPU、零流量的
  合法等待（如等定时器、等人工触发的外部事件）超过 `--idle` 仍会被误杀——用
  `STALL_GUARD_IDLE=300` 前缀放宽。反过来，后台有周期性心跳/遥测流量的进程
  即使真卡在提示上，也可能因流量被当作 progress 而延迟判定。
- 检测到卡住只能"杀掉并报告"，无法替你作答；自动应答请用 `yes |` / `expect`。
- 需要 `ps -o pgid=,pid=,time=`（macOS/BSD 自带；Linux procps 同样支持）。
  网络检测在 macOS 依赖 `nettop`，阻塞点探测依赖 `sample`（均系统自带）；
  Linux 网络检测以 `/proc/<pid>/io` 近似（含磁盘 I/O）、探测读 `/proc`；
  不可用时对应功能自动停用，其余照常。
