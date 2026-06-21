# supabase

PoC 用 Supabase プロジェクトのセットアップとスキーマ定義（Issue #9）。

高頻度更新データ（気象庁の警報・地震・避難情報）と、避難場所の近傍検索（空間検索）を担う **PostgreSQL + PostGIS** レイヤー。低頻度の面データ（ハザードポリゴン）は別途 CDN で静的配信する（[doc/cdn-geojson-design.md](../doc/cdn-geojson-design.md) 参照）。

## ディレクトリ構成

```
supabase/
├── config.toml          # Supabase CLI 設定
└── migrations/          # 適用順に番号付けされた DDL
    ├── 20260621000001_enable_postgis.sql   # PostGIS 拡張の有効化
    ├── 20260621000002_create_tables.sql    # テーブル・インデックス・トリガー
    └── 20260621000003_enable_rls.sql       # RLS（公開データの読み取りのみ許可）
```

## テーブル一覧

| テーブル | 区分 | 用途 | 空間カラム |
|---|---|---|---|
| `warnings` | 高頻度 | 気象庁 警報・注意報 | `geom` (MultiPolygon) |
| `earthquakes` | 高頻度 | 地震情報・緊急地震速報 | `epicenter_geom` (Point) |
| `evacuation_orders` | 高頻度 | 避難指示・高齢者等避難 | なし |
| `shelters` | 低頻度（参照） | 指定緊急避難場所 | `geom` (Point) |

座標系はすべて WGS84（SRID 4326）。空間検索カラムには GIST インデックスを付与済み。

高頻度更新テーブルは収集スクリプトが冪等に upsert できるよう自然キー（UNIQUE 制約）を持つ:

| テーブル | upsert キー |
|---|---|
| `warnings` | `(area_code, warning_type, issued_at)` |
| `earthquakes` | `event_id` |
| `evacuation_orders` | `(area_code, order_type, issued_at)` |
| `shelters` | `gsi_id` |

`warnings` / `shelters` は `content_hash` を持ち、未変更レコードの書き込みをスキップできる。

`shelters.disaster_types` は災害種別の英小文字スラッグ配列で、表記揺れを防ぐため次の値に統一する:
`flood`（洪水）, `landslide`（土砂災害）, `storm_surge`（高潮）, `earthquake`（地震）, `tsunami`（津波）, `fire`（大規模な火事）, `inland_flood`（内水氾濫）, `volcano`（火山現象）。

## セットアップ手順

### 1. Supabase プロジェクトの作成（手動）

1. https://supabase.com でプロジェクトを新規作成する（PoC のためリージョンは Tokyo 推奨）
2. `Project Settings > API` と `Project Settings > Database` から接続情報を控える
3. リポジトリルートで `.env` を用意する:
   ```bash
   cp .env.example .env
   # SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_DB_URL を記入
   ```

### 2. マイグレーションの適用

**方法 A: Supabase CLI（推奨）**

```bash
# CLI: https://supabase.com/docs/guides/cli
supabase link --project-ref <your-project-ref>
supabase db push
```

**方法 B: SQL Editor で手動適用**

CLI を使わない場合は、ダッシュボードの SQL Editor で `migrations/` 内の SQL を**ファイル名の番号順**に貼り付けて実行する。

### 3. 適用後の確認

PostGIS が有効か、テーブルが作成されたかを確認する:

PostGIS の型・関数は `extensions` スキーマにあるため、search_path に依存しないようスキーマ修飾して記述している。

```sql
-- PostGIS のバージョン確認
select extensions.postgis_full_version();

-- 近傍検索の動作確認（東京駅から半径 2km 以内の避難場所）
select name, address,
       extensions.st_distance(
         geom::extensions.geography,
         extensions.st_setsrid(extensions.st_makepoint(139.7671, 35.6812), 4326)::extensions.geography
       ) as distance_m
from public.shelters
where extensions.st_dwithin(
        geom::extensions.geography,
        extensions.st_setsrid(extensions.st_makepoint(139.7671, 35.6812), 4326)::extensions.geography,
        2000
      )
order by distance_m;
```

## RLS（Row Level Security）方針

- 4 テーブルすべてで RLS を有効化し、**SELECT のみを公開**（`anon` / `authenticated`）
- 書き込みは収集スクリプトが `service_role` キーで行う。`service_role` は RLS をバイパスするため、書き込みポリシーは設けていない（＝匿名・ログインユーザーからの書き込みは不可）

## 関連 Issue

- #9 Supabase セットアップ（本ディレクトリ）
- #10〜#12 各データソースの収集スクリプト（このスキーマへ書き込む）
