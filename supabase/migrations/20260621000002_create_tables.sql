-- PoC: 高頻度更新データと参照用テーブルの作成 (Issue #9)
--
-- 座標系はすべて WGS84 (SRID 4326) に統一する。
-- 空間検索を行うカラムには GIST インデックスを付与する。
-- 警戒レベルは気象庁の「5段階の警戒レベル」(1〜5) に対応する。

-- updated_at を自動更新するための共通トリガー関数
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================================
-- warnings: 気象庁 警報・注意報
-- =============================================================
create table public.warnings (
  id            bigint generated always as identity primary key,
  area_code     text        not null,                       -- 気象庁エリアコード (例: 東京都 = 130000)
  warning_type  text        not null,                       -- 種別 (例: 大雨, 洪水, 暴風)
  level         smallint    check (level between 1 and 5),  -- 警戒レベル 1〜5
  headline      text,                                       -- 見出し・本文
  issued_at     timestamptz not null,                       -- 発表時刻
  expires_at    timestamptz,                                -- 失効時刻 (未定なら null)
  geom          geometry(MultiPolygon, 4326),               -- 対象範囲 (面情報がある場合のみ)
  source        text        not null default 'jma',
  content_hash  text,                                       -- 差分検出用 (取得スクリプトが書き込む)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- 収集スクリプトの冪等な upsert 対象キー (5分毎ポーリングでの重複行を防ぐ)
  unique (area_code, warning_type, issued_at)
);

comment on table public.warnings is '気象庁の警報・注意報。area_code 単位で更新される。(area_code, warning_type, issued_at) で upsert する。';

create index warnings_area_code_idx  on public.warnings (area_code);
create index warnings_issued_at_idx  on public.warnings (issued_at desc);
create index warnings_geom_gix       on public.warnings using gist (geom);

create trigger warnings_set_updated_at
  before update on public.warnings
  for each row execute function public.set_updated_at();

-- =============================================================
-- earthquakes: 緊急地震速報・地震情報
-- =============================================================
create table public.earthquakes (
  id              bigint generated always as identity primary key,
  event_id        text unique,                      -- 気象庁の地震識別子 (重複登録防止)
  magnitude       numeric(3, 1),                    -- マグニチュード
  depth_km        integer,                          -- 震源の深さ (km)
  epicenter_name  text,                             -- 震源地名
  max_intensity   text,                             -- 最大震度 (例: '5+')
  epicenter_geom  geometry(Point, 4326),            -- 震源の位置
  occurred_at     timestamptz,                      -- 発生時刻
  issued_at       timestamptz not null,             -- 発表時刻
  created_at      timestamptz not null default now()
);

comment on table public.earthquakes is '気象庁の地震情報。event_id で重複登録を防ぐ。';

create index earthquakes_issued_at_idx on public.earthquakes (issued_at desc);
create index earthquakes_geom_gix      on public.earthquakes using gist (epicenter_geom);

-- =============================================================
-- evacuation_orders: 避難指示・高齢者等避難等
-- =============================================================
create table public.evacuation_orders (
  id          bigint generated always as identity primary key,
  area_code   text        not null,                       -- 対象市区町村コード
  area_name   text,                                       -- 対象地域名
  level       smallint    check (level between 1 and 5),  -- 警戒レベル 1〜5
  order_type  text,                                       -- 種別 (例: 避難指示, 高齢者等避難)
  status      text        not null default 'active'
                check (status in ('active', 'lifted')),   -- 発令中 / 解除済み
  issued_at   timestamptz not null,                       -- 発令時刻
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- 冪等な upsert 対象キー。order_type が null でも重複扱いとするため NULLS NOT DISTINCT を使う (PostgreSQL 15+)
  unique nulls not distinct (area_code, order_type, issued_at)
);

comment on table public.evacuation_orders is '自治体の避難情報。status で発令中/解除を管理する。(area_code, order_type, issued_at) で upsert する。';

create index evacuation_orders_area_code_idx on public.evacuation_orders (area_code);
create index evacuation_orders_status_idx    on public.evacuation_orders (status);

create trigger evacuation_orders_set_updated_at
  before update on public.evacuation_orders
  for each row execute function public.set_updated_at();

-- =============================================================
-- shelters: 指定緊急避難場所 (国土地理院・低頻度更新)
-- =============================================================
create table public.shelters (
  id              bigint generated always as identity primary key,
  gsi_id          text unique,                  -- 国土地理院データ上の識別子 (重複登録防止)
  name            text not null,                -- 施設名
  address         text,                         -- 住所
  geom            geometry(Point, 4326) not null, -- 位置 (必須)
  disaster_types  text[] not null default '{}', -- 対応災害種別 (許容値は下記コメント参照)
  capacity        integer,                      -- 収容人数 (不明なら null)
  is_designated   boolean not null default true, -- 指定緊急避難場所か
  content_hash    text,                         -- 差分検出用 (日次取得で未変更ならスキップ)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.shelters is '指定緊急避難場所。geom に GIST インデックスを付与し近傍検索に用いる。';
-- disaster_types の許容値は災害種別の英小文字スラッグに統一する (収集スクリプト間での表記揺れ防止):
--   flood (洪水), landslide (土砂災害), storm_surge (高潮), earthquake (地震),
--   tsunami (津波), fire (大規模な火事), inland_flood (内水氾濫), volcano (火山現象)
comment on column public.shelters.disaster_types is '対応災害種別の英小文字スラッグ配列: flood, landslide, storm_surge, earthquake, tsunami, fire, inland_flood, volcano';

create index shelters_geom_gix           on public.shelters using gist (geom);
create index shelters_disaster_types_gix on public.shelters using gin (disaster_types);

create trigger shelters_set_updated_at
  before update on public.shelters
  for each row execute function public.set_updated_at();
