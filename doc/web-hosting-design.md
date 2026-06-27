# Web アプリ ホスティング選定・設計

> 関連 Issue: #3
> 対象: SafeTabi の Web アプリ（PWA）のホスティング環境とデプロイパイプライン

## 1. 背景と要件

SafeTabi の Web アプリは「災害時に通信が不安定な観光地でも動くこと」が最重要要件である（[HANDOFF.md](./HANDOFF.md)）。ホスティング選定では以下を評価軸とする。

| 評価軸 | 内容 |
|---|---|
| 商用利用 | SafeTabi はビジネスベンチャー（BtoG/BtoB）であり、無料枠でも**商用利用が許可**されること |
| PWA / Service Worker | オフライン対応の要。Service Worker を素直に配信できること |
| プッシュ通知 | FCM（Android）/ iOS Web Push 連携のしやすさ |
| オフラインキャッシュ配信 | 避難所・ハザードデータをローカルキャッシュできること |
| エッジ配信 | 訪日外国人の端末から低遅延でアクセスできること |
| 無料枠 PoC | コスト最小化（[decisions.md](./decisions.md) 方針）で運用できること |
| 将来のスケーラビリティ | 全国展開フェーズに耐えること |

なお、低頻度ハザードデータは別途 CDN（jsDelivr）で静的配信し（[cdn-geojson-design.md](./cdn-geojson-design.md)）、高頻度データは Supabase + PostGIS から取得する（[supabase/README.md](../supabase/README.md)）。ホスティングが担うのは **アプリ本体（フロントエンド + 必要最小限のサーバー処理）** である。

## 2. 選択肢の比較

| サービス | 無料枠の商用利用 | Next.js 親和性 | エッジ | PWA | プッシュ連携 | 全国展開時 |
|---|---|---|---|---|---|---|
| **Cloudflare Pages** | **可（明示的に許可）** | ○（next-on-pages 経由） | ◎ | ◎ | FCM はホスト非依存 | ◎（Workers / R2 と統合、帯域無制限） |
| Vercel | **不可（Hobby は非商用のみ。商用は Pro 必須）** | ◎（純正） | ◎ | ◎ | FCM はホスト非依存 | ○（Pro/有料前提） |
| Firebase Hosting | 可 | △（SSR は Functions 経由） | ○ | ○ | ◎（FCM 純正統合） | △（Next.js SSR が重い） |
| GitHub Pages | 可 | ✕（静的のみ・SSR 不可） | ○ | ○ | ✕（サーバー処理不可） | ✕ |

補足:
- **Vercel Hobby（無料）は利用規約で商用利用が禁止**されており、「プロジェクト制作に関わる者の金銭的利益を目的とするデプロイ」は対象外。SafeTabi は商用ベンチャーのため、PoC でも Hobby は利用できず、無料運用なら選外となる（Vercel を使うなら Pro = $20/月 が必要）。
- **Cloudflare Pages（無料）は商用利用を明示的に許可**し、帯域は無制限。静的アセットへのリクエストは無制限・無料で、動的処理（Pages Functions）は Workers 無料枠（10万リクエスト/日）で賄える。
- **プッシュ通知（FCM）はクライアント SDK + サーバーキーで動作し、ホスティング先に依存しない**。FCM のサーバー送信は、気象庁 API 更新をトリガーにする別系統（GitHub Actions / 将来の Workers）が担う。
- GitHub Pages は静的配信のみで、多言語翻訳など最小限のサーバー処理が載らないため PoC のアプリ本体には不適。

## 3. 決定: Cloudflare Pages（PoC フェーズ）

PoC フェーズの Web アプリホスティングは **Cloudflare Pages（無料プラン）** とする。

### 選定理由

1. **無料プランで商用利用が許可されている**。SafeTabi はビジネスベンチャーであり、コスト最小化方針（decisions.md）と商用利用の両立が必須。Vercel Hobby は非商用限定のためこの時点で選外となる
2. **帯域無制限・静的リクエスト無料**で、訪日外国人の端末からエッジ配信を低遅延で提供できる。PWA（Service Worker）配信もそのまま行える
3. **エコシステムが一貫する**。データ収集基盤はフェーズ3で **Cloudflare Workers cron** への移行が想定され（HANDOFF.md）、CDN も将来 **Cloudflare R2** へ移行する案がある（cdn-geojson-design.md）。ホスティングを Cloudflare に揃えることでエッジ基盤を一系統に統一できる
4. 動的処理（SSR / API）は **Pages Functions（Workers 無料枠 10万リクエスト/日）** で賄え、東京都のみの PoC 規模では十分な余裕がある
5. プッシュ通知は FCM（クライアント SDK）で実現し、**ホスティング先に依存しない**

### トレードオフと申し送り

- **Next.js の親和性は Vercel ほど"設定ゼロ"ではない**。Cloudflare Pages 上で Next.js を動かすには `@cloudflare/next-on-pages`（または OpenNext の Cloudflare アダプタ）を介する必要がある。PoC の立ち上げに致命的ではないが、アダプタ非対応の Next.js 機能（一部の Node.js ランタイム依存 API 等）を避ける必要がある
- そのため、**実装時は Web 標準 API（Fetch / Web Crypto 等）と Edge ランタイムを基本とし、Node.js 固有 API への依存を最小化する**
- 全国展開フェーズでも Cloudflare（Pages / Workers / R2）を継続利用する想定で、スケール時の基盤分断を避ける

## 4. デプロイパイプライン設計

### 構成

```
GitHub (monorepo: app/)
  │  push / pull_request
  ▼
Cloudflare Pages（GitHub 連携）
  ├── main へのマージ        → Production デプロイ
  └── PR / フィーチャーブランチ → Preview デプロイ（自動 URL 発行）
```

- **Git 連携によるデプロイ**を採用し、専用の CI YAML は持たない（Cloudflare Pages の GitHub 連携が push を検知してビルド・デプロイする）
- モノレポのため、Pages プロジェクトの **Root Directory（ビルドのルート）を `app/`** に設定する
- **Production**: `main` ブランチ。**Preview**: PR ごとに自動デプロイし、レビュー時に実画面を確認できるようにする
- 無料枠のビルド回数（500 ビルド/月）節約のため、`app/` 配下に変更が無いコミットではビルドをスキップする設定を検討する
- ビルド/Lint/型チェック等のコード品質ゲートは別途 GitHub Actions（アプリ実装フェーズで追加）で担い、Pages はデプロイに専念する

### 環境変数

- Supabase 接続情報（`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`）など公開可能な値はクライアントに渡す。秘密鍵（service_role）は **アプリには載せない**（収集スクリプト専用）
- 値は Cloudflare Pages のプロジェクト設定（Production / Preview で分離）で管理し、リポジトリには `.env.example` の形でキー名のみ記載する（実装フェーズで追記）

## 5. 決定事項（Issue #3 のチェックリスト）

- [x] **ホスティングサービスを選定する** → Cloudflare Pages（無料・商用利用可）。全国展開フェーズも継続利用
- [x] **基本的なデプロイパイプライン設計を行う** → Cloudflare Pages の GitHub 連携で main=Production / PR=Preview。Root Directory は `app/`

## 6. 将来の申し送り

- 全国展開フェーズでも Cloudflare（Pages / Workers / R2）を継続し、収集基盤・CDN・ホスティングのエッジ基盤を統一する
- プッシュ通知の送信基盤（FCM サーバー送信）はホスティングとは別系統で設計する（別 Issue）。iOS は Web Push（iOS 16.4+・ホーム画面追加が前提）となり APNs を直接は叩かない点に注意し、詳細は通知設計 Issue で精査する
- 多言語翻訳など最小限のサーバー処理は Pages Functions（Workers）で実装し、Web 標準 API を基本とする
