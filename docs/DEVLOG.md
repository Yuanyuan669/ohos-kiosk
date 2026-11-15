# HomeKiosk 开发日志

> 2026-11-15 起按日期记录本机/实机改动。构建、签名、装机与历史坑位见
> [README.md](../README.md)、[PITFALLS.md](PITFALLS.md)、[TOOLCHAIN-NOTES.md](TOOLCHAIN-NOTES.md)。

---

## 2026-11-15 feat: 股市面板 + 精简汇总 feed

### 目标
- 在原有「时钟 / 天气 / 照片 / 备忘」信息屏上增加股市信息，替代纯照片轮播；
  没有数据时仍回退照片，不影响现有使用。
- 数据源分成两层：
  - TradingMaster 生成的 `kiosk_summary.json`（A 股情绪、自选、舆情，小体积）；
  - 新浪行情接口（港股 / 美股 / 商品指数，设备直连，GBK 响应只取数值字段）。
- 设备网络实测 `*.workers.dev` 被解析到不可达地址、GitHub raw 直连报
  `Unknown Other Error`，因此 kiosk 使用「镜像列表」：默认 gh-proxy.com，
  失败后依次尝试 raw / ghproxy.net / ghfast.top / statically / jsDelivr，
  不把设备绑定到单一域名。

### 实现
1. `service/HttpServices.ets`
   - 新增 `StockService.fetchSummary()`：依次尝试设置 URL 和镜像列表
     （raw / ghproxy / ghfast / statically / jsDelivr），单个失败继续下一个；
     全部失败返回 null。
   - 新增 `StockService.fetchGlobals()`：请求新浪
     `hq.sinajs.cn`，带 Referer；解析上证/深成/创业板、恒生、道指、纳指、
     标普、黄金、白银、WTI、布伦特。
   - `HttpProbe.getString()` 增加可选 Referer 头；使用显式类避免 ArkTS
     对象字面量限制。
2. `model/Types.ets`
   - 增加 `KioskSummary / KioskMarket / KioskWatch / KioskNews / GlobalQuote`
     等接口，字段与 `kiosk_summary.json` 对齐。
3. `pages/Index.ets`
   - 右侧主卡改为 `MediaCard`：有股市数据时显示 4 页面板，否则继续照片轮播。
   - 4 页：A 股市场（指数/成交/情绪/涨跌家数）、自选股、全球/商品、
     FlashQuant 舆情；20 秒自动翻页，点击卡片手动翻页。
   - 汇总里缺少指数时，用新浪 A 股指数兜底；全球页自动过滤 A 股，避免重复。
   - 移除底部页脚，给内容区释放高度；退出按钮保留。
4. `common/SettingsStore.ets` + `pages/Settings.ets`
   - 新增 `stockEnabled`、`stockSummaryUrl`、`stockRefreshSec`；
   - 设置页支持启停、feed URL、刷新间隔（最小 60 秒）；
   - 默认 feed：`https://gh-proxy.com/https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json`。
5. `feed/kiosk_summary.json`
   - 由 TradingMaster `scripts/build_kiosk_summary.py` 生成后热更新到本仓库；
     仅含公开市场汇总，不含账户、持仓、token。

### 验证
- `bash scripts/build.sh` + `bash scripts/sign.sh` 通过；HAP 已安装到
  LHT16（API 11）。
- 用本地 HTTP feed 验证 4 页均正常：A 股指数与情绪、自选股涨跌、全球/商品、
  舆情/正负新闻数；点击卡片翻页有效。
- 线上 feed 验证：GitHub raw 直连失败，`gh-proxy.com` 镜像返回 200；
  `generated_at=2026-11-15T22:46:59+08:00`，market date `2026-11-13`。
- 线上 feed 不可达时回退照片轮播，天气/照片/退出按钮未受影响。

### 已知限制
- 当前网络对 `*.workers.dev` 不可达；若 GitHub raw 也失败，面板会回退照片，
  可在设置页手动改 feed URL。
- 商品页涨跌幅用新浪昨收字段估算；行情源不保证所有品种都有昨收。
- 股市数据刷新默认 5 分钟，页面轮播 20 秒，避免信息屏频繁请求。
