# Thunderbird Windows 构建记录

## 先说结论

这份文档记录的是一次在 2026-05-10 成功跑通的 Windows 11 Thunderbird 编译过程。目的很简单：下次重建环境的时候，少踩点坑，少走点弯路。

最关键的一点先记住：这个仓库只有 Thunderbird 的 `comm` 源码，不是完整的可直接编译根目录。只在当前目录下是编不过去的。真正跑通的方式是：另外准备一份同级的 Gecko 源码根目录 `C:\AI\thunderbird\mozilla-unified`，把当前仓库挂进去当 `comm` 用，再把 Gecko 对齐到兼容的 Mercurial changeset，重新生成 Rust vendor，最后从 Gecko 根目录去编译和打包 Thunderbird。

最后成功产出的文件是：

- `C:\AI\thunderbird\mozilla-unified\obj-thunderbird\dist\bin\thunderbird.exe`
- `C:\AI\thunderbird\mozilla-unified\obj-thunderbird\dist\thunderbird-150.0a1.en-US.win64.zip`

编出来的应用信息是：

- `Name=Thunderbird`
- `Version=150.0a1`

## 具体信息

### 仓库和版本

- Thunderbird `comm` 仓库路径：`C:\AI\thunderbird\thunderbird-desktop`
- Thunderbird 分支：`main`
- Thunderbird commit：`762ee446617ca2b80655476bf1c6e56d4c0faa9d`
- Thunderbird commit 时间：`2026-02-25 10:58:40 +0000`
- Gecko 根目录：`C:\AI\thunderbird\mozilla-unified`
- Gecko 仓库类型：Mercurial
- 实际可用的 Gecko changeset：`f2f75ecf8eb443871319273e7e39fb7f01b2581e`
- Gecko 分支：`default`
- Gecko changeset 时间：`2026-02-25 10:49 +0000`
- `mozilla-unified` 里的 `comm` 是一个 Windows junction，指向 `C:\AI\thunderbird\thunderbird-desktop`

### 当时能跑通的构建配置

文件：`C:\AI\thunderbird\mozilla-unified\mozconfig`

```sh
ac_add_options --enable-project=comm/mail
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird
```

这两行的作用很关键：

- 强制 `mach` 编译 Thunderbird，而不是 Firefox
- 把 Thunderbird 的产物单独放进 `obj-thunderbird`，避免之前 Firefox 的老产物串进来搞事情

### 工具和环境

- 操作系统：Windows 11
- MozillaBuild 安装路径：`C:\mozilla-build`
- 机器上已经装好了带原生桌面工具链的 Visual Studio
- 构建命令必须在 MozillaBuild 里跑，别直接在 PowerShell 里硬跑

这里有个很容易让人误判的点：普通 PowerShell 会看起来像是少了 `hg`、`cl.exe`，或者 `MOZILLABUILD` 没设。这在 MozillaBuild 外面是正常现象，不代表环境一定坏了。

## 实际可用的构建流程

### 1. 从 Gecko 根目录开始，不要直接从这个仓库根目录开始

这个仓库本身没有顶层 `mach`，所以不要直接在 `C:\AI\thunderbird\thunderbird-desktop` 下面编。

正确做法是进 MozillaBuild，并且把工作目录指到 Gecko 根目录：

```powershell
$env:USE_MINTTY='0'
& 'C:\mozilla-build\start-shell.bat' -where 'C:\AI\thunderbird\mozilla-unified'
```

### 2. 如果要 bootstrap，记得用没有空格的 application alias

下面这个写法是能用的：

```sh
./mach --no-interactive bootstrap --application-choice browser
```

下面这个通过 PowerShell 再转进 `start-shell.bat` 时会因为引号问题翻车：

```sh
./mach --no-interactive bootstrap --application-choice "Firefox for Desktop"
```

### 3. 确认 `comm` 挂载方式和根目录 `mozconfig` 都对

当时能用的目录结构是：

- `C:\AI\thunderbird\mozilla-unified`
- `C:\AI\thunderbird\mozilla-unified\comm` -> junction 到 `C:\AI\thunderbird\thunderbird-desktop`

还有一点别漏掉：`mozconfig` 必须放在 `mozilla-unified` 根目录，不是只放在 `comm` 里就行。

### 4. 把 Gecko 对齐到兼容版本

这次用的 Thunderbird GitHub `main` 快照，直接去配 2026-05 的 Gecko 新 tip 是编不过的。最后可行的办法就是把 Gecko 切回 2026 年 2 月那个和 Thunderbird 快照更接近的 changeset：

```sh
hg update -C f2f75ecf8eb443871319273e7e39fb7f01b2581e
```

### 5. 重新同步 Rust vendor tree

Gecko 对齐完以后，要重新生成 Thunderbird 的 Rust vendor tree：

```sh
./mach tb-rust vendor
```

### 6. 做一次干净的 Thunderbird 构建

```sh
./mach clobber
./mach build
```

### 7. 打出可分发的 ZIP 包

```sh
./mach package
```

## 这次碰到的问题，以及最后怎么解的

### 1. 一开始想直接在 `thunderbird-desktop` 里编

现象：

- 没有顶层 `mach`
- 没有根目录 `mozconfig`
- 在这个仓库根目录执行 build 命令，本身就是不成立的

解决：

- 准备一个 Gecko 根目录：`C:\AI\thunderbird\mozilla-unified`
- 把当前仓库挂进去，作为 `comm`
- 所有 `mach` 命令都在 Gecko 根目录执行

### 2. 普通 PowerShell 里看起来像是 MozillaBuild 工具没装好

现象：

- 找不到 `hg`
- 找不到 `cl.exe`
- `MOZILLABUILD` 没有设置

解决：

- 构建命令统一走 `C:\mozilla-build\start-shell.bat`
- 在普通 PowerShell 里看不到 `hg` 或 `cl.exe`，先别急着判死刑，这本来就可能是正常的

### 3. `start-shell.bat` 配合 `"Firefox for Desktop"` 会失败

现象：

- `The syntax of the command is incorrect.`

原因：

- 命令经过 `cmd.exe` 和 MSYS 两层之后，引号嵌套把命令行搞坏了

解决：

- 用 `--application-choice browser`，不要用那个带空格的名字

### 4. 产物编出来成了 Firefox，不是 Thunderbird

现象：

- 旧的 object directory 数据还指着 Firefox
- 老的构建输出里显示的是 `firefox`

解决：

- 在 `mozilla-unified` 根目录创建 `mozconfig`
- 设置 `ac_add_options --enable-project=comm/mail`
- 用单独的对象目录：`mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird`

### 5. 旧 object directory 污染，清理起来很麻烦

现象：

- 之前 Firefox 的对象目录里有遗留文件
- 还有被锁住的构建产物

解决：

- 别再硬复用旧对象目录了
- 直接换一个干净的 Thunderbird 专用目录：`obj-thunderbird`

### 6. Cargo frozen 或 offline 相关依赖报错

现象：

- 构建过程中缺 Rust 依赖

恢复时用过的办法：

```sh
cargo fetch --locked --manifest-path Cargo.toml
```

这个命令会先把依赖拉下来，在 Rust vendor tree 还没重新同步前，能帮忙把前面的 Cargo 错误先顶过去。

### 7. Rust vendor tree 没同步

现象：

- 构建过程提示需要执行 `mach tb-rust vendor`
- `comm/third_party/rust` 下面的 crate 状态跟当前 lock 文件对不上

解决：

```sh
./mach tb-rust vendor
```

### 8. Gecko tip 对这个 Thunderbird 快照来说太新了

现象：

- Thunderbird 代码里很多地方同时编译失败
- 典型例子包括 `WordBreaker`、`EncodingDetector`、`Collator`、`NodeList`、`nsIFilePicker` 一类 API 对不上

原因：

- 2026-02-25 的 `comm` Git 快照，拿去配 2026-05-09 的 Gecko tip 编了

解决：

- 把 Gecko 回退到 `f2f75ecf8eb443871319273e7e39fb7f01b2581e`
- 重新执行 `./mach tb-rust vendor`
- 再跑一遍 `./mach clobber` 和 `./mach build`

这个地方就是整次构建的转折点。回到这个版本之后，第一次完整编译成功。

### 9. `./mach installer` 没产出想要的 Windows 安装包

现象：

- 这个命令在当前平台上走到了一个不支持的 `make install` 路径

解决：

- 直接用 `./mach package`，成功拿到可分发的 ZIP 产物

### 10. `./mach build installers-en-US` 失败

现象：

- 本地化安装包流程在 artifact 相关代码里失败了
- 这个流程默认认为 `comm` 应该是一个 Hg 仓库

原因：

- 当前工作区里的 `comm` 来自 GitHub，是 Git checkout，不是 Hg 版 `comm-central`

解决：

- 先接受 ZIP 包是当前环境下可用的分发产物
- 以后如果真的要完整的 Windows 本地化安装包，再考虑切换到 Hg 版 `comm` checkout，或者单独调整 release packaging 流程

## 这次最大的经验

- 最重要的不是先敲什么命令，而是先选对构建根目录。只有 `comm` 本身是不够的。
- 根目录 `mozconfig` 配对了，再加上一个干净的 Thunderbird 专用对象目录，能少掉一大堆混乱。
- 对这台机器来说，基于 Mercurial 的 Gecko 环境，比之前试过的 Git bootstrap 更稳。
- MozillaBuild 要一直用到底。普通 PowerShell 更适合拿来查看状态，不适合作为主构建环境。
- 如果突然有一大批 Thunderbird 源码同时因为 Gecko API 变化而报错，先怀疑版本没对齐，不要第一反应就是手改源码。
- Gecko 版本切换以后，记得先重新跑 Rust vendor，再重新编译。
- 不要拿一个正在长时间 bootstrap 或 build 的 shell 去顺手做别的检查，容易把自己绕进去。
- 如果完整 installer 流程走不通，`./mach package` 也足够先拿到一个能本地使用的 Windows 构建产物。

## 下次重建时推荐照着走的检查清单

下次如果要重建，建议按这个顺序确认：

1. 先确认 `mozilla-unified` 存在，而且 `comm` 是一个指向当前仓库的 junction。
2. 确认 `mozilla-unified\mozconfig` 里有 `--enable-project=comm/mail` 和 `MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird`。
3. 用 `USE_MINTTY=0` 进入 MozillaBuild。
4. 如果要刷新环境，执行 `./mach --no-interactive bootstrap --application-choice browser`。
5. 除非 Thunderbird checkout 故意换到了更新且确认兼容的版本，否则先把 Gecko 切到 `f2f75ecf8eb443871319273e7e39fb7f01b2581e`。
6. 执行 `./mach tb-rust vendor`。
7. 执行 `./mach clobber`。
8. 执行 `./mach build`。
9. 执行 `./mach package`。
10. 最后确认 `obj-thunderbird\dist\bin\thunderbird.exe` 和 `obj-thunderbird\dist` 下面的 ZIP 包都出来了。

## 自动化脚本

项目里已经放了一个可复用的 PowerShell 脚本：`C:\AI\thunderbird\thunderbird-desktop\rebuild-thunderbird.ps1`

默认用法：

```powershell
Set-Location C:\AI\thunderbird\thunderbird-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-thunderbird.ps1
```

Dry run 用法：

```powershell
Set-Location C:\AI\thunderbird\thunderbird-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-thunderbird.ps1 -DryRun
```

这个脚本会做这些事：

- 检查 Gecko 根目录和 MozillaBuild 路径
- 确保 `comm` junction 指向当前仓库
- 确保 `mozilla-unified\mozconfig` 跟 Thunderbird 配置一致
- 如果需要，可选执行可用的 `browser` bootstrap
- 把 Gecko 更新到这次验证过的可用 changeset
- 重新跑 Rust vendor
- 执行 clobber、build 和 package

比较有用的可选参数：

- `-SkipBootstrap`
- `-SkipGeckoUpdate`
- `-SkipVendor`
- `-SkipClobber`
- `-SkipPackage`

## 复用说明

如果当前仓库一直停在 Thunderbird commit `762ee446617ca2b80655476bf1c6e56d4c0faa9d`，那最稳妥的默认做法就是继续沿用这份文档里的 Gecko 版本和 `mozconfig`。

如果后面 Thunderbird 更新到了新的 commit，那就别默认认为 Gecko tip 一定还能直接用。先重新确认一下 Gecko 版本对齐情况，再开始编译。