上板实录：构建 / 签名 / 装机 / 内容 各阶段的坑（2026-11-15）

这一篇只记"实际踩到并已修掉"的问题，按出现顺序排列。工具链选型与下载源被墙/403 的坑
在 docs/TOOLCHAIN-NOTES.md 里，签名材料的一致性规则在 signing/README.md 里，这里不重复。

跑通时的环境（复现时先对一遍）
  工程目录   D:\ohos-kiosk（GitHub: Yuanyuan669/ohos-kiosk，2026-11-15 从临时目录迁入）
  IDE        D:\DevEcoStudio（26.0.1.290，只当编辑器和设备管理器用，不参与编译）
  编译目标   D:\ohos-tools\sdk\openharmony → 4.0-Release / API 10（ets + js + toolchains）
  hvigor     D:\ohos-tools\hvigor-3.2.4（不能用 IDE 自带的 6.26.x）
  JDK        D:\ohos-tools\java\jdk-17
  设备       硬开鸿 LHT16，实测 OpenHarmony-4.1.7.5 / API 11 / 厂商 "OHarm OS 2.0"
             设置里显示的 2.0.613 是厂商产品版本号，不是 OpenHarmony 版本

一、工具链（细节见 TOOLCHAIN-NOTES.md）
  1. winget install Huawei.DevEco 指向 3.1.0.501，CDN 直链 403，装不上。
  2. 官方 4.0 Release 文档里的 devecostudio 4.0.0.600 链接同样 403（已下架）。
     结论：IDE 不必回退，用 26.x + Settings 里装 OpenHarmony SDK 即可。
  3. hvigor 与 SDK 版本写法绑定：
       DevEco 26 自带 hvigor 6.26.x 认 "4.0.0(10)" 这种字符串；
       hvigor 3.2.4 只认裸数字 10。两种写法不能混。
     本工程固定裸数字 + hvigor 3.2.4。
  4. hvigor 找 SDK 的规则是 $OHOS_BASE_SDK_HOME/<apiVersion>/<component>，
     下载解包后目录叫 openharmony-4.0-Release，必须建一个名为 10 的 junction 指过去，
     否则报 "Unable to find the following components: toolchains:10"。
  5. @ohos/hvigor 在 registry.npmjs.org 和 ohpm.openharmony.cn 都是 404，
     只有 https://repo.harmonyos.com/npm/ 提供（3.0.2 / 3.0.9 / 3.2.4 以及 6.x）。
  6. C 盘的 Microsoft.OpenJDK.17 卸载返回 1603，至今还在；JAVA_HOME 已指向 D 盘，
     PATH 也优先 D 盘，不影响构建。要彻底清掉需要手动卸载。

二、构建（hvigor / ArkTS）
  1. build-profile.json5 的 products[] 里写 deviceConfig 报 schema 错，删掉即可。
  2. EntryAbility 里 windowStage.loadContent(path, callback) 的 AsyncCallback<void,void>
     签名不收 (err, data) 回调，改成 Promise 链：
       windowStage.loadContent('pages/Index').then(() => windowStage.getMainWindow())...
  3. 打包阶段 spawn java ENOENT：hvigor 起的是裸 java，JDK 必须在 PATH 里。
     env.sh 已按 JAVA_HOME 把 $JAVA_HOME/bin 前置到 PATH。
  4. ArkTS 的 arkts-limited-stdlib 禁用全局 parseInt / parseFloat。
     解析 wttr.in 的字符串数值时改成 Number()，编译通过。
  5. open-meteo 的 current_weather 里字段叫 weathercode，不是 weather_code。
     写成后者的后果是温度正常、天气文案恒为"未知"。现在两个名字都兜住。
  6. 默认备忘文案里写着 scripts/push-photos.ps1（不存在），已改成 push-photos.sh。

三、签名（完整规则见 signing/README.md）
  1. 直接拿 SDK 自带的 OpenHarmonyProfileRelease.pem 当 app 证书签名会报
     "SignatureException: Signature did not verify"——它是 profile 的签名链，不是应用证书。
     正确做法是用 generate-app-cert 以 SDK 里公开的测试 CA 签发自己的应用证书，
     那个 .pem 只用于 sign-profile。
  2. verify-app 必须给 -outCertChain / -outProfile，而且输出路径不能指向已存在的 .pem
     （会报 Not support file），用 .cer / .p7b。
  3. 只要下面三处有一处不一致，设备就报 9568322 / 9568313：
       profile 里的 bundle-name == 工程 bundleName
       profile 里的 distribution-certificate == appCertFile 的叶子证书
       appCertFile 的叶子证书公钥 == keystore 里 keyAlias 的公钥

四、装机 / 截图 / 推照片（Windows + Git Bash 特有，Linux runner 不受影响）
  1. Git Bash 会把命令行里的 /data/local/tmp/x.jpeg 改写成 C:/Program Files/Git/data/...，
     hdc file recv 因此找不到远端文件。处理：
       MSYS_NO_PATHCONV=1 hdc file recv /data/local/tmp/x.jpeg "$(cygpath -w 本地路径)"
     deploy.sh 的截图步骤已按这个写法改掉。
  2. 这版 hdc 的 file send 不是"发到目录下的同名文件"，而是按本地相对路径在远端建子目录：
       file send assets/photos/a.png $SANDBOX/   → $SANDBOX/assets/photos/a.png
     push-photos.sh 因此曾"成功"但应用扫不到。现在先 cd 到图片目录，只发 "./a.png"。
  3. 应用沙箱真实路径是 /data/app/el2/100/base/<bundle>/haps/<module>/files/photos，
     不是 .../base/<bundle>/files/photos（少了 haps/<module> 一段）。脚本改为探测
     haps/*/files/photos，找不到再按 entry 拼。
  4. hdc shell 是 root（uid=0），直写进去的文件属主是 root，应用（20010025）读不到。
     推完要把属主改成 files 目录的属主、权限 660；注意只 chmod 文件，别 chmod 目录
     （目录去掉 x 位后连应用自己也进不去）。
  5. 照片列表只在 onPageShow 重新扫描；推完照片要重启应用或进设置再返回，否则页面还是旧列表。
  6. 这块镜像没有 getparam / getprop，取系统属性用 param get <key>；
     也没有 curl / wget，netcat 指向的 toybox 不含该 applet，设备侧做不了 HTTP 探测。
  7. faultlog 里的 jscrash-com.minkiapps.ets.news、appfreeze-com.wathinst.ohbili
     是设备上别的应用留下的旧记录，与 HomeKiosk 无关。

五、网络与内容
  1. 天气卡显示"离线 / Timeout was reached"：不是应用 bug。
     2026-11-15 在本机和板子所在网络实测：
       能 ping 通 223.5.5.5 和 api.open-meteo.com；
       对 api.open-meteo.com 的 TCP 80/443 全部被 reset/超时；本机 curl 同样复现。
     处理：主源 open-meteo 6 秒超时后自动切 wttr.in（无需 key，实测可达），
     两源都失败才显示"离线"，并按 120 秒重试。
  2. 板子当前 Wi-Fi 是 192.168.31.177/24（DHCP，会变）。
     免线部署流程：插线跑 bash scripts/tcp-mode.sh，之后
       OHOS_TARGET=<板子IP>:5555 bash scripts/pipeline.sh
  3. 自定义信息源必须自己在设置页填 URL；本机联调用
       node tools/feed-mock.js 8788
     然后填 http://<本机局域网IP>:8788/feed。明文 http 若被镜像限制，换 https 或内网网关。

六、已经验证过的结论（别再重复怀疑）
  - API 10 的包在 API 11 设备上可安装、可启动，四个窗口 API 均返回 ok；
    截图 2408×1080 横屏，页脚显示 "API 11 · OpenHarmony-4.1.7.5"。
  - 未签名 HAP 1113957 B → 签名后 1118721 B，verify-app 通过。
  - doctor.sh 21 项全过；tools/validate-project.js 52 项全过。
  - 安装/卸载都是普通应用行为（hdc install -r / hdc uninstall），不动固件。

七、还没做 / 未验证
  - 免线部署（tcp-mode.sh + OHOS_TARGET）尚未实际执行。
  - CI 的 self-hosted runner 模板尚未真跑过（模板已写好，见 ci/）。
  - 5.0 / API 12 刷机未做，也不需要；将来要刷先备份。
  - C 盘那份 JDK 仍未卸载（winget 返回 1603）。