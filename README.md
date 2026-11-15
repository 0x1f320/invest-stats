# Invest Stats

**Invest Stats** is a macOS menu bar app that shows live stock prices and your portfolio profit from the [Toss Securities OpenAPI](https://developers.tossinvest.com/docs), in the style of iStat Menus.

The app's UI is in Korean, since it is built for Toss Securities users.

## Features

### Stock items

Each stock item is its own menu bar item, for example `삼성전자 72,000 +1.23%`.

- **Popover:** clicking the item opens a price chart (1D / 1M / 3M / 6M / 1Y) with the day's open, high, low and volume.
- **US stocks:** each item can show its price in dollars or in won, converted at the USD/KRW base rate (매매기준율).

### Asset items

An asset item shows the profit on an account's holdings as `{profit}₩ ({rate}%)`, for example `+1,019,000₩ (+11.79%)`.

- **Profit:** since purchase or since the previous close, either raw or after fees and taxes.
- **Popover:** clicking the item lists every holding with its price, a 30-day sparkline and its profit. Tapping a holding shows how its market value, purchase amount, profit, costs and weight are calculated.
- **US holdings:** converted to KRW at the base rate.
- **Profit colors:** each item can color its profit and rate by their sign, red for a gain and blue for a loss by default. The color convention is set in the general settings.

### Any number of items

Add as many stock and asset items as you like, and remove them from the settings window, the item's right-click menu, or the `…` menu in its popover.

Positions are kept by macOS. Rearrange items with ⌘-drag or a menu bar manager such as [Thaw](https://github.com/stonerl/Thaw) or [Ice](https://github.com/jordanbaird/Ice).

### Updates

Invest Stats checks [GitHub Releases](https://github.com/0x1f320/invest-stats/releases) at launch and once a day. When a newer version is out, it shows the changes since your version and installs the update when you accept, then relaunches.

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

- **Kept:** on its first launch, Invest Stats copies TossBar's settings, items and menu bar positions. Keys in `~/Library/Application Support/TossBar/` and in the iCloud Keychain keep working.
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
2. **Enter the keys:** enter the Client ID and Secret in the window that opens on first launch, then click **저장 및 연결 테스트** (save and test).
3. **Storage:** by default the keys are stored in `~/Library/Application Support/TossBar/`, readable only by your user (`0600`). They are not stored in the login Keychain, so rebuilding the app never asks for your password.
   - **Share with your other Macs:** in release builds, turn on **iCloud 키체인에 저장해 같은 Apple 계정의 다른 Mac 과 공유** before saving. The keys and the cached token move to the iCloud Keychain. On another Mac signed in to the same Apple Account, Invest Stats offers the shared keys on first launch.
   - Each Mac still needs its public IP in the client's allowed IPs.
4. **Use a dedicated client:** Toss Securities keeps only one valid token per client. If another tool uses the same keys, each will keep invalidating the other's token.

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
| `Sources/TossBar/API` | REST client: OAuth2 token cache, per-group rate limiting, 429 and 401 retries |
| `Sources/TossBar/Data` | Shared polling service, chart and sparkline data, KRW conversion, the searchable stock list |
| `Sources/TossBar/StatusBar` | One `NSStatusItem` and popover per item, synced with the item list |
| `Sources/TossBar/Update` | GitHub Releases check, version comparison, download, signature check and install |
| `Sources/TossBar/Store` | Item configs and settings (UserDefaults), API keys and token (files) |
| `Sources/TossBar/Views` | SwiftUI popovers, settings and onboarding |

Some design choices:

- **Batched prices:** prices for every item are fetched in one request per refresh, so many items cost the same as one.
- **Stable status items:** each status item has a stable `autosaveName` and is never recreated on edit. This keeps its position with macOS and with menu bar managers.
- **Raw API figures:** profit figures come straight from the API's own calculations, including the after-cost values. Only the USD to KRW conversion is done locally.

## License

[MIT](LICENSE). Market and account data is provided by the Toss Securities OpenAPI. This project is not affiliated with Toss Securities.
