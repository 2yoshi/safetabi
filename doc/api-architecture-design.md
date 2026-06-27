# API サーバー構成設計（Supabase 直接 vs 中間 API レイヤー）

> 関連 Issue: #4
> 対象: クライアントアプリ（Web / 将来のスマホ）からのデータ取得方式

## 1. 背景と要件

SafeTabi のデータは取得経路が 3 系統に分かれる（既存設計の再掲）。

| データ | 取得経路 | 関連設計 |
|---|---|---|
| 高頻度（警報・地震・避難情報・避難場所） | Supabase（PostgreSQL + PostGIS） | [supabase/README.md](../supabase/README.md) |
| 低頻度・面データ（ハザードポリゴン） | 静的 GeoJSON + jsDelivr CDN を直接 fetch | [cdn-geojson-design.md](./cdn-geojson-design.md) |
| アプリ本体 | Cloudflare Pages | [web-hosting-design.md](./web-hosting-design.md) |

本ドキュメントが対象とするのは **Supabase 上のデータをクライアントがどう取得するか** である。ハザード CDN への直接 fetch は本設計の対象外（別系統で確定済み）。

評価軸:
- **PoC のシンプルさ**: コスト最小化方針（[decisions.md](./decisions.md)）に沿い、最小構成で立ち上げられること
- **将来の BtoG / BtoB**: 認証・レート制限・マルチテナントが必要になったときに対応できること
- **RLS で十分か**: 公開オープンデータの読み取り制御が Supabase の RLS で完結するか
- **移行容易性**: Supabase 以外への移行や中間レイヤー追加が後から可能か

## 2. 選択肢の比較

| 観点 | A. Supabase 直接アクセス | B. 中間 API レイヤー |
|---|---|---|
| 構成 | クライアント → Supabase REST（PostgREST）/ RPC | クライアント → API（Pages Functions 等）→ Supabase |
| 実装コスト | 低（サーバー実装不要） | 中〜高（API 実装・運用が増える） |
| 認証・認可 | RLS（公開読み取り）で完結 | アプリ層で自由に制御（APIキー・JWT・テナント分離） |
| レート制限 | Supabase 側の制限に依存 | 自前で制御可能 |
| ビジネスロジック | DB 関数（RPC）に寄せる | API 層に集約できる |
| ベンダー依存 | Supabase に密結合 | 中間層で吸収でき移行が容易 |
| PoC 適性 | ◎ | △（オーバースペック） |

## 3. 決定: A. Supabase 直接アクセス（PoC フェーズ）

PoC フェーズは **クライアントから Supabase へ直接アクセスする構成（A）** とする。

### 選定理由

1. **PoC のスコープ（東京都・公開オープンデータの閲覧）では中間 API レイヤーが提供する価値（認証・マルチテナント・レート制限）がまだ不要**。現時点で B を導入するのはオーバースペックで、コスト最小化方針に反する
2. **公開データの読み取り制御は Supabase の RLS で完結する**。#9 で「SELECT のみ公開（anon / authenticated）、書き込みは service_role のみ」を設定済みで、クライアントは anon キーで安全に読み取れる
3. **空間検索も Supabase で完結できる**。近傍避難所検索などの PostGIS クエリは PostgreSQL 関数（RPC）として定義し、PostgREST 経由で呼び出す（後述）
4. **サーバー実装が不要**で PoC を最速で立ち上げられる

### クライアントが使うインターフェース

| 用途 | 方式 |
|---|---|
| 警報・地震・避難情報の一覧取得 | PostgREST（`/rest/v1/warnings?...` 等、RLS で読み取りのみ） |
| 近傍避難所の検索（PostGIS） | RPC（Postgres 関数。例: `nearby_shelters(lat, lon, radius_m)`）※関数定義は別 Issue で追加 |
| リアルタイム更新（任意） | Supabase Realtime（必要に応じて。PoC では polling でも可） |

- クライアントには **anon キーのみ**を渡す（Cloudflare Pages の環境変数 `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`）。**service_role キーはアプリに載せない**（収集スクリプト専用）
- 空間検索を PostgREST の生フィルタではなく RPC に寄せる理由: `ST_DWithin` 等の空間述語はクライアントから直接表現しづらく、関数化することでクエリの一貫性とインデックス（GIST）利用を担保できる

## 4. PoC フェーズ構成図

```
                        ┌──────────────────────────────┐
   ユーザー端末          │  Cloudflare Pages (アプリ本体)  │
   (Web / PWA)  ───────▶│  Next.js / Service Worker      │
                        └───────────────┬──────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │ ① 高頻度データ                  │ ② 低頻度・面データ                │
        │   (anon キー + RLS)            │   (静的 fetch)                  │
        ▼                               ▼                                │
┌──────────────────────┐      ┌──────────────────────┐                  │
│ Supabase             │      │ jsDelivr CDN         │                  │
│  PostgREST (REST)    │      │  ハザード GeoJSON      │ ◀── 収集パイプライン │
│  RPC (PostGIS 関数)   │      │  (リポジトリ配信)      │                  │
│  Realtime (任意)      │      └──────────────────────┘                  │
└──────────┬───────────┘                                                │
           ▲ 書き込みは service_role のみ（RLS バイパス）                    │
           └──────────────────────── データ収集スクリプト ◀────────────────┘
                                      (GitHub Actions / 将来 Workers)
```

- クライアントは **①Supabase（高頻度）** と **②jsDelivr（低頻度ハザード）** の 2 系統から取得する
- 書き込みは収集スクリプトのみ（service_role）。クライアントは一切書き込まない

## 5. 中間 API レイヤー（B）への移行方針

以下のいずれかが必要になった時点で、Supabase の前段に中間 API レイヤーを導入する。

**移行トリガー**:
- BtoG / BtoB 向けの**認証・APIキー発行・利用課金**が必要になったとき
- **マルチテナント**（自治体・事業者ごとのデータ分離やカスタマイズ）が必要になったとき
- RLS だけでは表現しづらい**複雑な認可・ビジネスロジック**が必要になったとき
- Supabase 固有 API への依存を断ち、**他基盤への移行余地**を確保したいとき

**移行先の方針**:
- 中間 API は **Cloudflare Pages Functions / Workers（Hono 等）** で実装する。ホスティング・収集基盤と同じ Cloudflare に揃え、エッジ基盤を一系統に保つ（エコシステム統一方針と一致）
- 移行容易性のため、PoC 段階から**クライアントのデータ取得処理を 1 つのモジュールに集約**しておく（直接 Supabase 呼び出しを画面コンポーネントに散らさない）。これにより取得先を中間 API へ差し替える際の改修範囲を限定できる

## 6. 決定事項（Issue #4 のチェックリスト）

- [x] **API アクセス方式を決定する** → A. Supabase 直接アクセス（PoC）。anon キー + RLS、空間検索は RPC。中間 API レイヤーは移行トリガー到達時に Cloudflare 上で導入
- [x] **PoC フェーズの構成図を作成する** → §4 の通り

## 7. 将来の申し送り

- 近傍検索用の PostGIS RPC 関数（`nearby_shelters` 等）の定義は別 Issue で追加する
- クライアントのデータ取得は 1 モジュールに集約し、中間 API レイヤー（B）への差し替えコストを抑える
- 中間 API を導入する場合は Cloudflare（Pages Functions / Workers）で実装し、基盤を分断しない
