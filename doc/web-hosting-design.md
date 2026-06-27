# Web アプリ ホスティング選定・設計

> 関連 Issue: #3
> 対象: SafeTabi の Web アプリ（PWA）のホスティング環境とデプロイパイプライン

## 1. 背景と要件

SafeTabi の Web アプリは「災害時に通信が不安定な観光地でも動くこと」が最重要要件である（[HANDOFF.md](./HANDOFF.md)）。ホスティング選定では以下を評価軸とする。

| 評価軸 | 内容 |
|---|---|
| PWA / Service Worker | オフライン対応の要。Service Worker を素直に配信できること |
| プッシュ通知 | FCM（Android）/ APNs（iOS）連携のしやすさ |
| オフラインキャッシュ配信 | 避難所・ハザードデータをローカルキャッシュできること |
| エッジ配信 | 訪日外国人の端末から低遅延でアクセスできること |
| 無料枠 PoC | コスト最小化（[decisions.md](./decisions.md) 方針）で運用できること |
| 将来のスケーラビリティ | 全国展開フェーズに耐えること |

なお、低頻度ハザードデータは別途 CDN（jsDelivr）で静的配信し（[cdn-geojson-design.md](./cdn-geojson-design.md)）、高頻度データは Supabase + PostGIS から取得する（[supabase/README.md](../supabase/README.md)）。ホスティングが担うのは **アプリ本体（フロントエンド + 必要最小限のサーバー処理）** である。

## 2. 選択肢の比較

| サービス | 無料枠 | Next.js 親和性 | エッジ | PWA | プッシュ連携 | 全国展開時 |
|---|---|---|---|---|---|---|
| **Vercel** | あり（Hobby） | ◎（純正） | ◎ | ◎ | FCM はホスト非依存 | ○（有料移行 or 他社移行） |
| Cloudflare Pages | あり（寛大） | ○（next-on-pages 経由） | ◎ | ◎ | FCM はホスト非依存 | ◎（Workers / R2 と統合、低 egress） |
| Firebase Hosting | あり | △（SSR は Functions 経由） | ○ | ○ | ◎（FCM 純正統合） | △（Next.js SSR が重い） |
| GitHub Pages | あり | ✕（静的のみ・SSR 不可） | ○ | ○ | ✕（サーバー処理不可） | ✕ |

補足:
- **プッシュ通知（FCM）はクライアント SDK + サーバーキーで動作し、ホスティング先に依存しない**。よって「Firebase Hosting でないと FCM が使えない」わけではない。FCM のサーバー送信は、気象庁 API 更新をトリガーにする別系統（GitHub Actions / 将来の Cloud Functions / Workers）が担う。
- GitHub Pages は静的配信のみで、多言語翻訳など最小限のサーバー処理（後述）が載らないため PoC のアプリ本体には不適。

## 3. 決定: Vercel（PoC フェーズ）

PoC フェーズの Web アプリホスティングは **Vercel（Hobby プラン）** とする。

### 選定理由

1. **Next.js との親和性が最も高い**。SafeTabi のフロントは Next.js（PWA）を想定しており（リポジトリの `.gitignore` も Next.js 前提）、Vercel は純正ホストとして SSR / ISR / Edge Functions / 画像最適化が設定なしで動く。PoC を最速で立ち上げられる
2. **エッジ配信が標準**で、訪日外国人の端末から低遅延でアクセスできる
3. **PWA（Service Worker）配信が容易**。静的アセット・Service Worker をそのまま配信でき、オフライン要件を満たせる
4. **無料の Hobby プランで PoC を運用可能**（商用利用の範囲・帯域上限は本番移行前に再確認する）
5. プッシュ通知は FCM（クライアント SDK）で実現し、**ホスティング先に依存しない**

### トレードオフと申し送り

- **エコシステムの一貫性は次点**。データ収集基盤はフェーズ3で **Cloudflare Workers cron** への移行が想定されており（HANDOFF.md）、CDN も将来 **Cloudflare R2** へ移行する案がある（cdn-geojson-design.md）。ホスティングだけ Vercel だとエッジ基盤が二系統になる
- そのため **全国展開フェーズでは Cloudflare Pages への移行を再検討する**。Next.js を素直に書いておけば `@cloudflare/next-on-pages` 経由で移行でき、Workers / R2 とエッジ基盤を統一できる
- 移行コストを抑えるため、**Vercel 固有機能（Vercel KV / Vercel Postgres / Edge Config 等）への依存を避ける**。状態は Supabase に寄せ、エッジ処理は標準的な Web 標準 API（Fetch / Web Crypto 等）で書く

## 4. デプロイパイプライン設計

### 構成

```
GitHub (monorepo: app/)
  │  push / pull_request
  ▼
Vercel（GitHub 連携）
  ├── main へのマージ        → Production デプロイ
  └── PR / フィーチャーブランチ → Preview デプロイ（自動 URL 発行）
```

- **Git 連携によるデプロイ**を採用し、専用の CI YAML は持たない（Vercel の GitHub App が push を検知してビルド・デプロイする）
- モノレポのため Vercel プロジェクトの **Root Directory を `app/`** に設定する
- **Production**: `main` ブランチ。**Preview**: PR ごとに自動デプロイし、レビュー時に実画面を確認できるようにする
- ビルド/Lint/型チェック等のコード品質ゲートは別途 GitHub Actions（アプリ実装フェーズで追加）で担い、Vercel はデプロイに専念する

### 環境変数

- Supabase 接続情報（`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`）など公開可能な値はクライアントに渡す。秘密鍵（service_role）は **アプリには載せない**（収集スクリプト専用）
- 値は Vercel のプロジェクト設定（Production / Preview / Development で分離）で管理し、リポジトリには `.env.example` の形でキー名のみ記載する（実装フェーズで追記）

## 5. 決定事項（Issue #3 のチェックリスト）

- [x] **ホスティングサービスを選定する** → Vercel（PoC）。全国展開フェーズで Cloudflare Pages 移行を再検討
- [x] **基本的なデプロイパイプライン設計を行う** → Vercel の GitHub 連携で main=Production / PR=Preview。Root Directory は `app/`

## 6. 将来の申し送り

- 全国展開フェーズで Cloudflare Pages（+ Workers / R2）への移行を評価する。移行容易性のため Vercel 固有機能への依存を避ける
- プッシュ通知の送信基盤（FCM サーバー送信）はホスティングとは別系統で設計する（別 Issue）
- 多言語翻訳など最小限のサーバー処理は、まず Vercel の Edge/Serverless Functions で実装し、移行時は Workers へ載せ替え可能な形にする
