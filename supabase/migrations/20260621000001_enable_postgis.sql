-- PoC: PostGIS 拡張を有効化する (Issue #9)
--
-- Supabase では拡張機能は `extensions` スキーマに作成するのが推奨。
-- Supabase のデータベースは search_path に `extensions` を含むため、
-- 以降のテーブル定義では geometry 型をスキーマ修飾なしで参照できる。
create extension if not exists postgis with schema extensions;
