# Changelog

## [1.2.0-dev.4](https://github.com/0x1f320/invest-stats/compare/v1.2.0-dev.3...v1.2.0-dev.4) (2026-11-17)

### Features

* **alert:** sell a holding from its alert notification ([#46](https://github.com/0x1f320/invest-stats/issues/46)) ([dd05808](https://github.com/0x1f320/invest-stats/commit/dd05808a72818fe034a1fa7ae20ac753b41f7440))

## [1.2.0-dev.3](https://github.com/0x1f320/invest-stats/compare/v1.2.0-dev.2...v1.2.0-dev.3) (2026-11-17)

### Features

* **api:** add the sellable quantity and order endpoints ([#45](https://github.com/0x1f320/invest-stats/issues/45)) ([5355eb7](https://github.com/0x1f320/invest-stats/commit/5355eb7d7b6dc7e875c2d329885f34c42c9e7eed))

## [1.2.0-dev.2](https://github.com/0x1f320/invest-stats/compare/v1.2.0-dev.1...v1.2.0-dev.2) (2026-11-17)

### Features

* **alert:** alert on a stock's holding profit and rate ([#44](https://github.com/0x1f320/invest-stats/issues/44)) ([1b35952](https://github.com/0x1f320/invest-stats/commit/1b359524e2486c111bf29fcfa804de484fdc1e47))

## [1.2.0-dev.1](https://github.com/0x1f320/invest-stats/compare/v1.1.1-dev.4...v1.2.0-dev.1) (2026-11-17)

### Features

* **stock:** show the holding's profit on stock items ([#43](https://github.com/0x1f320/invest-stats/issues/43)) ([5fbf747](https://github.com/0x1f320/invest-stats/commit/5fbf747195deb9414367b117a2d473be6078dda5))

## [1.1.1-dev.4](https://github.com/0x1f320/invest-stats/compare/v1.1.1-dev.3...v1.1.1-dev.4) (2026-11-17)

### Bug Fixes

* **status-bar:** dim menu bar text on inactive displays ([#42](https://github.com/0x1f320/invest-stats/issues/42)) ([a53e87f](https://github.com/0x1f320/invest-stats/commit/a53e87fbc7526e718544efdddfeeb6585575d631))

## [1.1.1-dev.3](https://github.com/0x1f320/invest-stats/compare/v1.1.1-dev.2...v1.1.1-dev.3) (2026-11-15)

### Bug Fixes

* **update:** check releases without the github api rate limit ([#41](https://github.com/0x1f320/invest-stats/issues/41)) ([88c937d](https://github.com/0x1f320/invest-stats/commit/88c937d49f9fe8b8b701992b41cbda3ba734b360))

## [1.1.1-dev.2](https://github.com/0x1f320/invest-stats/compare/v1.1.1-dev.1...v1.1.1-dev.2) (2026-11-15)

### Bug Fixes

* **status-bar:** close the popover when an app window opens ([#40](https://github.com/0x1f320/invest-stats/issues/40)) ([fa08b37](https://github.com/0x1f320/invest-stats/commit/fa08b3752316260d3ab77f0dbf4db350435c139a))

## [1.1.1-dev.1](https://github.com/0x1f320/invest-stats/compare/v1.1.0...v1.1.1-dev.1) (2026-11-15)

### Bug Fixes

* **update:** check for updates every 30 minutes ([#39](https://github.com/0x1f320/invest-stats/issues/39)) ([cff1235](https://github.com/0x1f320/invest-stats/commit/cff1235d0723d9b15a27fd8a9bbd62bc6fae456d))

## [1.1.0](https://github.com/0x1f320/invest-stats/compare/v1.0.0...v1.1.0) (2026-11-15)

### Features

* **alerts:** evaluate price alert conditions with re-arming ([#32](https://github.com/0x1f320/invest-stats/issues/32)) ([db2bf8a](https://github.com/0x1f320/invest-stats/commit/db2bf8acb834d4737adb8ed0e26a97963e4cf7eb))
* **alerts:** notify price alerts and set them per item ([#33](https://github.com/0x1f320/invest-stats/issues/33)) ([4c09287](https://github.com/0x1f320/invest-stats/commit/4c09287c8745f9f2d52828725023af5eae6779e5)), closes [#32](https://github.com/0x1f320/invest-stats/issues/32)
* **api:** add market indicator endpoints ([#34](https://github.com/0x1f320/invest-stats/issues/34)) ([0dd7e8e](https://github.com/0x1f320/invest-stats/commit/0dd7e8e3e5e58f4dcca5407063797d65227a6cd5))
* **indicator:** add market index, bond yield and exchange rate items ([#35](https://github.com/0x1f320/invest-stats/issues/35)) ([85617d7](https://github.com/0x1f320/invest-stats/commit/85617d7e45b8e2b739867ec44a24691097c74256)), closes [#29](https://github.com/0x1f320/invest-stats/issues/29) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#31](https://github.com/0x1f320/invest-stats/issues/31) [#34](https://github.com/0x1f320/invest-stats/issues/34) [#29](https://github.com/0x1f320/invest-stats/issues/29) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#31](https://github.com/0x1f320/invest-stats/issues/31)
* **indicator:** chart indices and bond yields in the popover ([#36](https://github.com/0x1f320/invest-stats/issues/36)) ([f107031](https://github.com/0x1f320/invest-stats/commit/f10703189ff5c83a627c29c3210872e4ed7c0543)), closes [#35](https://github.com/0x1f320/invest-stats/issues/35)
* **market:** show the market session in stock and asset popovers ([#29](https://github.com/0x1f320/invest-stats/issues/29)) ([fcc5d13](https://github.com/0x1f320/invest-stats/commit/fcc5d130aef1a61c367c2ff60baf3ae862075042))
* **menubar:** optionally dim items while their markets are closed ([#31](https://github.com/0x1f320/invest-stats/issues/31)) ([aa65080](https://github.com/0x1f320/invest-stats/commit/aa6508089cd75682e65e39380ef4f9a471a7b719))

### Performance Improvements

* **market:** poll less while every market is closed ([#30](https://github.com/0x1f320/invest-stats/issues/30)) ([d63b71e](https://github.com/0x1f320/invest-stats/commit/d63b71e21553b95ec0491484e37ec2ee252bef7a))

## [1.1.0-dev.5](https://github.com/0x1f320/invest-stats/compare/v1.1.0-dev.4...v1.1.0-dev.5) (2026-11-15)

### Features

* **alerts:** evaluate price alert conditions with re-arming ([#32](https://github.com/0x1f320/invest-stats/issues/32)) ([db2bf8a](https://github.com/0x1f320/invest-stats/commit/db2bf8acb834d4737adb8ed0e26a97963e4cf7eb))
* **alerts:** notify price alerts and set them per item ([#33](https://github.com/0x1f320/invest-stats/issues/33)) ([4c09287](https://github.com/0x1f320/invest-stats/commit/4c09287c8745f9f2d52828725023af5eae6779e5)), closes [#32](https://github.com/0x1f320/invest-stats/issues/32)

## [1.1.0-dev.4](https://github.com/0x1f320/invest-stats/compare/v1.1.0-dev.3...v1.1.0-dev.4) (2026-11-15)

### Features

* **indicator:** chart indices and bond yields in the popover ([#36](https://github.com/0x1f320/invest-stats/issues/36)) ([f107031](https://github.com/0x1f320/invest-stats/commit/f10703189ff5c83a627c29c3210872e4ed7c0543)), closes [#35](https://github.com/0x1f320/invest-stats/issues/35)

## [1.1.0-dev.3](https://github.com/0x1f320/invest-stats/compare/v1.1.0-dev.2...v1.1.0-dev.3) (2026-11-15)

### Features

* **indicator:** add market index, bond yield and exchange rate items ([#35](https://github.com/0x1f320/invest-stats/issues/35)) ([85617d7](https://github.com/0x1f320/invest-stats/commit/85617d7e45b8e2b739867ec44a24691097c74256)), closes [#29](https://github.com/0x1f320/invest-stats/issues/29) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#31](https://github.com/0x1f320/invest-stats/issues/31) [#34](https://github.com/0x1f320/invest-stats/issues/34) [#29](https://github.com/0x1f320/invest-stats/issues/29) [#30](https://github.com/0x1f320/invest-stats/issues/30) [#31](https://github.com/0x1f320/invest-stats/issues/31)

## [1.1.0-dev.2](https://github.com/0x1f320/invest-stats/compare/v1.1.0-dev.1...v1.1.0-dev.2) (2026-11-15)

### Features

* **menubar:** optionally dim items while their markets are closed ([#31](https://github.com/0x1f320/invest-stats/issues/31)) ([aa65080](https://github.com/0x1f320/invest-stats/commit/aa6508089cd75682e65e39380ef4f9a471a7b719))

## [1.1.0-dev.1](https://github.com/0x1f320/invest-stats/compare/v1.0.0...v1.1.0-dev.1) (2026-11-15)

### Features

* **api:** add market indicator endpoints ([#34](https://github.com/0x1f320/invest-stats/issues/34)) ([0dd7e8e](https://github.com/0x1f320/invest-stats/commit/0dd7e8e3e5e58f4dcca5407063797d65227a6cd5))
* **market:** show the market session in stock and asset popovers ([#29](https://github.com/0x1f320/invest-stats/issues/29)) ([fcc5d13](https://github.com/0x1f320/invest-stats/commit/fcc5d130aef1a61c367c2ff60baf3ae862075042))

### Performance Improvements

* **market:** poll less while every market is closed ([#30](https://github.com/0x1f320/invest-stats/issues/30)) ([d63b71e](https://github.com/0x1f320/invest-stats/commit/d63b71e21553b95ec0491484e37ec2ee252bef7a))

## 1.0.0 (2026-11-15)

### ⚠ BREAKING CHANGES

* rename the app to invest stats (#20)

### Features

* add API key onboarding and settings window ([#3](https://github.com/0x1f320/invest-stats/issues/3)) ([bd7e1a6](https://github.com/0x1f320/invest-stats/commit/bd7e1a624256e8447acee54e18c0c435144acee2)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* add app icon ([#18](https://github.com/0x1f320/invest-stats/issues/18)) ([b8b02a5](https://github.com/0x1f320/invest-stats/commit/b8b02a58b2f52c18c68b056f7a826bb6bfdd3b88))
* **api:** add Toss Securities OpenAPI client ([#2](https://github.com/0x1f320/invest-stats/issues/2)) ([342bc82](https://github.com/0x1f320/invest-stats/commit/342bc82fed4e77f7429ee172d3e596455ec9163c))
* **asset:** add holdings profit menu bar item ([#7](https://github.com/0x1f320/invest-stats/issues/7)) ([3146eda](https://github.com/0x1f320/invest-stats/commit/3146edaacad9db1b1e22a9b7d5b99d9f9ff1e165)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* **asset:** choose raw or after-fee/tax profit basis ([#9](https://github.com/0x1f320/invest-stats/issues/9)) ([c831aa9](https://github.com/0x1f320/invest-stats/commit/c831aa94b9c8b57f40bd7b6d3b6456f4010c689b)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* **asset:** color menu bar profit by its sign ([#13](https://github.com/0x1f320/invest-stats/issues/13)) ([b1be59a](https://github.com/0x1f320/invest-stats/commit/b1be59af85a2a6aae7339dc2319107803b0331d5))
* **asset:** show holdings breakdown popover ([#8](https://github.com/0x1f320/invest-stats/issues/8)) ([8f2bda4](https://github.com/0x1f320/invest-stats/commit/8f2bda4035cbc852cf6db7478ca578204f565599)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* edit items in their own settings windows ([#23](https://github.com/0x1f320/invest-stats/issues/23)) ([d593428](https://github.com/0x1f320/invest-stats/commit/d593428d07f3415320bf68df3e6c6b0260711d57))
* manage multiple connections and pick one per item ([#22](https://github.com/0x1f320/invest-stats/issues/22)) ([d634eec](https://github.com/0x1f320/invest-stats/commit/d634eec18052bbea7242f547857af6de8ae7e76e))
* **menubar:** let each item set its own menu bar format ([#26](https://github.com/0x1f320/invest-stats/issues/26)) ([494ce06](https://github.com/0x1f320/invest-stats/commit/494ce06546bf17bdeda5716d6867ea38fdc74c74))
* offer updates from github releases with their changelog ([#16](https://github.com/0x1f320/invest-stats/issues/16)) ([0d9d6f4](https://github.com/0x1f320/invest-stats/commit/0d9d6f4c9a4698b4f0ee1cbc3146ed0034bc2610))
* rename the app to invest stats ([#20](https://github.com/0x1f320/invest-stats/issues/20)) ([c1c84e2](https://github.com/0x1f320/invest-stats/commit/c1c84e29ed07d9aad8219df49e1ece6dc0944f9e))
* share api keys with other macs through the icloud keychain ([#15](https://github.com/0x1f320/invest-stats/issues/15)) ([dbf34b8](https://github.com/0x1f320/invest-stats/commit/dbf34b83cd696178d2929b4a48a3c40caac17fba))
* **stock:** add per-item KRW/USD display for US stocks ([#6](https://github.com/0x1f320/invest-stats/issues/6)) ([293a6e5](https://github.com/0x1f320/invest-stats/commit/293a6e53141ae19c5e093ac1619109658cc6b973)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* **stock:** add stock price menu bar item ([#4](https://github.com/0x1f320/invest-stats/issues/4)) ([63f2cd4](https://github.com/0x1f320/invest-stats/commit/63f2cd4539e3b588a057ef54f8d73018f60c0cd6)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* **stock:** show recent price chart popover ([#5](https://github.com/0x1f320/invest-stats/issues/5)) ([a96de46](https://github.com/0x1f320/invest-stats/commit/a96de46128c487fde3e6c3121a9bb6cc9f408b62)), closes [#11](https://github.com/0x1f320/invest-stats/issues/11)
* warn when macOS hides the menu bar items ([#10](https://github.com/0x1f320/invest-stats/issues/10)) ([ae6499b](https://github.com/0x1f320/invest-stats/commit/ae6499bd362895d240b4517be6456f7818d07559))

### Bug Fixes

* pad the settings window and unify tab backgrounds ([#21](https://github.com/0x1f320/invest-stats/issues/21)) ([c6267a4](https://github.com/0x1f320/invest-stats/commit/c6267a47babb1c3b4940bcbbbf5a56d917b19731))
* soften trend colors in dark mode popovers ([#19](https://github.com/0x1f320/invest-stats/issues/19)) ([26cb589](https://github.com/0x1f320/invest-stats/commit/26cb589458871fbe19f502ed580cef12d56face4))

## [1.0.0-dev.9](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.8...v1.0.0-dev.9) (2026-11-15)

### Features

* edit items in their own settings windows ([#23](https://github.com/0x1f320/invest-stats/issues/23)) ([d593428](https://github.com/0x1f320/invest-stats/commit/d593428d07f3415320bf68df3e6c6b0260711d57))
* **menubar:** let each item set its own menu bar format ([#26](https://github.com/0x1f320/invest-stats/issues/26)) ([494ce06](https://github.com/0x1f320/invest-stats/commit/494ce06546bf17bdeda5716d6867ea38fdc74c74))

## [1.0.0-dev.9](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.8...v1.0.0-dev.9) (2026-11-15)

### Features

* edit items in their own settings windows ([#23](https://github.com/0x1f320/invest-stats/issues/23)) ([d593428](https://github.com/0x1f320/invest-stats/commit/d593428d07f3415320bf68df3e6c6b0260711d57))

## [1.0.0-dev.9](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.8...v1.0.0-dev.9) (2026-11-15)

### Features

* edit items in their own settings windows ([#23](https://github.com/0x1f320/invest-stats/issues/23)) ([d593428](https://github.com/0x1f320/invest-stats/commit/d593428d07f3415320bf68df3e6c6b0260711d57))

## [1.0.0-dev.8](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.7...v1.0.0-dev.8) (2026-11-15)

### Features

* manage multiple connections and pick one per item ([#22](https://github.com/0x1f320/invest-stats/issues/22)) ([d634eec](https://github.com/0x1f320/invest-stats/commit/d634eec18052bbea7242f547857af6de8ae7e76e))

## [1.0.0-dev.7](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.6...v1.0.0-dev.7) (2026-11-15)

### Bug Fixes

* pad the settings window and unify tab backgrounds ([#21](https://github.com/0x1f320/invest-stats/issues/21)) ([c6267a4](https://github.com/0x1f320/invest-stats/commit/c6267a47babb1c3b4940bcbbbf5a56d917b19731))

## [1.0.0-dev.6](https://github.com/0x1f320/invest-stats/compare/v1.0.0-dev.5...v1.0.0-dev.6) (2026-11-15)

### ⚠ BREAKING CHANGES

* rename the app to invest stats (#20)

### Features

* rename the app to invest stats ([#20](https://github.com/0x1f320/invest-stats/issues/20)) ([c1c84e2](https://github.com/0x1f320/invest-stats/commit/c1c84e29ed07d9aad8219df49e1ece6dc0944f9e))

## [1.0.0-dev.3](https://github.com/0x1f320/tossinvest-stats/compare/v1.0.0-dev.2...v1.0.0-dev.3) (2026-11-15)

### Features

* offer updates from github releases with their changelog ([#16](https://github.com/0x1f320/tossinvest-stats/issues/16)) ([0d9d6f4](https://github.com/0x1f320/tossinvest-stats/commit/0d9d6f4c9a4698b4f0ee1cbc3146ed0034bc2610))

## [1.0.0-dev.2](https://github.com/0x1f320/tossinvest-stats/compare/v1.0.0-dev.1...v1.0.0-dev.2) (2026-11-15)

### Features

* share api keys with other macs through the icloud keychain ([#15](https://github.com/0x1f320/tossinvest-stats/issues/15)) ([dbf34b8](https://github.com/0x1f320/tossinvest-stats/commit/dbf34b83cd696178d2929b4a48a3c40caac17fba))

## 1.0.0-dev.1 (2026-11-14)

### Features

* add API key onboarding and settings window ([#3](https://github.com/0x1f320/tossinvest-stats/issues/3)) ([bd7e1a6](https://github.com/0x1f320/tossinvest-stats/commit/bd7e1a624256e8447acee54e18c0c435144acee2)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **api:** add Toss Securities OpenAPI client ([#2](https://github.com/0x1f320/tossinvest-stats/issues/2)) ([342bc82](https://github.com/0x1f320/tossinvest-stats/commit/342bc82fed4e77f7429ee172d3e596455ec9163c))
* **asset:** add holdings profit menu bar item ([#7](https://github.com/0x1f320/tossinvest-stats/issues/7)) ([3146eda](https://github.com/0x1f320/tossinvest-stats/commit/3146edaacad9db1b1e22a9b7d5b99d9f9ff1e165)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **asset:** choose raw or after-fee/tax profit basis ([#9](https://github.com/0x1f320/tossinvest-stats/issues/9)) ([c831aa9](https://github.com/0x1f320/tossinvest-stats/commit/c831aa94b9c8b57f40bd7b6d3b6456f4010c689b)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **asset:** color menu bar profit by its sign ([#13](https://github.com/0x1f320/tossinvest-stats/issues/13)) ([b1be59a](https://github.com/0x1f320/tossinvest-stats/commit/b1be59af85a2a6aae7339dc2319107803b0331d5))
* **asset:** show holdings breakdown popover ([#8](https://github.com/0x1f320/tossinvest-stats/issues/8)) ([8f2bda4](https://github.com/0x1f320/tossinvest-stats/commit/8f2bda4035cbc852cf6db7478ca578204f565599)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **stock:** add per-item KRW/USD display for US stocks ([#6](https://github.com/0x1f320/tossinvest-stats/issues/6)) ([293a6e5](https://github.com/0x1f320/tossinvest-stats/commit/293a6e53141ae19c5e093ac1619109658cc6b973)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **stock:** add stock price menu bar item ([#4](https://github.com/0x1f320/tossinvest-stats/issues/4)) ([63f2cd4](https://github.com/0x1f320/tossinvest-stats/commit/63f2cd4539e3b588a057ef54f8d73018f60c0cd6)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* **stock:** show recent price chart popover ([#5](https://github.com/0x1f320/tossinvest-stats/issues/5)) ([a96de46](https://github.com/0x1f320/tossinvest-stats/commit/a96de46128c487fde3e6c3121a9bb6cc9f408b62)), closes [#11](https://github.com/0x1f320/tossinvest-stats/issues/11)
* warn when macOS hides the menu bar items ([#10](https://github.com/0x1f320/tossinvest-stats/issues/10)) ([ae6499b](https://github.com/0x1f320/tossinvest-stats/commit/ae6499bd362895d240b4517be6456f7818d07559))
