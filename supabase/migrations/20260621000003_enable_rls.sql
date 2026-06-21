-- PoC: Row Level Security の設定 (Issue #9)
--
-- 方針: これらはすべて「公開オープンデータ」であり、誰でも読み取り可能とする。
-- 書き込みはデータ収集スクリプトが service_role キーで行う。
-- service_role は RLS をバイパスするため、書き込み用ポリシーは作成しない
-- (= 匿名・ログインユーザーからの書き込みは一切許可されない)。

-- 各テーブルで RLS を有効化
alter table public.warnings          enable row level security;
alter table public.earthquakes       enable row level security;
alter table public.evacuation_orders enable row level security;
alter table public.shelters          enable row level security;

-- 読み取り権限を匿名・ログインユーザーに付与
grant select on public.warnings          to anon, authenticated;
grant select on public.earthquakes       to anon, authenticated;
grant select on public.evacuation_orders to anon, authenticated;
grant select on public.shelters          to anon, authenticated;

-- 公開読み取りポリシー (SELECT のみ許可)
create policy "Public read access" on public.warnings
  for select to anon, authenticated using (true);

create policy "Public read access" on public.earthquakes
  for select to anon, authenticated using (true);

create policy "Public read access" on public.evacuation_orders
  for select to anon, authenticated using (true);

create policy "Public read access" on public.shelters
  for select to anon, authenticated using (true);
