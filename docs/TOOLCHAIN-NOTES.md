工具链选型实录（2026-11-14 在本机实测并验证到底）

这一篇只记录一件事：给这块 OpenHarmony 4.0（API 10）开发板手机挑一套装得下来、又能装得进板子的工具链。
网上多数教程指向的包已经下架，照抄会卡在半路；本篇把"哪些路已经实测走不通"和"最终走通的那条"分开写。

最终走通的组合（本机就是这套，build -> sign -> verify-app 全绿）
  IDE        DevEco Studio 26.0.1.290  D:\DevEcoStudio
             仍然带 sdk\default\openharmony\{ets,js,native,previewer,toolchains}，
             也就是开源鸿蒙支持并没有被砍掉；只是它自带的这份是 apiVersion 26（HarmonyOS 26.0.1 Beta1），
             不含 API 10 编译目标。
  编译 SDK   OpenHarmony 4.0-Release SDK（apiVersion 10，组件版本 4.0.10.13）
             D:\ohos-tools\sdk\openharmony-4.0-Release\{ets,js,toolchains}
             下载源：https://repo.huaweicloud.com/openharmony/os/4.0-Release/ohos-sdk-windows_linux-public.tar.gz
                     2141445383 字节，SHA256 80a92d54f81b163c903d6bfb95d3cad8a1854efa6dbe02802a9ca87aebc3ad50（已校验）
             native / previewer 两个组件没解：应用是纯 ArkTS，没有 C++ 也不需要 IDE 预览器。
  hvigor     3.2.4 + @ohos/hvigor-ohos-plugin 3.2.4，装在 D:\ohos-tools\hvigor-3.2.4
             唯一可用公共源 https://repo.harmonyos.com/npm/ （registry.npmjs.org 与
             https://ohpm.openharmony.cn/ohpm/ 对 @ohos/hvigor 一律 404）。
             3.2.4 正是 DevEco 4.0 那代的产品，认 build-profile.json5 里裸数字 compileSdkVersion: 10；
             IDE 26 自带的 hvigor 6.26.x 认 "4.0.0(10)" 字符串形式。两种写法不能混，所以工程保持裸数字。
             node v24.14.1（DevEco 自带）跑 hvigor 3.2.4 实测无兼容问题。
  JDK        17.0.21（D:\ohos-tools\java\jdk-17）。签名工具与 hvigor 的 PackageHap 都要 java，
             且 hvigor 是裸 spawn "java"，所以 JDK 的 bin 必须在 PATH 上（env.sh 按 JAVA_HOME 自动补）。
  设备连接   D:\ohos-tools\sdk\openharmony\toolchains\hdc.exe  Ver 1.3.0a  <- 与 4.0 镜像同代
             D:\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe  Ver 3.2.0f  <- 与 IDE 同代
             两份都在机器上，doctor.sh 会同时报版本；哪份能列出设备就用哪份（export HDC=...）。
  目录约定   hvigor 找 SDK 的方式是 $OHOS_BASE_SDK_HOME/<API 号>/<组件>，所以要有一个名为 10 的目录；
             本机用 D:\ohos-tools\sdk\10 指向同一份 SDK 的 junction 满足它，不占额外空间。

关于"新版 DevEco 不认老开发板"这条担心，分开说
  1) IDE 产品支持层面：不成立。26.0.1.290 的安装目录里明确有 openharmony SDK 分支、有 hap-sign-tool.jar、
     有 modulecheck/rescheck 这些开源鸿蒙专用工具，Settings 里的 OpenHarmony SDK 页签也还在。
  2) 真正的风险在 hdc 协议代际差，这是同类板子的公开案例：OpenHarmony 4.1 板子配 DevEco 5.x 时
     Device Manager 根本看不到设备（CSDN bit_mike 2025-05 记录 + 华为开发者论坛同一话题回复）。
     现在这条已经被绕开：不依赖 IDE 的 hdc，改走与镜像同代的 1.3.0a，并且整条链路只走命令行。
  3) 装机这道门还剩签名：见下一节。这三点里只有第 3 条需要上板验证，其余都已核实。

签名材料：原来列为"待确认假设"，现在已解决且可脚本复现
  OpenHarmony SDK 的 toolchains/lib/OpenHarmony.p12（口令 123456）里带的是公开测试 PKI 的私钥，
  含 "openharmony application root ca" 和 "openharmony application ca" 两个 PrivateKeyEntry。
  因此不需要 IDE 自动签名、不需要厂商签名包、不需要 UDID 白名单，就能签发一条设备信任的正规链：
    应用密钥对(ECC NIST-P-256) -> Application CA 签发应用证书(validity 3650 天)
      -> Profile 里 bundle-name=com.local.homekiosk、distribution-certificate 对上、有效期到 2033-05-18
      -> profile 由 "openharmony application profile release" 签成 .p7b
      -> sign-app localSign 出 HAP，verify-app 结果 Verify success
  全过程写在 scripts/make-signing-material.sh + scripts/sign.sh，几秒跑完，CI 可复现。
  两个坑实测记录：
    - SDK 自带的 OpenHarmonyProfileRelease.pem 是"签名 Profile 用的三级链"（叶子是 Profile Release 证书），
      不能当 -appCertFile 用，混用会报 Signature did not verify。
    - 模板 UnsgnedReleasedProfileTemplate.json 里预填的 distribution-certificate（指纹 8E:93:86:3F...）
      在 p12 里没有对应私钥，且原模板 not-after 是 2023 年，直接套模板签出来的包设备上必然被拒；
      必须换成我们自己那张叶子证书并重写有效期。

已经确认失效的下载源（别再点）
  1) winget 的 Huawei.DevEco
     包里是 3.1.0.501（2023-06 版，对应 API 9）。它指向的 CDN 直链实测 HTTP 403 Forbidden：
       .../devecostudio-windows-3.1.0.501.zip?HW-CC-Date=20230621T074329Z...
     后果：winget install Huawei.DevEco 会在下载阶段失败。
  2) OpenHarmony 官方文档里 4.0 Release 的配套 IDE
     docs/gitee 的 OpenHarmony-v4.0-release.md "版本软件和工具配套关系" 表仍写着
     DevEco Studio 4.0 Release，Windows(64-bit) 链接：
       .../devecostudio-windows-4.0.0.600.zip?HW-CC-Date=20231027T004333Z...
       SHA256 2c88cf43e1ef6ba722aac31eccc8ef92f07a9b72e43a9c1df127017828a22137
     实测同样 HTTP 403：华为已下架该包，文档未同步更新。
     "按官方配套关系回退到 4.0 IDE"这条理论最优路径，在 2026-11 走不通。
     替代结论：IDE 用最新，编译目标（SDK + hvigor）单独降到 4.0 同代，两者解耦即可。

真出问题时按这个顺序找退路
  1) 问板子厂商（硬开鸿）要"开发板配套工具包"。开发者手机形态开发板一般随镜像附 SDK/IDE 与
     应用调试签名材料，这是唯一能保证 hdc 协议版本和板端 hdcd 匹配、且签名根一定被信任的来源。
  2) 只换 hdc：export HDC=<另一份 hdc.exe 绝对路径>，其余仍用现在的 SDK/hvigor，重跑 scripts/doctor.sh。
  3) 装不上且报 9568322/9568313：走 IDE 的 Automatically generate signature 拿到 IDE 那套材料，
     复制进 signing/ 覆盖（IDE 生成的东西本身也是 CA 签发的，只是密钥不是我们这把）。
  4) 刷机到 5.0 尝鲜版（API 12）：bash scripts/get-ohos-sdk.sh 5.0.0-Release + bash scripts/set-api.sh 12。
     这是刷机，有变砖风险，当前信息屏工程并不依赖它。

本机安装过程里唯一没收尾的一项（如实记录）
  起初用 winget 装了 Microsoft.OpenJDK.17 到 C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot。
  后来按要求改成 D 盘解压版，用户级 JAVA_HOME / PATH 也已指过去，构建与签名实测用的都是 D 盘那个
  （doctor.sh 会打印 java 的实际路径）。但卸载 C 盘那一次返回：
      卸载失败，退出代码为: 1603
  按"失败即停手"的约定我没有换方案重试。影响只是留了一份没人引用的冗余 JDK。
  要清掉的话手动跑一次并同意 UAC：
      winget uninstall --id Microsoft.OpenJDK.17

验收（三条命令，从冷环境到装机；2026-11-15 已在本机全部跑通）
  bash scripts/doctor.sh                    # 实测：21 项全过，含设备 API 11 / LHT16 / OpenHarmony-4.1.7.5
  bash scripts/pipeline.sh                  # 实测：build -> sign -> install -> 启动 -> 截图 全绿
  bash scripts/make-signing-material.sh     # 期望：三件套重新生成，Profile bundle-name 对上

装机之后踩到的构建/路径/网络坑，统一记在 docs/PITFALLS.md，这里不再展开。
