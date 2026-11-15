HomeKiosk — 把开发者手机变成家庭信息屏，并把构建到装机做成一条能在 CI 上复跑的链路

目标设备：硬开鸿 开发者手机形态开发板（展锐 P7885 5G，8+128G，6.58" FHD）。

2026-11-15 在实机上读到的版本（`param get const.ohos.fullname` 等）：
  OpenHarmony 4.1.7.5 / API 11 / 型号 LHT16 / 厂商口径 "OHarm OS 2.0"（设置里显示的 2.0.613 是厂商产品版本号，
  不是 OpenHarmony 版本）。出厂文档写的是 4.0，实际到手的镜像比文档新一个 API 档。
本工程 compileSdkVersion / compatibleSdkVersion 仍写 10：API 10 产物在 API 11 设备上向下兼容，
实测可以安装并运行；装上之后截图里的页脚会显示真实的 `API 11 · OpenHarmony-4.1.7.5`。

这个工程是什么
  ArkTS / Stage 模型应用，零三方依赖（不用 ohpm 拉外网包，CI 冷启动也能构建）。
  页面一：大字时钟 + 日期星期 + 天气卡 + 照片轮播 + 自定义信息源卡 + 备忘。
  页面二：设置（城市/经纬度、刷新间隔、信息源 URL、常亮、强制横屏、备忘）。
  天气用 Open-Meteo，不需要 API key；拿不到就降级显示"离线"并 2 分钟重试，不会白屏。
  "自定义信息源"是留给后续盯盘的口子：任何返回 {"title":"","lines":[]} 的 JSON 接口
  都能直接显示，不改代码。本地想验证就用 tools/feed-mock.js。

本机链路现状（2026-11-14 已验证，全部装在 D 盘，C 盘没落东西）
  DevEco Studio 26.0.1.290   D:\DevEcoStudio（自带的 node v24.14.1 / ohpm / hvigor 也在里面）
  OpenHarmony SDK 4.0 API 10 D:\ohos-tools\sdk\openharmony（4.0.10.13；ets + js + toolchains）
                             D:\ohos-tools\sdk\10 是指向同一份的版本号目录，hvigor 按号找组件
  JDK 17                     D:\ohos-tools\java\jdk-17（用户级 JAVA_HOME / PATH 已指向它）
  hvigor 3.2.4 + 插件 3.2.4  D:\ohos-tools\hvigor-3.2.4（npm 源只能用 https://repo.harmonyos.com/npm/，
                             registry.npmjs.org 和 ohpm.openharmony.cn 都返回 404）
  hdc                        D:\ohos-tools\sdk\openharmony\toolchains\hdc.exe  Ver 1.3.0a
                             D:\DevEcoStudio\...\toolchains\hdc.exe  Ver 3.2.0f（备用，两个都能试）
  已跑通：doctor 19/20，build -> sign -> verify-app 全绿，产物
  build-artifacts\entry-signed.hap（1.1MB）。唯一没过的就是板子还没插。

还剩两件没验证的，别当成既成事实
  1. 板子的镜像认不认这套签名。SDK 里公开的 OpenHarmony.p12 带着 Root CA 和 Application CA
     的私钥，所以本工程的应用证书是由官方测试 CA 正式签发的（不是自签孤儿证书），Profile 里
     bundle-name 已对齐、有效期到 2033。标准系统开发镜像普遍信任这套根，但厂商改过根就要换材料，
     第一次装机就是这道门，见第 3 步。
  2. setWindowKeepScreenOn / setPreferredOrientation / setWindowSystemBarEnable 在这个镜像上
     各自是否可用。代码里每个都单独包了 try/catch 并打日志，跑不通只会少个效果，不会崩。

按步骤来（每步失败就停下，别往下走）

第 1 步 确认板子能被识别
  板子上：设置 -> 关于本机 -> 连续点版本号，开开发者模式；开发者选项里打开 USB 调试。
  电脑上（Git Bash）：
      bash scripts/doctor.sh        # 第 6 节会报设备在不在线
  或直接：
      /d/ohos-tools/sdk/openharmony/toolchains/hdc.exe list targets
  空列表：先换数据线（很多线只能充电），再看设备管理器有没有带感叹号的设备——
  驱动在 SDK 的 toolchains/usb_driver 目录，右键手动指定安装。
  再不行就换一份 hdc：export HDC='D:\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe'
  判据：输出一行设备序列号。

第 2 步 生成签名材料（一次性，约 5 秒）
      bash scripts/make-signing-material.sh
  它用 SDK 自带的 OpenHarmony 测试 PKI 走完整链条：生成应用密钥对 -> 让 Application CA
  签发应用证书（10 年）-> 写 bundle-name=com.local.homekiosk 的 Profile -> 签成 .p7b。
  判据：末尾打印三件套 homekiosk.p12 / homekiosk-app.cer / homekiosk-profile.p7b。

第 3 步 第一次装机（关键验证点）
      bash scripts/pipeline.sh
  判据：deploy.sh 末尾 pidof 拿到进程号，并且 build-artifacts/device.jpeg 里能看到界面。
  如果报 9568322 / 9568313：这台镜像不认社区测试根。两条退路——
    A. DevEco Studio 打开本工程 -> Project Structure -> Signing Configs -> Automatically
       generate signature -> 选中板子 -> Run。跑通后把 IDE 生成的 .p12/.cer/.p7b
       （在 C:\Users\你\.ohos\config）复制到 signing/，后面继续用命令行签。
    B. 找厂商要开发板调试签名包。
  如果报 [Fail]Connect / api version：分别按第 1 步换 hdc、或核对设备 API 后改 build-profile.json5。

第 4 步 免线部署（让板子从桌面消失，也是上 CI 的前提）
  板子插着线时跑一次：
      bash scripts/tcp-mode.sh
  它把设备切到 TCP 监听、读出 IP，并打印后续要用的 OHOS_TARGET 值。之后拔掉线，任何能路由
  到那个 IP 的机器都可以：
      export OHOS_TARGET=192.168.1.23:5555
      bash scripts/pipeline.sh
  判据：tcp-mode.sh 里 tconn 返回 Connect OK。
  注意 DHCP 会换 IP；给板子绑定静态地址，或在 CI 里把 OHOS_TARGET 做成可改变量。

第 5 步 内容
  照片：丢进 assets/photos/ 后 bash scripts/push-photos.sh（工程自带的 sample-*.png 是两张示例，
       换成自己的照片再跑一次即可）。脚本直接写 <bundle>/haps/entry/files/photos 并修属主；
       写完重启一次应用（或进设置再返回）就会轮播。
  信息源：设置页填 URL。本机自测：node tools/feed-mock.js 8788，然后填 http://<本机IP>:8788/feed。
       注意明文 http 在部分镜像上受限，不通就先换 https 或直接把板子指到你的内网网关。
  天气：设置页改经纬度（默认北京 39.9042/116.4074）。主源 open-meteo 失败会自动切 wttr.in，
       两源都不可达才显示"离线"（实测本网络墙 open-meteo，备用源可用）。

放到 CI
  GitHub Actions 自建 runner 模板：ci/github-actions.self-hosted.yml（runner 打标签 ohos-board）
  GitLab CI 模板：ci/gitlab-ci.self-hosted.yml（runner tag 同名）
  要点：
    - runner 必须能到达设备（USB 直连，或同网段的 OHOS_TARGET）。设备不在 CI 够得着的地方，
      流水线只能做到"构建+签名出产物"，装机那段必然红。
    - CI 首次准备 = 三条命令：get-ohos-sdk.sh、install-hvigor.sh、make-signing-material.sh；
      或把本机 signing/ 三件套压成 base64 放 secrets 解出来，二者等价。
    - 签名材料进 secrets（zip + base64），密码单独三个变量，别写进 env.sh。
    - 每次改 bundleName 都要重新签 Profile（Profile 里钉死了包名）——重跑第 2 步就行。
    - concurrency 锁了，避免两次流水线抢同一块板子。

版本与工具链怎么选（为什么不用 DevEco 26 自带的 hvigor）
  DevEco 26 仍然带 OpenHarmony SDK 目录、hdc、hap-sign-tool，所以它并没有放弃开源鸿蒙；
  它只是把默认 SDK 换成了 HarmonyOS 26.0.1（apiVersion 26）。真正的风险点有两个，都已核实：
    - 它不再附带 API 10 的编译目标，但官方镜像能直接下到 4.0-Release SDK（本工程走的就是这条）；
    - IDE 自带的 hvigor 6.26.x 认 "4.0.0(10)" 这类字符串版本号，而 hvigor 3.2.4 认裸数字 10，
      两种写法不能混。所以工程保持裸数字 + hvigor 3.2.4，和出厂镜像同代，兼容性最稳。
  想换成 IDE 那条路（在 DevEco 里直接 Run）也可以，但要先用 scripts/set-api.sh 把版本号
  改成字符串形式，再跑 scripts/align-toolchain.sh 借 IDE 的 hvigorw。

刷机以后（想让 API 12 / OpenHarmony 5.0 尝鲜版跑起来）
  这个平台官方已放出 5.0.0 镜像。刷完只需两处：bash scripts/set-api.sh 12 改工程版本号，
  再 bash scripts/get-ohos-sdk.sh 5.0.0-Release 装对应 SDK。
  刷机有变砖风险且厂商镜像要单独取，不在本项目范围里，跑不通的当前信息屏并不需要它。

故障码速查
  9568322 / 9568313  签名或 Profile 与设备/包名不匹配 -> 第 3 步的 A/B 两条退路
  9568289            签名材料不成套 -> 重跑 make-signing-material.sh
  9568320 no signature file  把未签名包拿去装了 -> 跑 sign.sh
  InstallFailed ... api version  应用要求 API 高于设备 -> 降 compatibleSdkVersion 或刷镜像
  [Fail]Connect / [Empty]        设备掉线、IP 变了，或 hdc 与 hdcd 版本不对付 -> 换另一份 hdc 再试
  装上了但启动白屏              bash scripts/deploy.sh 末尾的 hilog 段落里找 HomeKiosk tag 的 warn
  天气一直"离线 / Timeout"     先在电脑上 curl 'https://api.open-meteo.com/v1/forecast?...' 验证出口。
                                2026-11-15 本机网络实测：ICMP 通、TCP 80/443 都被 reset，属于网络出口拦截，
                                应用只是按设计降级（2 分钟重试），换网络或代理后自动恢复
  hvigor 'Unable to find ... toolchains:10'  SDK 版本号目录没建：New-Item -ItemType Junction
  hvigor 'spawn java ENOENT'      JDK 不在 PATH，env.sh 会按 JAVA_HOME 补；CI 上显式 export

目录
  AppScope/                 应用级配置与图标
  entry/                    模块与全部 ArkTS 代码（pages / service / common / model）
  scripts/                  env.sh common.sh doctor build sign deploy pipeline tcp-mode
                            get-ohos-sdk install-hvigor make-signing-material
                            push-photos align-toolchain set-api ci-summary + ohos.ps1 / set-jdk.ps1
  ci/                       GitHub Actions 与 GitLab CI 模板
  signing/                  生成出来的签名材料，已被 .gitignore 排除，只留 README
  docs/TOOLCHAIN-NOTES.md   工具链选型记录与被排除的下载源（避免再踩 403 的坑）
  docs/PITFALLS.md          上板实录：构建/签名/装机/推照片/网络各阶段踩过的坑与修法
  docs/DEVICE.md            设备档案：实测版本/硬件/调试状态/常用命令/刷机与备份原则
  assets/photos/            照片投递暂存目录
  tools/feed-mock.js        本地假信息源，验证链路用
  tools/validate-project.js 工程静态自检（JSON/资源/路由/引用一致性）
