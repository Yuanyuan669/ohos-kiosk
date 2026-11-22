signing/ — 这块板子的签名材料从哪来

结论：不用等 IDE，也不用找厂商。一条命令就能生成整套。

    bash scripts/make-signing-material.sh

生成后这个目录里会有（全部已被 .gitignore 排除，绝不进仓库）：

    homekiosk.p12            应用密钥对，别名 homekiosk-app-key-v1，口令 123456
    homekiosk-app.cer        三级证书链：我们的应用证书 <- Application CA <- Application Root CA
    homekiosk-profile.json   未签名的 Profile（bundle-name / 有效期 / 叶子证书都已写好）
    homekiosk-profile.p7b    由 Profile Release 私钥签好的 Profile，设备读的就是这个
    root-ca.cer app-ca.cer   从 SDK 里导出的两级公开 CA，只是中间产物

为什么这套东西能被标准系统开发镜像接受
  OpenHarmony SDK 的 toolchains/lib/OpenHarmony.p12（store 口令 123456）里放的是社区公开测试 PKI 的
  私钥，其中包括 "openharmony application ca" 和 "openharmony application root ca" 两个 PrivateKeyEntry。
  出厂镜像内置的根就对应这套测试 PKI。所以脚本不是"自签一张孤儿证书"，而是让官方 Application CA
  给我们的应用密钥正式签发证书 —— 链条能一直追到设备已经信任的根。

  另外三个约定必须在一条链上自洽，否则设备报 9568322 / 9568313：
    Profile 的 bundle-name      == AppScope/app.json5 的 bundleName
    Profile 的 distribution-certificate == -appCertFile 的叶子证书
    -appCertFile 的叶子         == -keystoreFile 里 -keyAlias 对应的公钥
  make-signing-material.sh 是从头到尾按这个顺序生成的，所以不会错开；改包名后重跑一次即可。

实测踩过的两个坑（脚本已避开）
  1) SDK 里的 OpenHarmonyProfileRelease.pem 名字看着像"应用证书"，其实是签 Profile 用的三级链，
     叶子是 Profile Release 证书。把它当 -appCertFile 传给 sign-app 会报 Signature did not verify。
  2) UnsgnedReleasedProfileTemplate.json 里预填的 distribution-certificate 在 p12 中没有对应私钥，
     而且模板的 not-after 停在 2023 年。直接拿模板签出来的包，设备一定拒。

在 CI 上怎么带这份材料
  两条等价路径，任选一条：
    A. 把 signing/ 压成 zip、base64 存进 secret（模板里的 OHOS_SIGNING_ZIP），流水线解出来直接用。
       口令另存三个变量：OHOS_STORE_PWD / OHOS_KEY_PWD / OHOS_PROFILE_PWD。
    B. 不进 secret，runner 上现跑 make-signing-material.sh —— 它只需要 SDK（get-ohos-sdk.sh 装好的那份），
       完全离线、可重复。缺点是每个 runner 的密钥不是同一把，但只要 Profile 一起重新生成就不影响安装。
  密码不要写进 scripts/env.sh；那里只是本地默认值的兜底。

如果这块板子的镜像改过根（第一次装机失败时）
  1) DevEco Studio 打开工程 -> File -> Project Structure -> Signing Configs ->
     Automatically generate signature -> 选中板子 -> Run。跑通后 IDE 会把生成的
     .p12/.cer/.p7b 放在 %USERPROFILE%\.ohos\config，复制到本目录并按 sign.sh 的命名约定改名
     （homekiosk.p12 / homekiosk-app.cer / homekiosk-profile.p7b），命令行路径立刻恢复可用。
     注意 sign.sh 用 -keyAlias 选择别名，IDE 那套一般别名是 digitalKey 之类，需要
     export OHOS_KEY_ALIAS=<IDE 里的别名>。
  2) 找硬开鸿要"开发板调试签名包"，那是厂商根的唯一来源。
