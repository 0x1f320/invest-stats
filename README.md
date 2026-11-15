# Invest Stats

**Invest Stats** is a macOS menu bar app that shows live stock prices, market indicators and your portfolio profit from the [Toss Securities OpenAPI](https://developers.tossinvest.com/docs), in the style of iStat Menus.

The app's UI is in Korean, since it is built for Toss Securities users.

## Features

### Stock items

Each stock item is its own menu bar item, for example `삼성전자 72,000 +1.23%`.

- **Popover:** clicking the item opens a price chart (1D / 1M / 3M / 6M / 1Y) with the day's open, high, low and volume.
- **US stocks:** each item can show its price in dollars or in won, converted at the USD/KRW base rate (매매기준율).
- **Market status:** the popover shows the stock's market session, such as `정규장 · 15:30까지`, or when it opens next, such as `장 마감 · 다음 개장 11/17 08:00 프리마켓`. US stocks tell the day, pre, regular and after market apart.
- **Custom format:** see [Menu bar format](#menu-bar-format).

### Asset items

An asset item shows the profit on an account's holdings as `{profit}₩ ({rate}%)`, for example `+1,019,000₩ (+11.79%)`.

- **Profit:** since purchase or since the previous close, either raw or after fees and taxes.
- **Popover:** clicking the item lists every holding with its price, a 30-day sparkline and its profit. Tapping a holding shows how its market value, purchase amount, profit, costs and weight are calculated.
- **US holdings:** converted to KRW at the base rate.
- **Market status:** the popover shows the session of each market the holdings trade on.
- **Profit colors:** each item can color its profit and rate by their sign, red for a gain and blue for a loss by default. The color convention is set in the general settings.
- **Custom format:** see [Menu bar format](#menu-bar-format).

### Indicator items

An indicator item shows a market index, a Korean government bond yield or the USD/KRW base rate, for example `코스피 2,812.45 +0.51%`.

- **Indicators:** KOSPI and KOSDAQ, government bond yields (2, 3, 5, 10, 20 and 30 years), and the USD/KRW base rate (매매기준율).
- **Values as the API reports them:** indices in points, bond yields in percent, and the exchange rate in won per dollar.
- **Change:** an index shows its change rate since the previous close and a bond yield its change in percentage points (`%p`), both against the previous daily close the API reports. The exchange rate API reports no previous value, so the exchange rate shows only the direction it reports.
- **Popover:** clicking the item opens a chart (1D / 1M / 3M / 6M / 1Y for indices; bonds have daily candles only, so no 1D) with the day's open, high, low and previous close. The exchange rate API has no candles, so its popover shows the buying rate and its spread over the base rate instead.
- **Custom format:** see [Menu bar format](#menu-bar-format).

### Menu bar format

Each item can replace its menu bar text with a format of its own, set in the **표시** (Display) tab of its settings window. Codes such as `%p` stand for the item's values, `%%` is a literal `%`, and any other text is shown as written. Left empty, the item keeps its default text.

| Code | Stock item | Asset item | Indicator item |
| --- | --- | --- | --- |
| `%n` | Name (display name or stock name) | | Name (display name or indicator name) |
| `%c` | Stock code | | Indicator code, such as `KOSPI` or `USD/KRW` |
| `%p` | Price | Profit | Value (index, yield or exchange rate) |
| `%r` | Change rate since the previous close | Profit rate | Change rate since the previous close (empty for the exchange rate) |
| `%a` | Change amount since the previous close | | Change since the previous close, in `%p` for yields (empty for the exchange rate) |
| `%l` | | Label | |
| `%v` | | Market value | |
| `%b` | | Purchase amount | |

For example, `%n %p (%a, %r)` shows `삼성전자 72,000 (+900, +1.23%)`, `%l %r` shows `💰 +11.79%`, and `%c %p %a` on a bond yield shows `KR_BOND_10Y 3.215% -0.035%p`.

### Closed markets

Turn on **장이 닫힌 항목 흐리게 표시** in the general settings to dim an item's menu bar text while every market it follows is closed: the stock's market for a stock item, the markets of the holdings for an asset item, and the KRX market for an index or bond yield item. The exchange rate follows no market's hours, so it is never dimmed. The pre, after and US day market sessions count as open. It is off by default, so the text stays white.

### Connections

Each item reads from a connection: a provider (Toss Securities for now) and its API keys. Connections are managed in the **연결** (Connections) settings tab.

- **Several connections:** add as many as you like, including more than one for the same provider, for example your own account and a family member's. Each one needs its own keys, since two connections with the same keys would keep invalidating each other's token.
- **Per item:** adding an item asks which connection it reads from, and the item's settings window can change it later.
- **iCloud sync:** in release builds, turn on **iCloud 키체인으로 연결 동기화** in the 연결 tab to sync all connections, with their cached tokens, through the iCloud Keychain. They then show up on your other Macs signed in to the same Apple Account that have sync on. A Mac with sync off offers connections it finds there.

### Any number of items

Add as many stock, asset and indicator items as you like, and remove them from the settings window, the item's right-click menu, or the `…` menu in its popover.

- **Adding:** a small dialog asks only for what the item needs, a stock, an account or an indicator, and then opens the item's settings window.
- **Settings window:** each item has its own window with toolbar tabs, like a macOS settings window: 종목 (Stock) and 표시 (Display) for a stock item, 계좌 (Account), 손익 (Profit) and 표시 (Display) for an asset item, and 지표 (Indicator) and 표시 (Display) for an indicator item. Changes apply as you make them. Open it with 편집 (Edit) in the settings, the item's right-click menu, or the `…` menu in its popover.

Positions are kept by macOS. Rearrange items with ⌘-drag or a menu bar manager such as [Thaw](https://github.com/stonerl/Thaw) or [Ice](https://github.com/jordanbaird/Ice).

### Updates

Invest Stats checks [GitHub Releases](https://github.com/0x1f320/invest-stats/releases) at launch and every 30 minutes. When a newer version is out, it shows the changes since your version and installs the update when you accept, then relaunches.

- **Settings:** the **업데이트** (Updates) tab checks on demand and turns automatic checks off.
- **Pre-releases:** turn on **프리릴리스 받기** to also get builds from `dev`. Pre-release builds start with it on.
- **Safety:** an update is installed only if it is signed by the same developer as the running app.
- **Local builds** don't update themselves.

## Requirements

- macOS 14 or later
- Swift 5.10 or later. The Command Line Tools are enough; Xcode is not required.
- A Toss Securities OpenAPI client, with this Mac's public IP on its allow list

## Install

Download `InvestStats-<version>.zip` from [Releases](https://github.com/0x1f320/invest-stats/releases), unzip it, and move `Invest Stats.app` to `/Applications`. Releases are signed with a Developer ID and notarized by Apple, so they open without a Gatekeeper warning. After that, Invest Stats updates itself; keep it in a folder you can write to, such as `/Applications`.

- **Releases** such as `v1.2.0` are built from `main`.
- **Pre-releases** such as `v1.2.0-dev.1` are built from `dev` and carry changes that haven't reached a release yet.

### Coming from TossBar

The app used to be called TossBar, with the bundle id `dev.tossbar.TossBar`. TossBar builds can't update themselves to Invest Stats, so install it by hand and delete `TossBar.app`.

- **Kept:** on its first launch, Invest Stats copies TossBar's settings, items and menu bar positions. Keys in `~/Library/Application Support/TossBar/` and in the iCloud Keychain keep working; they become a connection, as described below.
- **Turn on again:** **Allow in Menu Bar** on macOS 26 and **로그인 시 실행** (launch at login), since macOS tracks both per app.

Every release, pre-releases included, is listed in [CHANGELOG.md](CHANGELOG.md).

## Build and run

```bash
scripts/build-app.sh            # builds and ad-hoc signs "build/Invest Stats.app"
open "build/Invest Stats.app"
cp -R "build/Invest Stats.app" /Applications/   # optional
```

Run the tests with:

```bash
scripts/test.sh
```

## First launch

1. **Register a client:** in Toss Securities WTS (the PC web app), open 설정 > Open API and register a client. Add this Mac's public IP to the allowed IPs; requests from other IPs fail with 403.
2. **Add a connection:** enter the Client ID and Secret in the window that opens on first launch, then click **저장 및 연결 테스트** (save and test). Add more connections later in the **연결** settings tab.
3. **Storage:** by default a connection is stored in `~/Library/Application Support/TossBar/`, readable only by your user (`0600`). It is not stored in the login Keychain, so rebuilding the app never asks for your password.
   - **Sync with your other Macs:** in release builds, turn on **iCloud 키체인으로 연결 동기화**. Every connection and its cached token move to the iCloud Keychain and are shared with your other Macs signed in to the same Apple Account. Turning sync off keeps a copy of the connections on this Mac and leaves the other Macs as they are.
   - Each Mac still needs its public IP in the client's allowed IPs.
4. **Use a dedicated client:** Toss Securities keeps only one valid token per client. If another tool uses the same keys, each will keep invalidating the other's token.

### Upgrading from a version without connections

The single set of keys that earlier versions saved becomes a connection on the first launch, with the same cached token, and existing items use it. A Mac that stored its keys in the iCloud Keychain starts with connection sync on. Macs that migrate the same keys arrive at the same connection, so a synced connection is never duplicated.

## Troubleshooting

### The app is running but no items appear

On macOS 26, check **System Settings > Menu Bar > Allow in Menu Bar** and make sure Invest Stats is on. Invest Stats detects this state and offers to open the setting.

To see what the menu bar is doing with each item, run:

```bash
TOSSBAR_DIAG=1 "build/Invest Stats.app/Contents/MacOS/TossBar"
```

### "허용되지 않은 IP 입니다"

Your public IP changed or isn't registered. Add it in WTS > 설정 > Open API.

## How it works

| Path | Role |
| --- | --- |
| `Sources/TossBar/API` | REST client, one per connection: OAuth2 token cache, per-group rate limiting, 429 and 401 retries |
| `Sources/TossBar/Data` | Polling loop and one data service per connection, chart and sparkline data, KRW conversion, the searchable stock list |
| `Sources/TossBar/StatusBar` | One `NSStatusItem` and popover per item, synced with the item list |
| `Sources/TossBar/Update` | GitHub Releases check, version comparison, download, signature check and install |
| `Sources/TossBar/Store` | Item configs and settings (UserDefaults), connections and tokens (files or the iCloud Keychain) |
| `Sources/TossBar/Views` | SwiftUI popovers, settings and onboarding |

Some design choices:

- **Batched prices:** prices for every item of a connection are fetched in one request per refresh, so many items cost the same as one. Indicator values are batched the same way, in their own request.
- **Idle polling:** while every market a connection's items follow is closed, that connection is refreshed every 5 minutes instead of at the refresh interval, and at full speed again once a market opens. Index and bond yield items follow the KRX market; the exchange rate follows none, so a connection with an exchange rate item keeps polling at the refresh interval.
- **Stable status items:** each status item has a stable `autosaveName` and is never recreated on edit. This keeps its position with macOS and with menu bar managers.
- **Raw API figures:** profit figures come straight from the API's own calculations, including the after-cost values. Only the USD to KRW conversion is done locally.

## License

[MIT](LICENSE). Market and account data is provided by the Toss Securities OpenAPI. This project is not affiliated with Toss Securities.
