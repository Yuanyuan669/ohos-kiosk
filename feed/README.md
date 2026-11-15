# kiosk feed

`kiosk_summary.json` 是 HomeKiosk 股市面板读取的公开精简汇总，由
TradingMaster 的 `scripts/build_kiosk_summary.py` 生成。

- 更新方式：把新生成的文件覆盖到本目录并提交推送；设备会按设置中的刷新间隔重读。
- 默认地址（gh-proxy 镜像）：
  `https://gh-proxy.com/https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json`
- kiosk 内置失败回退列表：GitHub raw → ghproxy.net → ghfast.top →
  statically → jsDelivr；任一成功即停止。
- 文件只包含公开市场数据，不包含账户、持仓、token 或任何密钥。
