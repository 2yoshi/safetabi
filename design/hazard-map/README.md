# design/hazard-map

現在地ハザードマップ表示機能（Issue #22）の UI モック。各ファイルは静的 HTML で、**ブラウザで直接開いてプレビュー**できる。設計の詳細は [doc/hazard-map-display-design.md](../../doc/hazard-map-display-design.md) を参照。

| ファイル | 内容 |
|---|---|
| `map-main.html` | メイン画面（地図＋現在地＋ハザード重畳＋アラートバー＋リスク要約） |
| `layer-toggle.html` | レイヤー切替（洪水/土砂/津波＋不透明度） |
| `risk-result-card.html` | リスク判定結果カード（危険/安全・想定浸水深・避難導線） |
| `legend.html` | 凡例（浸水深スケール・災害種別、多言語） |
| `attribution-footer.html` | 出典表示（オンライン=地理院/ハザードマップポータル、オフライン判定=国土数値情報） |
| `offline-state.html` | オフライン時表示（地図画像なし＋判定テキスト＋現在地） |
| `language-switcher.html` | 言語切替（日英中(簡/繁)韓） |

地図領域は実装前のためプレースホルダ＋オーバーレイ図形で概念を表現している（実 MapLibre は実装フェーズ）。

## Claude Design への同期

各 HTML の1行目に `<!-- @dsCard group="ハザードマップ" ... -->` マーカーを付与済みで、claude.ai/design のデザインシステムプロジェクトに同期するとカードとして表示される。**同期は接続が有効になった時点で実施予定（現状は後回し）。**
