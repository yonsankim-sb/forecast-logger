# Forecast Logger

[Forecast](https://www.forecastapp.com/)（Harvest のスケジューリング用サービス）向けの、
ネイティブ macOS **メニューバー + ウィンドウアプリ**です。Forecast のプロジェクトを
コード（例: `[24-0001] Website Redesign`）で一覧・検索し、**スタート/ストップ式の
タイマーで実作業時間を記録**（ローカル保存）、Forecast に**予定（アロケーション）を
登録**（日付・期間ごとの時間/日）、必要に応じて**記録した時間を Forecast に同期**できます。

SwiftUI（`Window` + ネイティブなメニューバー island）と `URLSession` の async/await で構築。
**サードパーティ依存はありません。** パーソナルアクセストークンは macOS の Keychain のみに保存します。

> **ステータス: 社内プロトタイプ。** チーム内に ad-hoc 署名ビルド（未 Notarize）で共有しています。
> [配布](#配布) と **[SECURITY.md](SECURITY.md)** を参照してください。

> **なぜ Harvest ではなく Forecast？** 当初は Harvest API の*実績時間*向けに仕様策定しましたが、
> 対象アカウントは **Forecast はあるが Harvest がない**ため、書き込み先となる Harvest の
> 時間記録バックエンドが存在しませんでした。Forecast は*計画/スケジューリング*ツールで、
> **アロケーション（予定時間）**を扱い、実績や**タイマーは持ちません**。そのためアプリを
> 再ターゲットし、タイマーの実時間はローカル保存し、Forecast のアロケーションへ*同期*できる形にしています。

---

## 動作要件

- **macOS 13 Ventura** 以降。
- ビルドには **Xcode 16** 以降（プロジェクトは file-system–synchronized group を使用）。
- **タイマー用フォントは同梱していません（下記参照）。**

### タイマー用フォント（ライセンス品 — このリポジトリには含みません）

タイマーの数字は **SHIFTBRAIN Norms Variable**（TT Norms 派生の商用書体）を使用します。
ライセンス品の再配布はできないため、**意図的にコミットしていません**（`.gitignore` で除外）。

- 本来の書体でビルドするには、ライセンス済みのファイルを
  `MacTimeTracker/Resources/Fonts/SHIFTBRAIN Norms Variable.ttf` に置いてください。
  起動時に `AppFonts.registerBundled()` がアプリバンドルへ埋め込み・登録します
  （プロセススコープのみ。システムには一切インストールしません）。
- **無くてもビルド・実行できます**。その場合タイマーはシステムの丸ゴシックへ自動フォールバックします
  （`Font.timer(size:)`）。

---

## 1. トークンを発行する

1. **<https://id.getharvest.com/developers>** にサインイン（Harvest ID サービスは Harvest / Forecast
   両方のトークンを発行します）。
2. **Personal Access Tokens** でトークンを作成してコピー。
3. アカウント ID を手で控える必要はありません（アプリが自動検出します）。

**各自が自分のトークンで接続してください** — 1 つのトークンを共有しないこと。

## 2. ビルドと実行

**Xcode:** `MacTimeTracker.xcodeproj` を開き、**MacTimeTracker** スキームと **My Mac** を選んで **⌘R**。

> 署名: *Sign to Run Locally*（`CODE_SIGN_IDENTITY = "-"`）。有料の Apple Developer アカウント無しでビルドできます。

**コマンドライン** — Release をビルドし `/Applications` へインストール・起動:

```sh
./install-local.command
```

ローカルでビルドしたアプリにはダウンロード隔離フラグが付かないため、Gatekeeper の警告なしで起動します。
ビルド成果物はリポジトリ外
（`~/Library/Developer/Xcode/DerivedData/ForecastLogger-local`）に置かれ、作業ツリーは汚れません。

**テスト**（Swift Testing）:

```sh
xcodebuild test -project MacTimeTracker.xcodeproj -scheme MacTimeTracker \
  -destination 'platform=macOS'
```

## 3. 接続する

1. **Settings**（歯車アイコン）を開く。
2. **Personal Access Token** を貼り付けて **Look up accounts** をタップ。Harvest ID サービスに
   問い合わせ、トークンで到達できる Forecast アカウントを一覧表示し、Account ID を自動入力します。
3. **Test Connection**（Forecast `/whoami` で検証）。成功すると *Connected as \<あなたの名前\>* と表示され、
   トークンを Keychain に保存します。

---

## 機能

| エリア | 内容 |
|---|---|
| **Settings** | トークン入力 + "Look up accounts"（Forecast アカウント ID を自動検出）、"Test Connection"（`/whoami`）。成功時のみ Keychain に保存し、保存済みトークンは編集欄に**再読込しません**。 |
| **メニューバー island** | dynamic-island 風カード: 記録中プロジェクト、大きなライブタイマー、**Record / Pause / Stop**。待機中は island 内でプロジェクトを選べます。 |
| **Record / Pause / Stop** | **実作業時間**を記録。Pause は現在のセグメントを閉じてセッションを保持（Resume 可）、Stop で終了。エントリは**ローカル保存**され再起動後も復元。日付を跨ぐエントリは日ごとに分割。 |
| **予定登録（単日 / 期間）** | Forecast のアロケーション（時間/日）を、日付または期間で作成（メモ付き）。 |
| **Today** | **Logged**（ローカルのタイマー実績）と **Scheduled**（Forecast アロケーション）を切り替え、プロジェクト別に合計表示。更新・削除（確認あり）、日別内訳も。 |
| **記録 → Forecast へ同期** | 各プロジェクトの本日アロケーションを実績時間に書き換え（無ければ作成）、または Forecast を変更しない。プロジェクト単位で耐障害的、失敗時は対象プロジェクトを明示。 |
| **エラー / オフライン** | ネットワーク・認証エラーは閉じられるバナー表示（クラッシュしない）。オフライン時は予定登録/同期を無効化（ローカルタイマーは動作）。 |
| **見た目** | コンパクト/フルウィンドウ、二言語 UI（EN/日本語）、調整可能な Metal "liquid-glass" シェーダー背景。 |

---

## Forecast との通信

リクエストは HTTPS で `https://api.forecastapp.com` へ送られ、以下を付与します:

```
Authorization: Bearer <token>
Forecast-Account-ID: <account id>
User-Agent: Forecast Logger (<your email>)
```

使用エンドポイント: `GET /whoami`, `/projects`, `/clients`, `/assignments`,
`POST`/`PUT`/`DELETE /assignments`。アカウント検出は
`GET https://id.getharvest.com/api/v2/accounts`。

> Forecast の API は**非公式・非公開**です。base URL とペイロード形式はコミュニティで知られているもので、
> 予告なく変わる可能性があります。

---

## プロジェクト構成

```
MacTimeTracker/
├── MacTimeTrackerApp.swift        # @main; 起動時に同梱フォントを登録
├── AppDelegate.swift              # メニューバー常駐でアプリを維持
├── Models/                        # Forecast/Harvest DTO, LoggedEntry
├── Services/
│   ├── ForecastAPI.swift          # 非同期 URLSession クライアント + アカウント検出
│   ├── KeychainStore.swift        # トークン save/load/delete（this-device-only）
│   ├── AppFonts.swift             # 同梱フォントをプロセスに登録
│   ├── TimeLogStore.swift         # ローカルの記録エントリを永続化
│   └── AuthStore.swift            # トークン（Keychain）+ accountId（UserDefaults）
├── ViewModels/TrackerViewModel.swift
├── Views/                         # SwiftUI views + DesignSystem（タイマー書体）
├── Resources/Fonts/               # ライセンスフォントを置く場所（gitignore 済み）
├── Noise.metal                    # liquid-glass シェーダー
└── MacTimeTracker.entitlements    # App Sandbox + 送信ネットワークのみ
MacTimeTrackerTests/               # Swift Testing スイート
install-local.command              # ビルド + /Applications へインストール（自分の Mac 用）
```

- Bundle id: `com.forecastlogger.ForecastLogger`。ローカルデータはすべてこのサンドボックス
  コンテナ（`~/Library/Containers/com.forecastlogger.ForecastLogger/`）に保存されます。
- トークンは Keychain のみ（service `com.forecastlogger.harvest`）。

---

## データの保存場所

すべて**このMac内**で完結します — アプリはサンドボックス化されており、Forecast へ明示的に同期する分を
除いてデータは端末外へ出ません。ローカルデータはすべてアプリのサンドボックスコンテナ配下に保存されます:

```
~/Library/Containers/com.forecastlogger.ForecastLogger/
```

| データ | 保存場所 | 備考 |
|---|---|---|
| **タイマー / 記録した時間**（実行中・一時停止セッション含む） | `…/Data/Library/Preferences/com.forecastlogger.ForecastLogger.plist` の UserDefaults キー `timelog.entries.v1` と `timelog.session.v1`（JSON, `TimeLogStore`） | スタート/ストップ式タイマーの実時間。このMac限定で、再起動・アップデート後も保持（bundle id 不変のため）。 |
| **設定**（アカウントID・連絡先メール・UI言語・シェーダースタイル） | 同じ `…plist`（キー `harvest.accountId`, `harvest.contactEmail`, `app.language`, `shader.glass`） | アカウントIDは秘密情報ではありません。 |
| **パーソナルアクセストークン** | macOS **Keychain** — generic-password、service `com.forecastlogger.harvest`（this-device-only） | plist やログには一切書き込みません。 |

- 記録データの plist は**アプリレベルでは暗号化されません** — at-rest 保護には **FileVault** を有効に。
- ローカルデータを全消去するには: アプリを終了して上記コンテナフォルダを削除し、トークンは
  Settings の **Disconnect**（または Keychain Access → `com.forecastlogger.harvest`）で削除してください。

---

## 配布

このプロトタイプは **ad-hoc 署名・未 Notarize** のため、他の Mac にダウンロードしたコピーは
隔離され、初回起動時に Gatekeeper にブロックされます。社内では DMG として共有します:

1. Release をビルド（`./install-local.command` が同じ成果物をビルド、または Xcode で Archive）。
2. `.app` を以下と一緒に DMG 化:
   - **`Install (first time).command`** — `/Applications` へコピーし、隔離フラグを解除
     （`xattr -dr com.apple.quarantine …`）して起動。
   - 受け取る人向けの短い **README**。
3. 受け取った人は **Install (first time).command を右クリック → 開く** し、Settings で**自分の**トークンを貼り付け。

**恒久運用への移行:** Gatekeeper の摩擦をなくす（かつ Keychain のアイテムを自社の **Team ID** に束縛する）
には、**Developer ID Application** 証明書で署名し **Notarize + staple** します。詳細は
[SECURITY.md](SECURITY.md#distribution-security)。

---

## セキュリティ

資格情報の扱い・データ at-rest・通信・サンドボックス・配布時のセキュリティは
**[SECURITY.md](SECURITY.md)** に記載しています。要約: トークンは **Keychain のみ**（this-device-only）に保存し、
UserDefaults やログには置きません。アプリは Hardened Runtime + 最小エンタイトルメントでサンドボックス化され、
通信は Harvest / Forecast への HTTPS のみです。
