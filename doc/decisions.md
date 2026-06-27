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

## 2026-06-27: Web アプリのホスティングを Cloudflare Pages とする

- **決定**: PoC フェーズの Web アプリ（PWA）のホスティングは **Cloudflare Pages（無料プラン）** とする。デプロイは GitHub 連携で行い、`main` マージ = Production / PR = Preview。モノレポのため Root Directory は `app/`
- **代替案**: Vercel（Next.js 純正だが Hobby は非商用限定）、Firebase Hosting（FCM 純正統合）、GitHub Pages（静的のみ）
- **選定理由**:
  - **無料プランで商用利用が許可されている**。SafeTabi は商用ベンチャーのため、Vercel Hobby（非商用限定）は無料運用では選外。コスト最小化方針と商用利用を両立できるのが決め手
  - 帯域無制限・静的リクエスト無料でエッジ配信でき、PWA 配信もそのまま行える
  - データ収集基盤（フェーズ3 = Workers cron）・CDN（将来 R2）と**エコシステムが一貫**し、エッジ基盤を一系統に統一できる
  - 動的処理は Pages Functions（Workers 無料枠 10万リクエスト/日）で賄え、東京都 PoC 規模では十分
  - プッシュ通知（FCM）はクライアント SDK で動作しホスティング先に依存しない
- **トレードオフ・申し送り**:
  - Next.js の親和性は Vercel ほど"設定ゼロ"ではなく、`@cloudflare/next-on-pages`（または OpenNext の Cloudflare アダプタ）を介する。実装は Web 標準 API / Edge ランタイムを基本とし、Node.js 固有 API への依存を最小化する
  - 全国展開フェーズも Cloudflare（Pages / Workers / R2）を継続し、基盤分断を避ける
- **関連**: Issue #3 / [web-hosting-design.md](./web-hosting-design.md)

---

## 2026-06-27: API アクセス方式を Supabase 直接アクセスとする

- **決定**: PoC フェーズはクライアントから **Supabase へ直接アクセス**する（PostgREST / RPC、anon キー + RLS）。中間 API レイヤーは設けない
- **代替案**: 中間 API レイヤー（Cloudflare Pages Functions / Hono 等）を挟む構成
- **選定理由**:
  - PoC スコープ（東京都・公開オープンデータの閲覧）では認証・マルチテナント・レート制限が不要で、中間レイヤーはオーバースペック
  - 公開データの読み取り制御は #9 で設定済みの RLS（SELECT のみ公開）で完結する
  - 近傍避難所などの空間検索は PostGIS の RPC 関数に寄せれば Supabase で完結する
  - サーバー実装が不要で PoC を最速に立ち上げられる
- **補足・申し送り**:
  - クライアントには anon キーのみを渡す（service_role はアプリに載せない）
  - 空間検索 RPC は `SECURITY INVOKER` で定義し RLS をバイパスしないこと（`SECURITY DEFINER` 禁止）
  - anon キーは公開され Cloudflare の前段保護が効かないため、濫用・レート制限は Supabase 組み込みの範囲で運用し、本格対応時は中間 API（B）で制御する
  - 移行容易性のため、クライアントのデータ取得処理は 1 モジュールに集約する
  - 中間 API レイヤー（B）への移行トリガー: BtoG/BtoB の認証・課金、マルチテナント、複雑な認可、濫用対策・レート制限、Supabase 非依存化。移行先は Cloudflare（Pages Functions / Workers）で基盤を分断しない
- **関連**: Issue #4 / [api-architecture-design.md](./api-architecture-design.md)
