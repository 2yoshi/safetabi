# Decisions

プロジェクトで合意した主要な意思決定の記録。日付・背景・代替案・選定理由を残します。

新しい決定は **下に追記** してください（時系列順）。

---

## 2026-06-20: リポジトリ構成をモノレポとする

- **決定**: 単一リポジトリ `safetabi` 内に `app/`, `data-collector/` をディレクトリ分割するモノレポ構成
- **代替案**: `safetabi` と `safetabi-data-collector` を別リポジトリに分割
- **選定理由**:
  - PoC フェーズの管理コストが低い
  - データ収集とアプリで仕様変更が連動する場面が多いと想定
  - 後から分割も可能
- **関連**: Issue #1 / PR #15

---

## 2026-06-20: PoC 対象自治体を東京都とする

- **決定**: PoC 対象を **東京都**（気象庁 area_code: `130000`）に確定
- **代替案**: 京都府（260000）、大阪府（270000）
- **選定理由**:
  - 訪日外国人観光客数が最多で、サービス本来のターゲットと一致
  - 洪水・地震・津波・土砂と災害種別が網羅され、データ量・多様性ともに検証に十分
  - 自治体側の多言語化が既に進んでおり、アラートテキストの翻訳精度比較がしやすい
  - 気象庁 area_code（130000）はすでに動作確認済み
- **スコープ補足**:
  - 気象庁警報・避難指示: area_code `130000` のみ取得
  - 国土地理院 避難場所 CSV: 東京都のレコードのみ抽出
  - 国土数値情報 ハザード SHP: 東京都の Shapefile のみ取得
- **関連**: Issue #2

---

## 2026-06-21: 低頻度ハザードデータの配信方式を GitHub リポジトリ + jsDelivr とする

- **決定**: 低頻度更新のハザードポリゴン（洪水・土砂・津波）と避難場所一覧は、静的 GeoJSON としてビルドし **GitHub リポジトリ + jsDelivr CDN**（jsDelivr の `/gh/` ルートでリポジトリから直接配信。GitHub Pages は使わない）で配信する。ファイルは **災害種別 × 市区町村単位**で分割し、タイル化（PMTiles）は PoC では行わない
- **代替案**: Cloudflare R2 + CDN（大容量向き）、Supabase Storage（既存インフラ統合）
- **選定理由**:
  - 完全無料で、既存の GitHub Actions パイプラインからコミットするだけで配置できる（追加の認証・SDK 不要）
  - jsDelivr が HTTPS・CORS・圧縮を標準提供し、PWA から直接 fetch・キャッシュできる
  - 東京都のみの PoC では市区町村分割で jsDelivr の 50MB/ファイル制限に十分収まる
  - 将来は配置先 URL を差し替えるだけで Cloudflare R2 へ移行できる
- **補足**:
  - 高頻度・空間検索が必要なデータ（警報・避難場所近傍検索）は引き続き Supabase + PostGIS
  - 更新検知は `manifest.json`（ファイル一覧 + 内容ハッシュ）を起点とし、本体はバージョン付き URL で長期キャッシュ
  - タイル化（PMTiles）の移行閾値: 単一ファイル 10MB 超、または全国展開フェーズ
- **関連**: Issue #5 / [cdn-geojson-design.md](./cdn-geojson-design.md)

---

## 2026-06-27: Web アプリのホスティングを Vercel とする

- **決定**: PoC フェーズの Web アプリ（PWA）のホスティングは **Vercel（Hobby プラン）** とする。デプロイは Vercel の GitHub 連携で行い、`main` マージ = Production / PR = Preview。モノレポのため Root Directory は `app/`
- **代替案**: Cloudflare Pages（Workers/R2 と統合・全国展開向き）、Firebase Hosting（FCM 純正統合）、GitHub Pages（静的のみ）
- **選定理由**:
  - Next.js との親和性が最も高く、PoC を最速で立ち上げられる（SSR/エッジ/PWA 配信が設定なしで動く）
  - エッジ配信が標準で、訪日外国人の端末から低遅延でアクセスできる
  - 無料の Hobby プランで PoC を運用できる
  - プッシュ通知（FCM）はクライアント SDK で動作しホスティング先に依存しない
- **トレードオフ・申し送り**:
  - データ収集基盤はフェーズ3で Cloudflare Workers、CDN は将来 R2 への移行案があり、エッジ基盤の一貫性は次点
  - **全国展開フェーズでは Cloudflare Pages（+ Workers / R2）への移行を再検討**する
  - 移行コスト削減のため Vercel 固有機能（KV / Postgres / Edge Config 等）への依存を避け、状態は Supabase に寄せる
- **関連**: Issue #3 / [web-hosting-design.md](./web-hosting-design.md)
