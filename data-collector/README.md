# data-collector

オープンデータの自動収集スクリプト群。GitHub Actions の cron で定期実行することを想定しています。

## 状態

未着手。Issue #9（Supabase セットアップ）と Issue #2（PoC 対象自治体の選定）の完了後に実装を開始します。

## 想定する構成

```
data-collector/
├── collectors/          # データソースごとの取得ロジック（自治体に依存しない関数として実装）
│   ├── jma.py           # 気象庁 JSON API
│   ├── gsi.py           # 国土地理院 CSV
│   └── ksj.py           # 国土数値情報 SHP
├── run_warnings.py      # 警報・避難指示の収集エントリポイント
├── run_shelters.py      # 避難場所の収集エントリポイント
├── run_hazards.py       # ハザードポリゴンの収集エントリポイント
└── requirements.txt
```

## 設計指針

- データソースごとの取得ロジックは「自治体に依存しない独立した関数」として切り出す（将来のクラウド移行コスト削減のため）
- 差分検出（ハッシュ比較）で変更がなければストレージへの書き込みをスキップする
- エラー時は終了コード非ゼロで返す（GitHub Actions での失敗検知のため）

## 関連 Issue

- #9 Supabase セットアップ
- #10 気象庁 JSON API 取得スクリプト
- #11 国土地理院 CSV 取得スクリプト
- #12 国土数値情報 SHP → GeoJSON 変換
- #13 GitHub Actions ワークフロー設定
- #14 失敗通知設定
